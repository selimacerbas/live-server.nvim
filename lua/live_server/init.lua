local M = {}

local util   = require("live_server.util")
local server = require("live_server.server")

local defaults = {
  default_port  = 4070,
  open_on_start = true,
  notify        = true,
  headers       = { ["Cache-Control"] = "no-cache" },

  live_reload = {
    enabled       = true,  -- watch files & push SSE “reload”
    inject_script = true,  -- inject <script src="/__live/script.js">
    debounce      = 120,   -- ms
  },

  directory_listing = {
    enabled     = true,    -- keep simple listing if no index.html
    show_hidden = false,
  },
}

M.opts = vim.deepcopy(defaults)
M.state = { servers = {}, opened_ports = {} } -- [port] = inst; opened_ports[port]=true

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

-- Start server for a path (file or directory) on a port
local function start_for_path(path, port)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return util.notify("Path not found: " .. path, M.opts, "ERROR")
  end
  local root, index = path, nil
  if stat.type == "file" then
    root  = util.dirname(path)
    index = path
  end

  local s = M.state.servers[port]
  if s then
    server.update_target(s, root, index)
    util.notify(("LiveServer %d retargeted → %s%s")
      :format(port, root, index and (" (index " .. util.basename(index) .. ")") or ""), M.opts)
  else
    local ok, inst_or_err = pcall(server.start, {
      port = port,
      root = root,
      default_index = index,
      headers = M.opts.headers,
      live = {
        enabled       = M.opts.live_reload.enabled,
        inject_script = M.opts.live_reload.inject_script,
        debounce      = M.opts.live_reload.debounce,
      },
      features = {
        dirlist = {
          enabled     = M.opts.directory_listing.enabled,
          show_hidden = M.opts.directory_listing.show_hidden,
        },
      },
    })
    if not ok then
      return util.notify(("Port %d in use or failed to bind: %s"):format(port, inst_or_err), M.opts, "ERROR")
    end
    M.state.servers[port] = inst_or_err
    util.notify(("LiveServer %d started → %s"):format(port, root), M.opts)
  end

  if M.opts.open_on_start then
    util.open_browser(("http://127.0.0.1:%d/"):format(port))
    M.state.opened_ports[port] = true
  end
end

-- Public: pick path (Telescope) then port → start
function M.start_picker()
  util.pick_path(function(picked_path)
    if not picked_path or picked_path == "" then return end
    util.pick_port({ default = M.opts.default_port, known_ports = vim.tbl_keys(M.state.servers) }, function(port)
      if not port then return end
      start_for_path(picked_path, tonumber(port))
    end)
  end)
end

-- Open an existing server (ours or external) in browser via port picker
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
    if not s then return util.notify("No live-server instance on that port.", M.opts, "WARN") end
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
    if not s then return util.notify("No live-server instance on that port.", M.opts, "WARN") end
    local enabled = server.enable_live(s, not server.is_live_enabled(s))
    util.notify(("Live-reload %s on %d"):format(enabled and "ENABLED" or "DISABLED", port), M.opts)
  end)
end

-- Stop
function M.stop_one()
  local ports = vim.tbl_keys(M.state.servers)
  if #ports == 0 then
    return util.notify("No live-server instances to stop.", M.opts, "WARN")
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
