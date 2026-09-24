-- tests/floor_guard_test.lua
-- The plugin file refuses a Neovim below 0.10 with one ERROR notification
-- and no command, and defines its commands on a supported version.
--
-- Run: nvim --headless -u NONE -l tests/floor_guard_test.lua
local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
H.isolate()
H.rtp()
local plugin_file = H.root .. "/plugin/live_server.lua"

local notices = {}
local real_once = vim.notify_once
vim.notify_once = function(msg, level)
    notices[#notices + 1] = { msg = msg, level = level }
end
local real_has = vim.fn.has
vim.fn.has = function(feature)
    if feature == "nvim-0.10" then
        return 0
    end
    return real_has(feature)
end

H.section("Section 1: below the floor")
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
H.eq(vim.fn.exists(":LiveServerStart"), 0, "no command is defined below the floor")
H.eq(#notices, 1, "exactly one notification")
H.ok(notices[1] ~= nil and notices[1].msg:find("0.10", 1, true) ~= nil, "the notification names the floor")
H.eq(notices[1] and notices[1].level, vim.log.levels.ERROR, "the notification is an ERROR")

H.section("Section 2: at the floor")
vim.fn.has = real_has
vim.notify_once = real_once
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
H.eq(vim.fn.exists(":LiveServerStart"), 2, "the commands are defined on a supported Neovim")
H.eq(vim.fn.exists(":LiveServerStopAll"), 2, "every command is defined")
H.finish()
