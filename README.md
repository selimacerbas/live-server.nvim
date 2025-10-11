# live-server.nvim

A tiny, zero-dependency **local web server** for Neovim — written in pure Lua with `vim.loop`.
Start a server on any file or folder, auto-reload the browser on save, and quickly reopen existing ports.

* **Pure Lua**: no npm, no Python, no binaries.
* **Local-only**: binds to `127.0.0.1` (loopback).
* **SSE live-reload**: instant page refresh on file changes (debounced).
* **Directory listing**: clean index when no `index.html` exists.
* **Telescope UX**: pick a path (file or directory) and a port from a friendly picker.
* **Which-key friendly**: group label in `init`, real mappings in `keys`, no conflicts.
* **Same-port retargeting**: starting on the same port updates the served root/index (reuses the same browser tab/URL).

> 🔒 This plugin serves **only** on `127.0.0.1`. It’s meant for local dev previews, not production.

---

## Requirements

* Neovim **0.8+** (tested on 0.9 / 0.10).
* Linux, macOS, or Windows.
* [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) **recommended** for the best picking UX (falls back to `vim.ui.select/input` if missing).
* [which-key.nvim](https://github.com/folke/which-key.nvim) recommended.

---

## Installation (lazy.nvim)

```lua
-- lua/plugins/live-server.lua
return {
  "selimacerbas/live-server.nvim",
  dependencies = {
    "folke/which-key.nvim",
    "nvim-telescope/telescope.nvim", -- recommended for path picker
  },
  init = function()
    -- which-key group label only (best practice)
    local ok, wk = pcall(require, "which-key")
    if ok then wk.add({ { "<leader>l", group = "LiveServer" } }) end
  end,
  opts = {
    default_port = 4070,
    live_reload = { enabled = true, inject_script = true, debounce = 120 },
    directory_listing = { enabled = true, show_hidden = false },
  },
  -- map to user commands (robust lazy-loading)
  keys = {
    { "<leader>ls", "<cmd>LiveServerStart<cr>",      desc = "Start (pick path & port)" },
    { "<leader>lo", "<cmd>LiveServerOpen<cr>",       desc = "Open existing port in browser" },
    { "<leader>lr", "<cmd>LiveServerReload<cr>",     desc = "Force reload (pick port)" },
    { "<leader>lt", "<cmd>LiveServerToggleLive<cr>", desc = "Toggle live-reload (pick port)" },
    { "<leader>lS", "<cmd>LiveServerStop<cr>",       desc = "Stop one (pick port)" },
    { "<leader>lA", "<cmd>LiveServerStopAll<cr>",    desc = "Stop all" },
  },
  config = function(_, opts)
    require("live_server").setup(opts)
  end,
}
```

---

## Usage

### Start a server

* Press **`<leader>ls`** (or run `:LiveServerStart`).
* Pick a **path** (file or directory), then pick a **port** (default `4070`).
* Your browser opens `http://127.0.0.1:<port>/`.

> If you pick a **file**, the server serves the file’s folder with that file as the default index.
> If you pick the **same port** again later, the server **retargets** to the new root/index instead of creating a new instance.

### Other commands

* **Open existing**: `:LiveServerOpen` — choose a port and open its URL (works even if another app started the server).
* **Force reload**: `:LiveServerReload` — broadcast a manual reload to connected clients.
* **Toggle live-reload**: `:LiveServerToggleLive` — enable/disable file watching + reload for a port.
* **Stop one**: `:LiveServerStop` — choose a port to stop.
* **Stop all**: `:LiveServerStopAll`.

---

## Options

Configured via `require("live_server").setup({...})` or `opts = { ... }` in your lazy spec.

```lua
{
  default_port  = 4070,         -- default suggestion in the port picker
  open_on_start = true,         -- open browser after start/retarget
  notify        = true,         -- use :echo/notify for events
  headers       = { ["Cache-Control"] = "no-cache" }, -- extra response headers

  live_reload = {
    enabled       = true,       -- watch files under the served root
    inject_script = true,       -- injects <script src="/__live/script.js">
    debounce      = 120,        -- ms debounce for rapid changes
  },

  directory_listing = {
    enabled     = true,         -- render an index page if no index.html
    show_hidden = false,        -- include dotfiles in listing
  },
}
```

**How live-reload works:**
A tiny SSE script is injected into **HTML** responses. On any file change under the served root, the server pushes a `reload` event which triggers `location.reload()` in the browser. For non-HTML assets (CSS/JS/image), a full page reload still applies — simple and robust.

---

## Keymaps (default)

All under the which-key group **`<leader>l`**:

| Key          | Action                         |
| ------------ | ------------------------------ |
| `<leader>ls` | Start (pick path & port)       |
| `<leader>lo` | Open existing port in browser  |
| `<leader>lr` | Force reload (pick port)       |
| `<leader>lt` | Toggle live-reload (pick port) |
| `<leader>lS` | Stop one (pick port)           |
| `<leader>lA` | Stop all                       |

> We register only the **group label** in `init`, and return actual mappings in `keys` — the recommended pattern for Folke’s ecosystem to avoid conflicts and enable lazy-loading on keypress.

---

## Design notes

* **Local by default**: binds to `127.0.0.1`. If you want LAN, you can change the bind address in `server.lua` (not recommended for security).
* **Path safety**: requests are realpath-checked to prevent escaping the served root.
* **Index resolution**: directory → `default_index` (if starting from a file) → `index.html` → directory listing.
* **Same port, new path**: reusing the same port retargets the server → same URL, so browsers typically reuse the same tab.

---

## Troubleshooting

* **“Port in use or failed to bind”**
  Another process is using that port (or a previous server didn’t exit cleanly). Pick a different port, or stop the other process.
  You can stop live-server instances via `:LiveServerStop` or `:LiveServerStopAll`.

* **“start() bad argument #2 to 'start' (table expected, got number)”**
  Some `luv` builds expect `fs_event:start(path, {recursive=true}, cb)` while others accept `start(path, cb)`. The plugin tries both. Make sure you’re on the **latest** plugin files.

* **Browser didn’t open**
  We try `vim.ui.open` (NVIM 0.10) and fall back to `xdg-open`/`open`/`start`. If none work, copy the URL from the message and open manually.

* **Live-reload didn’t trigger**

  * It only injects into **HTML** pages.
  * Ensure the served root actually changed (the watcher is per root).
  * Try `:LiveServerToggleLive` off/on, or `:LiveServerReload` to force.

---

## API (for lua configs)

```lua
local ls = require("live_server")

ls.setup({ ... })                -- configure defaults
ls.start_picker()                -- UI flow: pick path, then port
ls.open_existing()               -- pick a port → open in browser
ls.force_reload()                -- broadcast reload to clients
ls.toggle_livereload()           -- enable/disable live-reload for a port
ls.stop_one()                    -- pick a port → stop
ls.stop_all()                    -- stop everything
```

---

## Roadmap

* File-type aware hot-refresh strategies (e.g., CSS inject without full reload).
* Optional LAN binding with allowlist.
* Pluggable middlewares (custom headers, rewrites).
* (Maybe) directory listing customization (sorting, columns).

---

## Contributing

PRs and issues are welcome!
Please include your **OS**, **Neovim version**, and (if relevant) **`vim.loop`/luv** version when reporting bugs. Repro steps make fixes fast. 🙏

---

## License

MIT © Selim Acerbaş
