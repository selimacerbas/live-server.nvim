-- tests/floor_guard_test.lua
-- Below Neovim 0.10 the plugin file defines no command and the module
-- answers a config's setup() without loading the plugin, one ERROR
-- notification between them; on a supported version the commands and the
-- exit hook are defined.
--
-- Run: nvim --headless -u NONE -l tests/floor_guard_test.lua
local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
H.isolate()
H.rtp()
local plugin_file = H.root .. "/plugin/live_server.lua"

-- Every refusal is recorded, notify_once's own dedupe aside, so the plugin
-- file's and the module's are checked apart.
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
H.eq(#notices, 1, "the plugin file refuses with one notification")
-- lazy.nvim's config calls setup() whatever the plugin file did.
package.loaded["live_server"] = nil
local setup_ok, setup_err = pcall(function()
    require("live_server").setup({})
end)
H.ok(setup_ok, "setup() raises nothing below the floor" .. (setup_ok and "" or (": " .. tostring(setup_err))))
H.eq(package.loaded["live_server.server"], nil, "the module returns before the server module, and vim.uv, load")
H.eq(#notices, 2, "the module refuses with one notification too")
-- notify_once shows a text once, so one text between the two refusals is
-- one notification on screen, whichever of them runs first.
local texts, all_errors = {}, #notices > 0
for _, notice in ipairs(notices) do
    texts[notice.msg] = true
    all_errors = all_errors and notice.level == vim.log.levels.ERROR
end
H.eq(vim.tbl_count(texts), 1, "the two refusals are one text, so the user sees one notification")
H.ok(notices[1] ~= nil and notices[1].msg:find("0.10", 1, true) ~= nil, "the notification names the floor")
H.ok(all_errors, "every refusal is an ERROR")

H.section("Section 2: at the floor")
vim.fn.has = real_has
vim.notify_once = real_once
package.loaded["live_server"] = nil
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
H.ok(package.loaded["live_server.server"] ~= nil, "the plugin's own module loads on a supported Neovim")
H.eq(vim.fn.exists(":LiveServerStart"), 2, "the commands are defined on a supported Neovim")
H.eq(vim.fn.exists(":LiveServerStopAll"), 2, "every command is defined")
local hooked, hooks = pcall(vim.api.nvim_get_autocmds, { group = "live_server", event = "VimLeavePre" })
H.eq(hooked and #hooks or 0, 1, "the exit hook sits once in the live_server group, a second source included")
-- stop_all notifies at exit, after the ruling and with no newline, where
-- its line fused with the runner's next one (a CI ::endgroup:: marker).
if hooked then
    vim.api.nvim_clear_autocmds({ group = "live_server" })
end
H.finish()
