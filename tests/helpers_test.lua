-- tests/helpers_test.lua
-- Verify the harness every other suite leans on: the root it resolves, the
-- XDG move, the bounded curl and the exit code a gate reads.
--
-- Run: nvim --headless -u NONE -l tests/helpers_test.lua

local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
local xdg = H.isolate()
H.rtp()

local uv = vim.uv or vim.loop
local ok, eq = H.ok, H.eq

H.section("Section 1: root and isolation")
ok(vim.fn.isdirectory(H.root .. "/tests") == 1, "H.root is the directory that holds tests/")
ok(vim.fn.stdpath("cache"):find(xdg, 1, true) == 1, "stdpath cache sits under the XDG root H.isolate() returned")

H.section("Section 2: bounded curl")
-- A port the kernel just handed out and took back: nothing listens on it, so
-- the refusal is certain, where a fixed port such as 9 is only probably closed.
local probe = uv.new_tcp()
probe:bind("127.0.0.1", 0)
local released_port = probe:getsockname().port
probe:close()
eq(H.http_get(("http://127.0.0.1:%d/"):format(released_port)).status, 0, "a refused connection yields status 0")

-- A listener that completes the handshake and never answers: the bounded
-- curl must give up on its own, and the helper must report that as 0.
local hold = uv.new_tcp()
hold:bind("127.0.0.1", 0)
hold:listen(1, function() end)
local t0 = uv.hrtime()
local stalled = H.http_get(("http://127.0.0.1:%d/"):format(hold:getsockname().port))
eq(stalled.status, 0, "a stalled server yields status 0")
eq(stalled.curl_exit, 28, "curl reports its timeout (exit 28)")
ok((uv.hrtime() - t0) / 1e9 < 8, "the stalled request returned within the bound")
hold:close()

H.section("Section 3: the exit code is the ruling")
-- Each case runs in a child of the same binary, since its cq would end this
-- suite too; progpath keeps the child on the version under test.
local helpers_path = vim.fs.joinpath(H.root, "tests", "helpers.lua")
local function child_exit(body)
    local path = vim.fs.joinpath(H.tmpdir(), "child_test.lua")
    H.write_file(path, ("local H = dofile(%q)\n%s\nH.finish()\n"):format(helpers_path, body))
    vim.fn.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", path })
    return vim.v.shell_error
end
eq(child_exit('H.ok(false, "deliberate")'), 1, "a failed assertion exits 1")
eq(child_exit(""), 1, "a suite with no assertion exits 1")
eq(child_exit('H.ok(true, "x")'), 0, "one passing assertion exits 0")

H.finish()
