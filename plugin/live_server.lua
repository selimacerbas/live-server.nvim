-- live-server.nvim needs Neovim 0.10: vim.uv (the test runner needs it too).
-- Refusing here spares an older Neovim a stack trace at first use.
if vim.fn.has("nvim-0.10") == 0 then
    vim.notify_once("live-server.nvim requires Neovim 0.10 or newer", vim.log.levels.ERROR)
    return
end

local LS = require("live_server")

vim.api.nvim_create_user_command("LiveServerStart", function()
    LS.start_picker()
end, { desc = "LiveServer: start (pick path & port)" })

vim.api.nvim_create_user_command("LiveServerOpen", function()
    LS.open_existing()
end, { desc = "LiveServer: open existing server (pick port)" })

vim.api.nvim_create_user_command("LiveServerReload", function()
    LS.force_reload()
end, { desc = "LiveServer: force reload clients (pick port)" })

vim.api.nvim_create_user_command("LiveServerToggleLive", function()
    LS.toggle_livereload()
end, { desc = "LiveServer: toggle live-reload (pick port)" })

vim.api.nvim_create_user_command("LiveServerStop", function()
    LS.stop_one()
end, { desc = "LiveServer: stop one (pick port)" })

vim.api.nvim_create_user_command("LiveServerStatus", function()
    LS.status()
end, { desc = "LiveServer: show running servers" })

vim.api.nvim_create_user_command("LiveServerStopAll", function()
    LS.stop_all()
end, { desc = "LiveServer: stop all" })

vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("live_server", { clear = true }),
    callback = function()
        LS.stop_all()
    end,
    desc = "LiveServer: stop all servers on exit",
})
