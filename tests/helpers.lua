-- tests/helpers.lua
-- Shared by every headless suite: isolation from the developer's own Neovim
-- state, a bounded curl and one pass/fail ledger whose exit code is the
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
-- (measured on 0.12.5), so setting them here moves cache, data and state.
function H.isolate()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.env.XDG_CACHE_HOME = root .. "/cache"
    vim.env.XDG_DATA_HOME = root .. "/data"
    vim.env.XDG_STATE_HOME = root .. "/state"
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
function H.finish()
    print("\n========================================")
    print(string.format("Results: %d passed, %d failed", passed, failed))
    print("========================================")
    if failed > 0 then
        vim.cmd("cq 1")
    end
end

return H
