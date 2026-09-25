-- lua/live_server/floor.lua
-- The one statement of the Neovim floor, read by the plugin file, the module
-- and the two submodules the plugin-author API loads. It loads on any Neovim
-- that sources a Lua plugin file (0.5 on), so it calls nothing newer. The
-- feature is tested beside the version: a 0.10.0-dev build from before
-- 2023-06-03 answers has("nvim-0.10") without vim.uv.
return {
    ok = vim.uv ~= nil and vim.fn.has("nvim-0.10") == 1,
    message = "live-server.nvim requires Neovim 0.10 or newer; on Neovim 0.9 pin the plugin to v1.5.0",
}
