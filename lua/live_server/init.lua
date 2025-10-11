local M        = {}

local util     = require("live_server.util")
local server   = require("live_server.server")

local defaults = {
    default_port = 4070,
    open_on_start = true,
    notify = true,
    reuse_browser = true,
    headers = { ["Cache-Control"] = "no-cache" },

    live_reload = {
        enabled = true,   -- watch files and push SSE “reload” to clients
        inject_script = true, -- auto-inject <script src="/__live/script.js"> into served HTML
        debounce = 120,   -- ms debounce for rapid FS changes
    },

    directory_listing = {
        enabled = true,
        show_hidden = false, -- set true to list dotfiles
    },

    markdown = {
        enabled = true, -- render *.md with a minimal Lua renderer
    },
}

M.opts         = vim.deepcopy(defaults)
M.state        = {
    -- [port] = server_instance
    servers = {},
    opened_ports = {}, -- [port] = true once opened in browser
}

---@param opts table|nil
function M.setup(opts)
    M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

-- Resolve roots for three modes
local function resolve_roots(mode)
    if mode == "file" then
        local f = vim.api.nvim_buf_get_name(0)
        assert(f ~= "", "No file name for current buffer.")
        local dir = util.dirname(f)
        return dir, f
    elseif mode == "dir" then
        return vim.loop.cwd(), nil
    elseif mode == "root" then
        local root = util.find_git_root() or vim.loop.cwd()
        return root, nil
    else
        error("Unknown mode: " .. tostring(mode))
    end
end

local function start_for(mode, port)
    local root, index = resolve_roots(mode)
    local s = M.state.servers[port]
    if s then
        server.update_target(s, root, index)
        util.notify(("LiveServer %d retargeted to %s%s")
            :format(port, root, index and (" (index " .. util.basename(index) .. ")") or ""), M.opts)
    else
        local ok, new_srv_or_err = pcall(server.start, {
            port = port,
            root = root,
            default_index = index,
            headers = M.opts.headers,
            live = {
                enabled = M.opts.live_reload.enabled,
                inject_script = M.opts.live_reload.inject_script,
                debounce = M.opts.live_reload.debounce,
            },
            features = {
                dirlist  = { enabled = M.opts.directory_listing.enabled, show_hidden = M.opts.directory_listing.show_hidden },
                markdown = { enabled = M.opts.markdown.enabled },
            },
        })
        if not ok then
            util.notify(("Port %d in use or failed to bind: %s"):format(port, new_srv_or_err), M.opts, "ERROR")
            return
        end
        M.state.servers[port] = new_srv_or_err
        util.notify(("LiveServer %d started → %s"):format(port, root), M.opts)
    end

    if M.opts.open_on_start then
        util.open_browser(("http://127.0.0.1:%d/"):format(port))
        M.state.opened_ports[port] = true
    end
end

-- PUBLIC API
function M.start_on_file_with_port(port) start_for("file", port) end

function M.start_on_dir_with_port(port) start_for("dir", port) end

function M.start_on_root_with_port(port) start_for("root", port) end

-- Picker helpers
local function pick_port_then(cb)
    util.pick_port({
        default = M.opts.default_port,
        known_ports = vim.tbl_keys(M.state.servers),
    }, function(port)
        if not port then return end
        cb(tonumber(port))
    end)
end

function M.start_on_file() pick_port_then(M.start_on_file_with_port) end

function M.start_on_dir() pick_port_then(M.start_on_dir_with_port) end

function M.start_on_root() pick_port_then(M.start_on_root_with_port) end

-- Open existing port in browser (can be external servers too)
function M.open_existing()
    util.pick_port({
        default = M.opts.default_port,
        known_ports = vim.tbl_keys(M.state.servers),
        title = "Open http://127.0.0.1:<port>/ in Browser",
    }, function(port)
        if not port then return end
        util.open_browser(("http://127.0.0.1:%d/"):format(port))
        M.state.opened_ports[tonumber(port)] = true
    end)
end

-- Live-reload controls
function M.force_reload()
    util.pick_port({
        default = M.opts.default_port,
        known_ports = vim.tbl_keys(M.state.servers),
        title = "Force reload (pick port)",
    }, function(port)
        if not port then return end
        local s = M.state.servers[tonumber(port)]
        if not s then
            util.notify("No live-server instance on that port.", M.opts, "WARN")
            return
        end
        server.reload(s, "manual")
    end)
end

function M.toggle_livereload()
    util.pick_port({
        default = M.opts.default_port,
        known_ports = vim.tbl_keys(M.state.servers),
        title = "Toggle live-reload (pick port)",
    }, function(port)
        if not port then return end
        local s = M.state.servers[tonumber(port)]
        if not s then
            util.notify("No live-server instance on that port.", M.opts, "WARN")
            return
        end
        local enabled = server.enable_live(s, not server.is_live_enabled(s))
        util.notify(("Live-reload %s on %d"):format(enabled and "ENABLED" or "DISABLED", port), M.opts)
    end)
end

-- Dirlist / Markdown toggles
function M.toggle_dirlist()
    util.pick_port({
        default = M.opts.default_port,
        known_ports = vim.tbl_keys(M.state.servers),
        title = "Toggle directory listing (pick port)"
    }, function(port)
        if not port then return end
        local s = M.state.servers[tonumber(port)]
        if not s then return util.notify("No live-server on that port.", M.opts, "WARN") end
        local enabled = server.set_dirlist(s, not server.is_dirlist_enabled(s))
        util.notify(("Directory listing %s on %d"):format(enabled and "ENABLED" or "DISABLED", port), M.opts)
    end)
end

function M.toggle_markdown()
    util.pick_port({
        default = M.opts.default_port,
        known_ports = vim.tbl_keys(M.state.servers),
        title = "Toggle markdown rendering (pick port)"
    }, function(port)
        if not port then return end
        local s = M.state.servers[tonumber(port)]
        if not s then return util.notify("No live-server on that port.", M.opts, "WARN") end
        local enabled = server.set_markdown(s, not server.is_markdown_enabled(s))
        util.notify(("Markdown rendering %s on %d"):format(enabled and "ENABLED" or "DISABLED", port), M.opts)
    end)
end

-- Stop
function M.stop_one()
    local ports = vim.tbl_keys(M.state.servers)
    if #ports == 0 then
        util.notify("No live-server instances to stop.", M.opts, "WARN")
        return
    end
    util.pick_list({
        title = "Stop LiveServer on Port",
        items = vim.tbl_map(function(p) return tostring(p) end, ports),
    }, function(choice)
        if not choice then return end
        local port = tonumber(choice)
        local s = M.state.servers[port]
        if s then
            server.stop(s)
            M.state.servers[port] = nil
            util.notify(("Stopped LiveServer %d"):format(port), M.opts)
        end
    end)
end

function M.stop_all()
    for port, s in pairs(M.state.servers) do
        server.stop(s)
        M.state.servers[port] = nil
    end
    util.notify("Stopped all LiveServer instances.", M.opts)
end

return M
