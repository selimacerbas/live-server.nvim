-- Lightweight user commands (autoload friendly)
local LS = require("live_server")

vim.api.nvim_create_user_command("LiveServerStartFile", function()
    LS.start_on_file()
end, { desc = "LiveServer: start on current file (pick port)" })

vim.api.nvim_create_user_command("LiveServerStartDir", function()
    LS.start_on_dir()
end, { desc = "LiveServer: start on current folder (pick port)" })

vim.api.nvim_create_user_command("LiveServerStartRoot", function()
    LS.start_on_root()
end, { desc = "LiveServer: start at VCS root (pick port)" })

vim.api.nvim_create_user_command("LiveServerOpen", function()
    LS.open_existing()
end, { desc = "LiveServer: open existing server (pick port)" })

vim.api.nvim_create_user_command("LiveServerReload", function()
    LS.force_reload()
end, { desc = "LiveServer: force reload clients (pick port)" })

vim.api.nvim_create_user_command("LiveServerToggleLive", function()
    LS.toggle_livereload()
end, { desc = "LiveServer: toggle live-reload (pick port)" })

vim.api.nvim_create_user_command("LiveServerToggleDirlist", function()
    LS.toggle_dirlist()
end, { desc = "LiveServer: toggle directory listing (pick port)" })

vim.api.nvim_create_user_command("LiveServerToggleMarkdown", function()
    LS.toggle_markdown()
end, { desc = "LiveServer: toggle markdown rendering (pick port)" })

vim.api.nvim_create_user_command("LiveServerStop", function()
    LS.stop_one()
end, { desc = "LiveServer: stop one (pick port)" })

vim.api.nvim_create_user_command("LiveServerStopAll", function()
    LS.stop_all()
end, { desc = "LiveServer: stop all" })
