-- tests/open_browser_test.lua
-- util.open_browser against a vim.ui.open that finds no opener: it answers
-- nil and a message without raising, which the fallback must read. The
-- platform opener and the notifier are stubbed, so no browser starts.
--
-- Run: nvim --headless -u NONE -l "$PWD/tests/open_browser_test.lua"

local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
H.isolate()
H.rtp()

local util = require("live_server.util")
local eq, ok = H.eq, H.ok

local URL = "http://127.0.0.1:8123/"
local opener = vim.fn.has("win32") == 1 and "cmd.exe" or (vim.fn.has("mac") == 1 and "open" or "xdg-open")
local real_open, real_jobstart, real_notify = vim.ui.open, vim.fn.jobstart, vim.notify

-- One call of open_browser with vim.ui.open answering ui_result (a table of
-- its return values) and jobstart answering job (a string raises it, as the
-- real jobstart raises E475 for an opener that is not executable, and when
-- exit is set on_exit is called with it); returns the jobstart calls and the
-- notices.
local function attempt(ui_result, job, exit)
    local calls, notices = {}, {}
    vim.ui.open = function()
        return unpack(ui_result)
    end
    vim.fn.jobstart = function(argv, opts)
        calls[#calls + 1] = argv
        if type(job) == "string" then
            error(job)
        end
        if exit ~= nil and job > 0 then
            opts.on_exit(job, exit)
        end
        return job
    end
    vim.notify = function(msg, level)
        notices[#notices + 1] = { msg = msg, level = level }
    end
    util.open_browser(URL)
    vim.wait(200, function()
        return #calls > 0 and (exit == nil or #notices > 0 or exit == 0)
    end)
    vim.wait(20, function()
        return false
    end)
    vim.ui.open, vim.fn.jobstart, vim.notify = real_open, real_jobstart, real_notify
    return calls, notices
end

H.section("Section 1: no opener found, the platform's opener starts")
local calls, notices = attempt({ nil, "vim.ui.open: no handler found" }, 7, 0)
eq(#calls, 1, "the fallback starts one job")
ok(
    calls[1] ~= nil and calls[1][1] == opener and calls[1][#calls[1]] == URL,
    ("the job is %s with the URL: %s"):format(opener, vim.inspect(calls[1]))
)
eq(#notices, 0, "a fallback that starts and exits 0 shows no notice")

H.section("Section 2: the fallback fails, the URL is shown")
calls, notices = attempt({ nil, "vim.ui.open: no handler found" }, -1)
eq(#calls, 1, "the fallback was tried")
ok(
    #notices == 1 and notices[1].msg:find(URL, 1, true) ~= nil and notices[1].level == vim.log.levels.WARN,
    "an opener that cannot start shows the URL to open by hand: " .. vim.inspect(notices)
)
calls, notices = attempt({ nil, "vim.ui.open: no handler found" }, 7, 3)
ok(
    #notices == 1 and notices[1].msg:find(URL, 1, true) ~= nil,
    "an opener that exits nonzero shows the URL to open by hand: " .. vim.inspect(notices)
)
calls, notices = attempt(
    { nil, "vim.ui.open: no handler found" },
    ("Vim:E475: Invalid value for argument cmd: '%s' is not executable"):format(opener)
)
ok(
    #notices == 1 and notices[1].msg:find(URL, 1, true) ~= nil,
    "an opener jobstart refuses as not executable shows the URL to open by hand: " .. vim.inspect(notices)
)

H.section("Section 3: vim.ui.open found an opener")
calls, notices = attempt({ {} }, 7, 0)
eq(#calls, 0, "no fallback runs when vim.ui.open returns a handle")
eq(#notices, 0, "no notice when vim.ui.open returns a handle")

H.finish()
