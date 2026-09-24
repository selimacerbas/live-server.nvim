-- tests/helpers.lua
-- Shared by every headless suite: XDG isolation for everything a suite
-- creates, a bounded curl and one pass/fail ledger whose exit code is the
-- ruling. Loaded by path (dofile), never by require, so nothing under tests/
-- joins the plugin's public module tree.
local uv = vim.uv or vim.loop
local H = {}

local passed, failed = 0, 0
local tests_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

-- The repository root is the parent of tests/, whatever the current
-- directory; tests build plugin paths from it.
H.root = vim.fn.fnamemodify(tests_dir, ":p:h:h")

-- A fresh XDG tree per run: stdpath() reads the variables at call time
-- (measured on 0.12.5), so cache, data and state move for everything created
-- after this call. The startup log is opened before any script runs and stays
-- in the state dir Neovim started with; a runner that must isolate it sets
-- XDG_STATE_HOME in the environment. The check turns a Neovim that cached the
-- paths at startup into a loud failure instead of writes into the real tree.
function H.isolate()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.env.XDG_CACHE_HOME = root .. "/cache"
    vim.env.XDG_DATA_HOME = root .. "/data"
    vim.env.XDG_STATE_HOME = root .. "/state"
    if vim.fn.stdpath("cache"):find(root, 1, true) ~= 1 then
        error("H.isolate: stdpath('cache') did not follow XDG_CACHE_HOME: " .. vim.fn.stdpath("cache"))
    end
    return root
end

function H.rtp()
    vim.opt.runtimepath:prepend(H.root)
    return H.root
end

function H.tmpdir()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    return dir
end

function H.write_file(path, data)
    local fd = assert(uv.fs_open(path, "w", 420))
    assert(uv.fs_write(fd, data, 0))
    assert(uv.fs_close(fd))
end

-- Synchronous GET through curl. Every call is bounded: a firewall that
-- swallows SYNs or a peer that never answers fails an assertion instead of
-- hanging the suite. status is 0 whenever curl itself failed (refused, timed
-- out, cut off mid-body), even when a status line had already arrived, so a
-- truncated 200 never passes as a 200; curl_exit carries curl's own code.
function H.http_get(url, headers)
    local cmd = { "curl", "-s", "--max-time", "5", "--connect-timeout", "2", "-o", "-", "-w", "\nHTTPSTATUS:%{http_code}" }
    for _, h in ipairs(headers or {}) do
        table.insert(cmd, "-H")
        table.insert(cmd, h)
    end
    table.insert(cmd, url)
    local out = vim.fn.system(cmd)
    local curl_exit = vim.v.shell_error
    local body, status = out:match("^(.*)\nHTTPSTATUS:(%d+)%s*$")
    if curl_exit ~= 0 then
        return { status = 0, body = body or "", curl_exit = curl_exit }
    end
    return { status = tonumber(status) or 0, body = body or "", curl_exit = 0 }
end

function H.section(title)
    print(((passed + failed) > 0 and "\n" or "") .. title)
end

function H.ok(cond, msg)
    if cond then
        passed = passed + 1
        print("  PASS: " .. msg)
    else
        failed = failed + 1
        print("  FAIL: " .. msg)
    end
end

function H.eq(a, b, msg)
    if a == b then
        passed = passed + 1
        print("  PASS: " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL: %s (got %s, want %s)", msg, tostring(a), tostring(b)))
    end
end

-- The summary line is what a gate reads; cq makes the exit code agree with it.
-- A suite that asserted nothing proved nothing, so it fails as well. The last
-- banner line carries its own newline because cq skips the one a normal exit
-- writes (measured on 0.12.5).
function H.finish()
    if passed + failed == 0 then
        print("No assertion ran: a suite that checks nothing is not a pass.")
    end
    print("\n========================================")
    print(string.format("Results: %d passed, %d failed", passed, failed))
    print("========================================\n")
    if failed > 0 or passed == 0 then
        vim.cmd("cq 1")
    end
end

return H
