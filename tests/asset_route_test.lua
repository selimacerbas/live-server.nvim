-- tests/asset_route_test.lua
-- Verify the /__live/asset endpoint:
--   - serves files relative to cfg.asset_root (string or function form)
--   - requires ?t=<token> when token auth is configured
--   - rejects traversal, absolute paths, and schemes
--
-- Run: nvim --headless -u NONE -c "set rtp^=." -l tests/asset_route_test.lua

local uv     = vim.loop
local server = require("live_server.server")
local lutil  = require("live_server.util")

local passed = 0
local failed = 0

local function eq(a, b, msg)
    if a == b then
        passed = passed + 1
        print("  PASS: " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL: %s (got %s, want %s)", msg, tostring(a), tostring(b)))
    end
end

local function http_get(url)
    local cmd = { "curl", "-s", "--connect-timeout", "2",
                  "-o", "-", "-w", "\nHTTPSTATUS:%{http_code}", url }
    local out = vim.fn.system(cmd)
    local body, status = out:match("^(.*)\nHTTPSTATUS:(%d+)%s*$")
    return { status = tonumber(status) or 0, body = body or "" }
end

local function write_file(path, data)
    local fd = uv.fs_open(path, "w", 420)
    uv.fs_write(fd, data, 0)
    uv.fs_close(fd)
end

-- Layout:
--   tmpdir/www/index.html          (served root)
--   tmpdir/src/pic.png             (asset root)
--   tmpdir/src/sub/nested.txt
--   tmpdir/secret.txt              (outside asset root)
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir .. "/www", "p")
vim.fn.mkdir(tmpdir .. "/src/sub", "p")
write_file(tmpdir .. "/www/index.html", "<html><body>ok</body></html>")
write_file(tmpdir .. "/src/pic.png", "PNGDATA")
write_file(tmpdir .. "/src/sub/nested.txt", "nested")
write_file(tmpdir .. "/secret.txt", "SECRET")

local TOKEN = lutil.random_token(16)

print("Section 1: token-gated asset route (asset_root as string)")

local inst = server.start({
    port = 0,
    root = tmpdir .. "/www",
    token = TOKEN,
    asset_root = tmpdir .. "/src",
    live = { inject_script = false },
    features = { dirlist = { enabled = false } },
})
local base = ("http://127.0.0.1:%d"):format(inst.port)

eq(http_get(base .. "/__live/asset?p=pic.png").status, 401, "asset without token is 401")
local r = http_get(base .. "/__live/asset?p=pic.png&t=" .. TOKEN)
eq(r.status, 200, "asset with token is 200")
eq(r.body, "PNGDATA", "asset body matches")
eq(http_get(base .. "/__live/asset?p=sub%2Fnested.txt&t=" .. TOKEN).status, 200, "nested asset (encoded slash) is 200")
eq(http_get(base .. "/__live/asset?p=../secret.txt&t=" .. TOKEN).status, 404, "traversal ../ is 404")
eq(http_get(base .. "/__live/asset?p=%2e%2e%2fsecret.txt&t=" .. TOKEN).status, 404, "encoded traversal is 404")
eq(http_get(base .. "/__live/asset?p=/etc/hosts&t=" .. TOKEN).status, 404, "absolute path is 404")
eq(http_get(base .. "/__live/asset?p=c:%5Cwin&t=" .. TOKEN).status, 404, "drive letter / backslash is 404")
eq(http_get(base .. "/__live/asset?p=missing.png&t=" .. TOKEN).status, 404, "missing file is 404")
eq(http_get(base .. "/__live/asset?t=" .. TOKEN).status, 404, "missing p param is 404")

server.stop(inst)

print("\nSection 2: asset_root as function, no token configured")

local current_root = tmpdir .. "/src"
inst = server.start({
    port = 0,
    root = tmpdir .. "/www",
    asset_root = function() return current_root end,
    live = { inject_script = false },
    features = { dirlist = { enabled = false } },
})
base = ("http://127.0.0.1:%d"):format(inst.port)

eq(http_get(base .. "/__live/asset?p=pic.png").status, 200, "no-token server serves asset openly (backward compat)")
current_root = tmpdir .. "/src/sub"
eq(http_get(base .. "/__live/asset?p=nested.txt").status, 200, "function root is re-evaluated per request")
eq(http_get(base .. "/__live/asset?p=pic.png").status, 404, "old root no longer served after function retarget")

server.stop(inst)

print("\nSection 3: no asset_root configured")

inst = server.start({
    port = 0,
    root = tmpdir .. "/www",
    live = { inject_script = false },
    features = { dirlist = { enabled = false } },
})
base = ("http://127.0.0.1:%d"):format(inst.port)
eq(http_get(base .. "/__live/asset?p=pic.png").status, 404, "asset route 404s when asset_root unset")
server.stop(inst)

print(string.format("\n========================================"))
print(string.format("Results: %d passed, %d failed", passed, failed))
print(string.format("========================================"))

if failed > 0 then vim.cmd("cq 1") end
