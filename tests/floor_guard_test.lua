-- tests/floor_guard_test.lua
-- Below Neovim 0.10 every documented command is a refuser that answers each
-- use with the floor module's text, the module answers a config's setup()
-- without loading the plugin (one ERROR notification at load between them)
-- and the modules the plugin-author API loads refuse at every require; on a
-- supported version the commands and the exit hook are defined.
--
-- Run: nvim --headless -u NONE -l tests/floor_guard_test.lua
local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
H.isolate()
H.rtp()
local plugin_file = H.root .. "/plugin/live_server.lua"
-- The plugin's entry module, the prefix its commands share and the features
-- its floor module tests beside the version.
local MODULE = "live_server"
local COMMAND_PREFIX = "LiveServer"
local FEATURES = { "uv" }

-- The documented commands: the README's command table, sorted.
local documented = {}
for line in io.lines(H.root .. "/README.md") do
    local name = line:match("^| `:(%w+)`")
    if name then
        table.insert(documented, name)
    end
end
table.sort(documented)
documented = table.concat(documented, " ")

-- The plugin's commands Neovim has, by the shared prefix, sorted: a set
-- equal to the README's is every documented command and no other.
local function defined()
    local names = {}
    for name in pairs(vim.api.nvim_get_commands({})) do
        if vim.startswith(name, COMMAND_PREFIX) then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return table.concat(names, " ")
end

-- A loaded module of this plugin or of live-server besides the entry module
-- and the floor module is code that needs 0.10.
local function loaded_below()
    local found = {}
    for name in pairs(package.loaded) do
        local plugin = name == MODULE or vim.startswith(name, MODULE .. ".")
        local ls = name == "live_server" or vim.startswith(name, "live_server.")
        if (plugin or ls) and name ~= MODULE and name ~= MODULE .. ".floor" then
            table.insert(found, name)
        end
    end
    table.sort(found)
    return table.concat(found, ", ")
end

-- The floor module's verdict, its chunk run against a vim that lacks field
-- (a dotted name; nil hides nothing), since a field removed from the running
-- vim can come back through its lazy loader (vim.uri_encode does, measured).
local function floor_ok_without(field)
    local chunk = assert(loadfile(H.root .. "/lua/" .. MODULE .. "/floor.lua"))
    local function proxy(real, prefix)
        return setmetatable({}, {
            __index = function(_, key)
                local name = prefix .. key
                if name == field then
                    return nil
                end
                local value = real[key]
                if type(value) == "table" and field and vim.startswith(field, name .. ".") then
                    return proxy(value, name .. ".")
                end
                return value
            end,
        })
    end
    setfenv(chunk, setmetatable({ vim = proxy(vim, "") }, { __index = _G }))
    return chunk().ok
end

-- The guard's return comes before every require but the floor module's, in
-- the source, so a require moved above it reds even when the module it
-- loads happens to need nothing newer.
local function guard_precedes_requires()
    local src = table.concat(vim.fn.readfile(H.root .. "/lua/" .. MODULE .. "/init.lua"), "\n")
    src = src:gsub("%-%-[^\n]*", "")
    local guard = src:find("if not floor.ok then", 1, true)
    local ret = guard and src:find("return setmetatable", guard, true)
    local first
    for at, name in src:gmatch("()require%s*%(?%s*[\"']([^\"']+)[\"']") do
        if name ~= MODULE .. ".floor" then
            first = at
            break
        end
    end
    return guard ~= nil and ret ~= nil and (first == nil or ret < first),
        ("guard at %s, its return at %s, the first other require at %s"):format(guard, ret, first)
end

-- Every refusal is recorded, notify_once's own dedupe aside, so the plugin
-- file's and the module's are checked apart; a refuser's goes through
-- vim.notify, since each use answers.
local notices, refusals = {}, {}
local real_once, real_notify = vim.notify_once, vim.notify
vim.notify_once = function(msg, level)
    notices[#notices + 1] = { msg = msg, level = level }
end
vim.notify = function(msg, level)
    refusals[#refusals + 1] = { msg = msg, level = level }
end
local real_has = vim.fn.has
vim.fn.has = function(feature)
    if feature == "nvim-0.10" then
        return 0
    end
    return real_has(feature)
end
local function turn_loop()
    vim.wait(50, function()
        return false
    end)
end

H.section("Section 1: below the floor")
H.ok(documented ~= "", "the README's command table lists the commands: " .. documented)
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
local message = require(MODULE .. ".floor").message
H.ok(message:find("0.10", 1, true) ~= nil, "the floor text names the floor")
H.ok(message:find("pin the plugin to v1.5.0", 1, true) ~= nil, "the floor text names the release to pin on 0.9")
-- lazy.nvim's cmd and keys specs run the command they were given, so each
-- documented one exists below the floor to say why.
H.eq(defined(), documented, "every documented command is defined below the floor, and no other")
-- lazy.nvim sources plugin files with :source, where an ERROR notification
-- on 0.9 raised a Vim(source) exception, so the refusal waits for the source
-- to return and shows once the loop turns.
H.eq(#notices, 0, "the plugin file's refusal waits until the :source returns")
vim.wait(1000, function()
    return #notices > 0
end)
H.eq(#notices, 1, "the plugin file refuses with one notification")
-- A cmd spec runs the command through vim.cmd inside lazy.nvim's handler,
-- where an ERROR notification on 0.9 raised a traceback, so a refuser's waits
-- too; every use answers, a second one included.
local names = vim.split(documented, " ")
-- Under pcall, so a command that is missing reds its own rows below and not
-- the whole suite.
for _, name in ipairs(names) do
    pcall(vim.cmd, name)
end
H.eq(#refusals, 0, "a refuser's answer waits until the command returns")
pcall(vim.cmd, names[1])
turn_loop()
H.eq(#refusals, #names + 1, "every documented command answers each use below the floor")
local refused_right = #refusals > 0
for _, refusal in ipairs(refusals) do
    refused_right = refused_right and refusal.msg == message and refusal.level == vim.log.levels.ERROR
end
H.ok(refused_right, "every refuser answers with the floor text as an ERROR")
-- lazy.nvim's config calls setup() whatever the plugin file did.
package.loaded[MODULE] = nil
local setup_ok, setup_err = pcall(function()
    require(MODULE).setup({})
end)
H.ok(setup_ok, "setup() raises nothing below the floor" .. (setup_ok and "" or (": " .. tostring(setup_err))))
H.eq(loaded_below(), "", "the module returns before any module but the floor module loads")
local structural, where = guard_precedes_requires()
H.ok(structural, "the module's floor guard returns before its first require but the floor module's: " .. where)
-- A lazy load on FileType runs the module inside 0.9's filetype nvim_cmd,
-- where an ERROR notification raised Vim(append), so this refusal waits too.
H.eq(#notices, 1, "the module's refusal waits until the require returns")
vim.wait(1000, function()
    return #notices > 1
end)
H.eq(#notices, 2, "the module refuses with one notification too")
-- lualine's documented component calls statusline(), and a nil there
-- rendered as the word nil.
local status_ok, status = pcall(function()
    return require(MODULE).statusline()
end)
H.eq(status_ok and tostring(status) or ("raised " .. tostring(status)), "", "the stub's statusline is empty")
-- Any other field a config calls answers the same, never a nil.
local other_ok, other = pcall(function()
    return require(MODULE).anything_else()
end)
H.eq(
    other_ok and tostring(other) or ("raised " .. tostring(other)),
    "",
    "an undocumented field on the stub answers the same"
)
-- notify_once shows a text once, so the floor module's text in both
-- refusals is one notification on screen, whichever of them runs first.
local all_floor_text, all_errors = #notices > 0, #notices > 0
for _, notice in ipairs(notices) do
    all_floor_text = all_floor_text and notice.msg == message
    all_errors = all_errors and notice.level == vim.log.levels.ERROR
end
H.ok(all_floor_text, "both refusals are the floor module's text, so the user sees one notification")
H.ok(all_errors, "every refusal is an ERROR")
-- The plugin-author API loads these two directly, so each refuses at load
-- with the floor text, and again on a retry. util goes first: server
-- requires util, so a server without its own guard still raises util's text
-- once, and only its second require shows the sentinel it left.
for _, modname in ipairs({ "live_server.util", "live_server.server" }) do
    for attempt = 1, 2 do
        local loaded, err = pcall(require, modname)
        H.eq(
            loaded and "loaded" or tostring(err),
            message,
            ("%s refuses to load with the floor text (require %d)"):format(modname, attempt)
        )
    end
end
-- notify_once arrived in 0.7 and a Lua plugin file is sourced from 0.5 on,
-- so without it each guard shows the text through vim.notify, once.
vim.notify_once = nil
refusals = {}
for name in pairs(package.loaded) do
    if name == MODULE or vim.startswith(name, MODULE .. ".") then
        package.loaded[name] = nil
    end
end
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
turn_loop()
H.eq(
    #refusals == 1 and refusals[1].msg or #refusals,
    message,
    "without notify_once the plugin file shows the text once"
)
require(MODULE).setup({})
turn_loop()
H.eq(#refusals == 2 and refusals[2].msg or #refusals, message, "without notify_once the module shows the text once")

H.section("Section 2: at the floor")
vim.fn.has = real_has
vim.notify_once = real_once
vim.notify = real_notify
-- The refusers go, so every command counted below is the real plugin's.
for _, name in ipairs(names) do
    pcall(vim.api.nvim_del_user_command, name)
end
-- The stub and the floor module's verdict go with every other module of
-- the plugin, and so does the sentinel require leaves for a module that
-- raised while loading.
for name in pairs(package.loaded) do
    if name == MODULE or vim.startswith(name, MODULE .. ".") then
        package.loaded[name] = nil
    end
end
H.ok(floor_ok_without(nil), "the floor admits this Neovim")
for _, field in ipairs(FEATURES) do
    H.eq(floor_ok_without(field), false, "the floor refuses a Neovim without vim." .. field .. ", whatever its version")
end
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
-- By type: a failed require leaves a truthy sentinel, and a left-over stub
-- answers state with a function.
H.ok(
    type(package.loaded["live_server.server"]) == "table" and type(require(MODULE).state) == "table",
    "the plugin's own modules load on a supported Neovim"
)
H.eq(defined(), documented, "every documented command is defined on a supported Neovim, and no other")
local hooked, hooks = pcall(vim.api.nvim_get_autocmds, { group = "LiveServerExit", event = "VimLeavePre" })
H.eq(hooked and #hooks or 0, 1, "the exit hook sits once in the LiveServerExit group, a second source included")
-- stop_all notifies at exit, after the ruling and with no newline, where
-- its line fused with the runner's next one (a CI ::endgroup:: marker).
if hooked then
    vim.api.nvim_clear_autocmds({ group = "LiveServerExit" })
end
H.finish()
