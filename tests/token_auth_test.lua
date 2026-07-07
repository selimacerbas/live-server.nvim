-- tests/token_auth_test.lua
-- Verify that cfg.token gates /__live/events, /__live/inject, and any path
-- listed in cfg.protected_paths, while leaving static assets (index.html)
-- reachable without auth.
--
-- Run: nvim --headless -c "set rtp+=." -c "luafile tests/token_auth_test.lua" -c "qa!"

local uv = vim.loop
local server = require("live_server.server")
local util = require("live_server.util")

local passed = 0
local failed = 0

local function ok(cond, msg)
	if cond then
		passed = passed + 1
		print("  PASS: " .. msg)
	else
		failed = failed + 1
		print("  FAIL: " .. msg)
	end
end

local function eq(a, b, msg)
	if a == b then
		passed = passed + 1
		print("  PASS: " .. msg)
	else
		failed = failed + 1
		print(string.format("  FAIL: %s (got %s, want %s)", msg, tostring(a), tostring(b)))
	end
end

-- Synchronous HTTP GET via curl. Returns { status, body }.
local function http_get(url, headers)
	local cmd = { "curl", "-s", "-o", "-", "-w", "\nHTTPSTATUS:%{http_code}", url }
	for _, h in ipairs(headers or {}) do
		table.insert(cmd, 2, "-H")
		table.insert(cmd, 3, h)
	end
	local out = vim.fn.system(cmd)
	local body, status = out:match("^(.*)\nHTTPSTATUS:(%d+)%s*$")
	return { status = tonumber(status), body = body or "" }
end

-- Workspace with two files
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local f1 = vim.fs.joinpath(tmpdir, "index.html")
local f2 = vim.fs.joinpath(tmpdir, "content.md")
do
	local fd = uv.fs_open(f1, "w", 420)
	uv.fs_write(fd, "<html><body>hi</body></html>", 0)
	uv.fs_close(fd)
	fd = uv.fs_open(f2, "w", 420)
	uv.fs_write(fd, "# secret content", 0)
	uv.fs_close(fd)
end

-- ─── Section 1: random_token / secure_compare ───────────────────────────────
print("Section 1: helpers")
local t1 = util.random_token(16)
local t2 = util.random_token(16)
eq(#t1, 32, "random_token(16) returns 32 hex chars")
ok(t1 ~= t2, "two calls return different tokens")
ok(t1:match("^[0-9a-f]+$") ~= nil, "token is pure hex")
ok(util.secure_compare("abc", "abc"), "secure_compare equal strings")
ok(not util.secure_compare("abc", "abd"), "secure_compare unequal strings")
ok(not util.secure_compare("abc", "abcd"), "secure_compare different lengths")
ok(not util.secure_compare(nil, "abc"), "secure_compare nil arg")

-- ─── Section 2: server with token ───────────────────────────────────────────
print("\nSection 2: server enforces token")
local TOKEN = util.random_token(16)
local inst = server.start({
	port = 0, -- OS-assigned
	root = tmpdir,
	default_index = f1,
	token = TOKEN,
	protected_paths = { "^/content%.md$" },
	live = { inject_script = false },
	features = { dirlist = { enabled = false } },
})
local port = inst.port

-- Static asset (index.html) is reachable without token
local r = http_get(("http://127.0.0.1:%d/"):format(port))
eq(r.status, 200, "/ (index.html) reachable without token")

-- /content.md requires token
r = http_get(("http://127.0.0.1:%d/content.md"):format(port))
eq(r.status, 401, "/content.md without token is 401")

r = http_get(("http://127.0.0.1:%d/content.md?t=wrong"):format(port))
eq(r.status, 401, "/content.md with wrong token is 401")

r = http_get(("http://127.0.0.1:%d/content.md?t=%s"):format(port, TOKEN))
eq(r.status, 200, "/content.md with correct token is 200")
ok(r.body:find("secret content") ~= nil, "/content.md body contains expected text")

-- /__live/inject requires token
r = http_get(("http://127.0.0.1:%d/__live/inject?event=reload"):format(port))
eq(r.status, 401, "/__live/inject without token is 401")

r = http_get(("http://127.0.0.1:%d/__live/inject?event=reload&t=%s"):format(port, TOKEN))
eq(r.status, 200, "/__live/inject with correct token is 200")

-- /__live/events also requires token (we don't actually read SSE; just confirm
-- the status code from the initial response line)
r = http_get(("http://127.0.0.1:%d/__live/events"):format(port))
eq(r.status, 401, "/__live/events without token is 401")

-- Path-normalization bypass: encoded or slash-padded variants of a protected
-- path must NOT evade the token (they resolve to the same file).
r = http_get(("http://127.0.0.1:%d//content.md"):format(port))
eq(r.status, 401, "//content.md (extra slash) without token is 401")

r = http_get(("http://127.0.0.1:%d/content%%2emd"):format(port))
eq(r.status, 401, "/content%2emd (encoded dot) without token is 401")

r = http_get(("http://127.0.0.1:%d/./content.md"):format(port))
eq(r.status, 401, "/./content.md (dot segment) without token is 401")

r = http_get(("http://127.0.0.1:%d/sub/../content.md?t=wrong"):format(port))
eq(r.status, 401, "/sub/../content.md (traversal) with wrong token is 401")

-- And the normalized/encoded form still serves with the correct token.
r = http_get(("http://127.0.0.1:%d//content.md?t=%s"):format(port, TOKEN))
eq(r.status, 200, "//content.md with correct token still serves")

server.stop(inst)

-- ─── Section 3: backward compat (no token in cfg) ───────────────────────────
print("\nSection 3: no token = no auth (backward compat)")
inst = server.start({
	port = 0,
	root = tmpdir,
	default_index = f1,
	live = { inject_script = false },
	features = { dirlist = { enabled = false } },
})
port = inst.port

r = http_get(("http://127.0.0.1:%d/content.md"):format(port))
eq(r.status, 200, "/content.md reachable when token not configured")

r = http_get(("http://127.0.0.1:%d/__live/inject?event=reload"):format(port))
eq(r.status, 200, "/__live/inject reachable when token not configured")

server.stop(inst)

-- ─── Summary ────────────────────────────────────────────────────────────────
print(string.format("\n========================================"))
print(string.format("Results: %d passed, %d failed", passed, failed))
print(string.format("========================================"))

if failed > 0 then vim.cmd("cq 1") end
