local uv = vim.loop
local U = {}

function U.notify(msg, opts, level)
    if opts and opts.notify == false then return end
    vim.notify(msg, (level and vim.log.levels[level]) or vim.log.levels.INFO, { title = "live-server.nvim" })
end

function U.joinpath(...)
    local sep = package.config:sub(1, 1)
    return table.concat({ ... }, sep)
end

function U.dirname(p) return p:match("^(.*)[/\\]") or "." end

function U.basename(p) return (p:gsub("[/\\]+$", "")):match("([^/\\]+)$") or p end

function U.find_git_root()
    local cwd = uv.cwd()
    local sep = package.config:sub(1, 1)
    local cur = cwd
    while cur and #cur > 0 do
        local candidate = U.joinpath(cur, ".git")
        if uv.fs_stat(candidate) then return cur end
        local parent = cur:match(("^(.*)%s[^%s]+$"):format(sep, sep))
        if not parent or parent == cur then break end
        cur = parent
    end
    return nil
end

function U.url_decode(s)
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

function U.url_encode(s)
    return (tostring(s):gsub("([^%w%-%._~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

function U.path_has_prefix(path, prefix)
    local sep = package.config:sub(1, 1)
    if prefix:sub(-1) ~= sep then prefix = prefix .. sep end
    return path == prefix:sub(1, -2) or path:sub(1, #prefix) == prefix
end

function U.html_escape(s)
    local map = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;' }
    return (tostring(s):gsub("[&<>\"]", map):gsub("'", map["'"]))
end

-- Open URL in default browser (portable)
function U.open_browser(url)
    if vim.ui and vim.ui.open then
        local ok = pcall(vim.ui.open, url)
        if ok then return end
    end
    local sys = (jit and jit.os) or uv.os_uname().sysname
    if sys == "Windows" or sys == "Windows_NT" then
        vim.schedule(function() vim.fn.jobstart({ "cmd.exe", "/c", "start", "", url }, { detach = true }) end)
    elseif sys == "OSX" or sys == "Darwin" then
        vim.schedule(function() vim.fn.jobstart({ "open", url }, { detach = true }) end)
    else
        vim.schedule(function() vim.fn.jobstart({ "xdg-open", url }, { detach = true }) end)
    end
end

-- Telescope presence
local function has_telescope() return pcall(require, "telescope") end

-- Generic list picker
function U.pick_list(opts, cb)
    local title = (opts and opts.title) or "Select"
    local items = (opts and opts.items) or {}
    if has_telescope() then
        local pickers, finders, conf = require("telescope.pickers"), require("telescope.finders"),
            require("telescope.config").values
        local actions, action_state = require("telescope.actions"), require("telescope.actions.state")
        pickers.new({}, {
            prompt_title = title,
            finder = finders.new_table({ results = items }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    local val = entry and (entry.value or entry[1] or entry.text)
                    cb(val)
                end)
                return true
            end,
        }):find()
    else
        vim.ui.select(items, { prompt = title }, cb)
    end
end

-- Directory scanner (simple, bounded depth)
local function scan_dirs(root, maxdepth, limit)
    maxdepth = maxdepth or 3
    limit = limit or 500
    local res, q = {}, { { root, 0 } }
    while #q > 0 and #res < limit do
        local item = table.remove(q, 1)
        local dir, depth = item[1], item[2]
        local it = uv.fs_scandir(dir)
        if it then
            while true do
                local name, t = uv.fs_scandir_next(it)
                if not name then break end
                if t == "directory" and name:sub(1, 1) ~= "." then
                    local full = U.joinpath(dir, name)
                    table.insert(res, full)
                    if depth < maxdepth then table.insert(q, { full, depth + 1 }) end
                end
            end
        end
    end
    table.sort(res)
    return res
end

-- Path picker (Telescope-first): choose file OR directory
function U.pick_path(cb)
    if has_telescope() then
        local pickers, finders, conf = require("telescope.pickers"), require("telescope.finders"),
            require("telescope.config").values
        local actions, action_state = require("telescope.actions"), require("telescope.actions.state")
        local cwd = uv.cwd()
        local menu = {
            { "📄 Pick a file…", "__PICK_FILE__" },
            { "📁 Pick a directory…", "__PICK_DIR__" },
            { "📌 Current file", "__CUR_FILE__" },
            { "📂 Current directory", "__CUR_DIR__" },
        }
        local git_root = U.find_git_root()
        if git_root then table.insert(menu, { "🪵 Git root", "__GIT_ROOT__" }) end

        pickers.new({}, {
            prompt_title = "LiveServer — Choose path",
            finder = finders.new_table({
                results = menu,
                entry_maker = function(e) return { value = e[2], display = e[1], ordinal = e[1] } end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    local tag = entry and entry.value
                    if tag == "__PICK_FILE__" then
                        require("telescope.builtin").find_files({
                            prompt_title = "LiveServer — Pick file",
                            cwd = cwd,
                            attach_mappings = function(pb)
                                actions.select_default:replace(function()
                                    local e = action_state.get_selected_entry()
                                    actions.close(pb)
                                    cb(e and (e.path or e.filename or e[1]))
                                end); return true
                            end,
                        })
                    elseif tag == "__PICK_DIR__" then
                        local dirs = scan_dirs(cwd, 4, 800)
                        if #dirs == 0 then return cb(cwd) end
                        U.pick_list({ title = "Pick directory", items = dirs }, cb)
                    elseif tag == "__CUR_FILE__" then
                        local f = vim.api.nvim_buf_get_name(0)
                        if f == "" then
                            U.notify("No current file.", { notify = true }, "WARN"); return
                        end
                        cb(f)
                    elseif tag == "__CUR_DIR__" then
                        cb(cwd)
                    elseif tag == "__GIT_ROOT__" then
                        cb(git_root)
                    end
                end)
                return true
            end,
        }):find()
    else
        -- Fallback: simple UI
        vim.ui.select({ "Pick file", "Pick directory", "Current file", "Current directory" },
            { prompt = "LiveServer — Choose path" }, function(choice)
            if choice == "Pick file" then
                vim.ui.input({ prompt = "File path: " }, cb)
            elseif choice == "Pick directory" then
                vim.ui.input({ prompt = "Directory path: ", default = uv.cwd() }, cb)
            elseif choice == "Current file" then
                local f = vim.api.nvim_buf_get_name(0)
                if f == "" then
                    U.notify("No current file.", { notify = true }, "WARN"); return
                end
                cb(f)
            elseif choice == "Current directory" then
                cb(uv.cwd())
            end
        end)
    end
end

-- Port picker
function U.pick_port(opts, cb)
    local default = tostring((opts and opts.default) or 8000)
    local known = {}
    for _, p in ipairs(opts.known_ports or {}) do table.insert(known, tostring(p)) end
    table.sort(known, function(a, b) return tonumber(a) < tonumber(b) end)
    local list = {}
    local seen = {}
    for _, p in ipairs(known) do table.insert(list, p); seen[p] = true end
    if not seen[default] then table.insert(list, default .. " (default)") end
    table.insert(list, "Other…")

    local function finish_with_port(p)
        if not p then return cb(nil) end
        p = tonumber(tostring(p):match("^(%d+)"))
        if not p or p <= 0 or p > 65535 then
            return U.notify("Invalid port.", { notify = true }, "ERROR")
        end
        cb(p)
    end

    U.pick_list({ title = "Pick Port (default " .. default .. ")", items = list }, function(choice)
        if not choice then return cb(nil) end
        if choice == "Other…" then
            vim.ui.input({ prompt = "Port: ", default = default }, finish_with_port)
        else
            finish_with_port(choice)
        end
    end)
end

-- .liveignore parser
function U.parse_liveignore(root)
    local path = U.joinpath(root, ".liveignore")
    local fd = uv.fs_open(path, "r", 438)
    if not fd then return {} end
    local stat = uv.fs_fstat(fd)
    if not stat then uv.fs_close(fd); return {} end
    local content = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    if not content then return {} end
    local patterns = {}
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local pat = line:gsub("([%.%+%-%^%$%(%)%%])", "%%%1"):gsub("%*", ".*")
            table.insert(patterns, pat)
        end
    end
    return patterns
end

function U.match_ignore(path, patterns)
    for _, pat in ipairs(patterns) do
        if path:find(pat) then return true end
    end
    return false
end

return U
