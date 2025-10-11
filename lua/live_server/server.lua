local uv   = vim.loop
local util = require("live_server.util")

local S    = {}

local MIME = {
    html = "text/html; charset=utf-8",
    htm = "text/html; charset=utf-8",
    css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8",
    mjs = "application/javascript; charset=utf-8",
    json = "application/json; charset=utf-8",
    txt = "text/plain; charset=utf-8",
    svg = "image/svg+xml",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    ico = "image/x-icon",
    wasm = "application/wasm",
}

local function guess_mime(path)
    local ext = string.match(path, "%.([%w]+)$")
    return (ext and MIME[ext:lower()]) or "application/octet-stream"
end

-- -------- HTTP helpers -----------------------------------------------------

local function write_headers(sock, status, headers)
    local reason = ({
        [200] = "OK", [301] = "Moved Permanently", [302] = "Found", [400] = "Bad Request",
        [404] = "Not Found", [405] = "Method Not Allowed", [500] = "Internal Server Error"
    })[status] or "OK"
    local lines = { ("HTTP/1.1 %d %s\r\n"):format(status, reason) }
    for k, v in pairs(headers or {}) do
        table.insert(lines, ("%s: %s\r\n"):format(k, v))
    end
    table.insert(lines, "\r\n")
    sock:write(table.concat(lines))
end

local function send_response(sock, status, headers, body)
    local h = headers or {}
    if body then h["Content-Length"] = #body end
    h["Connection"] = "close"
    write_headers(sock, status, h)
    if body then sock:write(body) end
    sock:shutdown(function() sock:close() end)
end

local function http_404(sock, path)
    send_response(sock, 404, { ["Content-Type"] = "text/plain; charset=utf-8" }, "404 Not Found: " .. path)
end

local function http_400(sock, msg)
    send_response(sock, 400, { ["Content-Type"] = "text/plain; charset=utf-8" }, "400 " .. (msg or "Bad Request"))
end

local function parse_request(buf)
    local line = buf:match("([^\r\n]+)")
    if not line then return nil end
    local m, path = line:match("^(%u+)%s+([^%s]+)")
    if not m or not path then return nil end
    return { method = m, path = path }
end

-- -------- Path mapping & file read ----------------------------------------

local function sanitize_and_map(req_path, root_real)
    local raw = util.url_decode(req_path)
    if raw:find("^/$") then
        return root_real
    end
    local joined = util.joinpath(root_real, raw:gsub("^/+", ""))
    local ok, real = pcall(uv.fs_realpath, joined)
    if not ok or not real then return nil end
    if not util.path_has_prefix(real, root_real) then return nil end
    return real
end

local function read_file_all(abs_path)
    local fd = uv.fs_open(abs_path, "r", 438)
    if not fd then return nil end
    local stat = uv.fs_fstat(fd)
    if not stat or stat.type ~= "file" then
        uv.fs_close(fd)
        return nil
    end
    local chunk = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    return chunk, stat
end

-- -------- LiveReload (SSE) ------------------------------------------------

local CLIENT_JS = table.concat({
    "!function(){try{",
    "var es=new EventSource('/__live/events');",
    "es.addEventListener('reload',function(){location.reload();});",
    "es.onopen=function(){console.log('[live-server.nvim] connected')};",
    "es.onerror=function(e){console.warn('[live-server.nvim] SSE error',e)};",
    "}catch(e){console.warn('[live-server.nvim] no EventSource',e)}}();",
})

local function sse_accept(inst, sock)
    write_headers(sock, 200, {
        ["Content-Type"] = "text/event-stream",
        ["Cache-Control"] = "no-cache",
        ["Connection"] = "keep-alive",
        ["Access-Control-Allow-Origin"] = "*",
    })
    sock:write("retry: 1000\n\n")
    table.insert(inst.sse_clients, sock)
    sock:read_start(function(err, chunk)
        if err or not chunk then
            sock:close()
            for i, cl in ipairs(inst.sse_clients) do
                if cl == sock then
                    table.remove(inst.sse_clients, i)
                    break
                end
            end
        end
    end)
end

local function sse_broadcast(inst, event, payload)
    local line = ("event: %s\ndata: %s\n\n"):format(event, payload or "{}")
    local i = 1
    while i <= #inst.sse_clients do
        local cl = inst.sse_clients[i]
        local ok = pcall(function() cl:write(line) end)
        if not ok then
            pcall(function() cl:close() end)
            table.remove(inst.sse_clients, i)
        else
            i = i + 1
        end
    end
end

local function schedule_reload(inst, changed_path)
    if not inst.live_enabled then return end
    inst._last_change = changed_path or inst._last_change
    inst.debounce_timer:stop()
    inst.debounce_timer:start(inst.live_debounce, 0, function()
        S.reload(inst, inst._last_change or "")
    end)
end

-- NOTE: luv has two signatures across versions:
--   start(path, opts_table, cb)  -- modern (expects table)
--   start(path, cb)              -- older (no options)
local function start_fs_watch(inst)
    if inst.fs_event then pcall(function() inst.fs_event:stop() end) end
    inst.fs_event = uv.new_fs_event()
    local cb = function(err, _fname, _status)
        if err then return end
        schedule_reload(inst, _fname or "")
    end
    local ok = pcall(function() inst.fs_event:start(inst.root_real, { recursive = true }, cb) end)
    if not ok then
        -- fallback: non-recursive / legacy signature
        pcall(function() inst.fs_event:start(inst.root_real, cb) end)
    end
end

local function stop_fs_watch(inst)
    if inst.fs_event then pcall(function()
            inst.fs_event:stop()
            inst.fs_event:close()
        end) end
    inst.fs_event = nil
end

-- -------- HTML helpers (injection + templating) ---------------------------

local function send_html_with_injection(inst, sock, html, extra_headers)
    if inst.inject_script then
        local tag = '<script src="/__live/script.js"></script>'
        if html:find("</body>", 1, true) then
            html = html:gsub("</body>", tag .. "</body>", 1)
        else
            html = html .. tag
        end
    end
    local headers = { ["Content-Type"] = "text/html; charset=utf-8" }
    for k, v in pairs(extra_headers or {}) do headers[k] = v end
    send_response(sock, 200, headers, html)
end

local function serve_html_file_with_injection(inst, sock, abs_path, extra_headers)
    local body = read_file_all(abs_path)
    if not body then return http_404(sock, abs_path) end
    send_html_with_injection(inst, sock, body, extra_headers)
end

-- -------- Directory listing -----------------------------------------------

local function dir_listing_html(inst, fs_path, req_path)
    local entries = {}
    local iter = uv.fs_scandir(fs_path)
    if not iter then
        return "<!doctype html><meta charset=utf-8><h2>Cannot read directory</h2>"
    end
    if req_path ~= "/" then
        table.insert(entries, { name = "..", is_dir = true, up = true })
    end
    while true do
        local name, t = uv.fs_scandir_next(iter)
        if not name then break end
        if not inst.dir_show_hidden and name:sub(1, 1) == "." then
            -- skip hidden
        else
            table.insert(entries, { name = name, is_dir = (t == "directory") })
        end
    end
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name:lower() < b.name:lower()
    end)

    local rows = {}
    for _, e in ipairs(entries) do
        local label = util.html_escape(e.name)
        local href
        if e.up then
            local parent = req_path:gsub("/+$", ""):match("^(.*)/[^/]*$") or "/"
            href = parent == "" and "/" or parent .. "/"
        else
            href = req_path ..
            (req_path:sub(-1) == "/" and "" or "/") .. util.url_encode(e.name) .. (e.is_dir and "/" or "")
        end
        local icon = e.up and "⤴" or (e.is_dir and "📁" or "📄")
        table.insert(rows, string.format(
            '<tr><td class="ico">%s</td><td><a href="%s">%s</a></td></tr>',
            icon, href, label
        ))
    end

    local title = "Index of " .. util.html_escape(req_path)
    local css = [[
    <style>
      :root{color-scheme:light dark}
      body{font:14px/1.5 system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif;padding:24px;max-width:900px;margin:auto}
      h1{font-size:20px;margin:0 0 16px}
      table{width:100%;border-collapse:collapse}
      td{padding:6px 8px;border-bottom:1px solid rgba(127,127,127,.2)}
      td.ico{width:2rem;text-align:center}
      a{text-decoration:none} a:hover{text-decoration:underline}
    </style>
  ]]
    return string.format([[
  <!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s</head>
  <body><h1>%s</h1><table>%s</table></body></html>
  ]], util.html_escape(title), css, util.html_escape(title), table.concat(rows))
end

-- -------- Static file streaming -------------------------------------------

local function stream_file(sock, abs_path, extra_headers)
    local fd = uv.fs_open(abs_path, "r", 438)
    if not fd then return http_404(sock, abs_path) end
    local stat = uv.fs_fstat(fd)
    if not stat or stat.type ~= "file" then
        uv.fs_close(fd)
        return http_404(sock, abs_path)
    end

    local headers = { ["Content-Type"] = guess_mime(abs_path), ["Content-Length"] = stat.size, ["Connection"] = "close" }
    for k, v in pairs(extra_headers or {}) do headers[k] = v end
    write_headers(sock, 200, headers)

    local offset = 0
    local function read_chunk()
        uv.fs_read(fd, 64 * 1024, offset, function(err_read, data)
            if err_read or not data then
                uv.fs_close(fd)
                sock:shutdown(function() sock:close() end)
                return
            end
            offset = offset + #data
            sock:write(data, function()
                if #data < 64 * 1024 then
                    uv.fs_close(fd)
                    sock:shutdown(function() sock:close() end)
                else
                    read_chunk()
                end
            end)
        end)
    end
    read_chunk()
end

local function serve_path(inst, sock, abs_path, req_path, extra_headers)
    local mime = guess_mime(abs_path)
    if mime:find("^text/html") then
        return serve_html_file_with_injection(inst, sock, abs_path, extra_headers)
    else
        -- FIX: correct call signature (no `inst` param here)
        return stream_file(sock, abs_path, extra_headers)
    end
end

-- -------- Public server API -----------------------------------------------

-- cfg: { port, root, default_index|nil, headers, live={enabled,inject_script,debounce}, features={dirlist={enabled,show_hidden}} }
function S.start(cfg)
    local tcp = uv.new_tcp()
    local ok, bind_err = pcall(function() tcp:bind("127.0.0.1", cfg.port) end)
    if not ok then error(bind_err or "bind failed") end

    local root_real = uv.fs_realpath(cfg.root)
    if not root_real then error("Invalid root: " .. tostring(cfg.root)) end

    local inst = {
        handle          = tcp,
        port            = cfg.port,
        root            = cfg.root,
        root_real       = root_real,
        default_index   = cfg.default_index,
        headers         = cfg.headers or {},
        started_at      = os.time(),

        -- live
        live_enabled    = cfg.live and cfg.live.enabled ~= false,
        inject_script   = cfg.live and cfg.live.inject_script ~= false,
        live_debounce   = (cfg.live and cfg.live.debounce) or 120,
        sse_clients     = {},
        debounce_timer  = uv.new_timer(),

        -- features
        dir_enabled     = not (cfg.features and cfg.features.dirlist and cfg.features.dirlist.enabled == false),
        dir_show_hidden = cfg.features and cfg.features.dirlist and cfg.features.dirlist.show_hidden or false,
    }

    if inst.live_enabled then start_fs_watch(inst) end

    ok, bind_err = pcall(function()
        tcp:listen(128, function(err_listen)
            if err_listen then return end
            local sock = uv.new_tcp()
            tcp:accept(sock)
            sock:read_start(function(err_read, chunk)
                if err_read then
                    sock:close()
                    return
                end
                if not chunk then
                    sock:close()
                    return
                end

                local req = parse_request(chunk)
                if not req then return http_400(sock, "Cannot parse request") end
                if req.method ~= "GET" then
                    return send_response(sock, 405, { ["Content-Type"] = "text/plain" }, "Method Not Allowed")
                end

                -- Special endpoints
                if req.path == "/__live/script.js" then
                    return send_response(sock, 200, { ["Content-Type"] = "application/javascript; charset=utf-8" },
                        CLIENT_JS)
                elseif req.path == "/__live/events" then
                    return sse_accept(inst, sock)
                end

                -- Map path
                local mapped = sanitize_and_map(req.path, inst.root_real)
                if not mapped then return http_404(sock, req.path) end

                local st = uv.fs_stat(mapped)
                if st and st.type == "directory" then
                    local candidate = inst.default_index or util.joinpath(mapped, "index.html")
                    if candidate and uv.fs_stat(candidate) then
                        return serve_path(inst, sock, candidate, req.path, inst.headers)
                    end
                    if inst.dir_enabled then
                        local html = dir_listing_html(inst, mapped, req.path)
                        return send_html_with_injection(inst, sock, html, inst.headers)
                    else
                        return http_404(sock, req.path .. " (no index)")
                    end
                elseif st and st.type == "file" then
                    return serve_path(inst, sock, mapped, req.path, inst.headers)
                else
                    return http_404(sock, req.path)
                end
            end)
        end)
    end)
    if not ok then error(bind_err or "listen failed") end

    return inst
end

function S.stop(inst)
    if inst.debounce_timer then pcall(function()
            inst.debounce_timer:stop()
            inst.debounce_timer:close()
        end) end
    for _, cl in ipairs(inst.sse_clients) do pcall(function() cl:close() end) end
    inst.sse_clients = {}
    stop_fs_watch(inst)
    pcall(function() inst.handle:close() end)
end

function S.update_target(inst, new_root, new_index)
    inst.root = new_root
    inst.root_real = uv.fs_realpath(new_root) or inst.root_real
    inst.default_index = new_index
    if inst.live_enabled then start_fs_watch(inst) end
end

-- Live-reload controls
function S.reload(inst, reason_path)
    local payload = ('{"ts":%d,"path":%q}'):format(os.time(), tostring(reason_path or ""))
    sse_broadcast(inst, "reload", payload)
end

function S.enable_live(inst, enable)
    enable = not not enable
    if inst.live_enabled == enable then return enable end
    inst.live_enabled = enable
    if enable then start_fs_watch(inst) else stop_fs_watch(inst) end
    return enable
end

function S.is_live_enabled(inst) return inst.live_enabled end

return S
