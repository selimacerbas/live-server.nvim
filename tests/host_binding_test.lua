-- tests/host_binding_test.lua
-- Verify that cfg.host controls the bind address:
--   - "127.0.0.1" (default) is reachable on loopback but not on the LAN IP
--   - "0.0.0.0" is reachable on both
--
-- Run: nvim --headless -u NONE -c "set rtp^=." -c "luafile tests/host_binding_test.lua" -c "qa!"

local uv     = vim.loop
local server = require("live_server.server")

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

-- curl GET; connect-timeout of 2s so we fail fast on refused connections.
local function http_get(url)
    local cmd = { "curl", "-s", "--connect-timeout", "2",
                  "-o", "-", "-w", "\nHTTPSTATUS:%{http_code}", url }
    local out = vim.fn.system(cmd)
    local body, status = out:match("^(.*)\nHTTPSTATUS:(%d+)%s*$")
    return { status = tonumber(status) or 0, body = body or "" }
end

-- Detect primary LAN IP (first non-loopback address from `hostname -I`).
local lan_ip = vim.fn.system("hostname -I"):match("(%S+)")

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local idx = vim.fs.joinpath(tmpdir, "index.html")
do
    local fd = uv.fs_open(idx, "w", 420)
    uv.fs_write(fd, "<html><body>ok</body></html>", 0)
    uv.fs_close(fd)
end

-- ─── Section 1: default host stores "127.0.0.1" on inst ──────────────────────
print("Section 1: inst.host reflects configured bind address")

local inst = server.start({
    port = 0,
    host = "127.0.0.1",
    root = tmpdir,
    default_index = idx,
    live = { inject_script = false },
    features = { dirlist = { enabled = false } },
})
eq(inst.host, "127.0.0.1", "inst.host is '127.0.0.1' when configured so")
local port = inst.port

local r = http_get(("http://127.0.0.1:%d/"):format(port))
eq(r.status, 200, "loopback reachable on 127.0.0.1 bind")

if lan_ip and lan_ip ~= "127.0.0.1" then
    r = http_get(("http://%s:%d/"):format(lan_ip, port))
    ok(r.status ~= 200, "LAN IP NOT reachable when bound to 127.0.0.1")
else
    print("  SKIP: could not determine LAN IP, skipping LAN-unreachable check")
end

server.stop(inst)

-- ─── Section 2: host = "0.0.0.0" is reachable on both interfaces ─────────────
print("\nSection 2: host = '0.0.0.0' reachable on loopback and LAN IP")

inst = server.start({
    port = 0,
    host = "0.0.0.0",
    root = tmpdir,
    default_index = idx,
    live = { inject_script = false },
    features = { dirlist = { enabled = false } },
})
eq(inst.host, "0.0.0.0", "inst.host is '0.0.0.0' when configured so")
port = inst.port

r = http_get(("http://127.0.0.1:%d/"):format(port))
eq(r.status, 200, "loopback reachable on 0.0.0.0 bind")

if lan_ip and lan_ip ~= "127.0.0.1" then
    r = http_get(("http://%s:%d/"):format(lan_ip, port))
    eq(r.status, 200, ("LAN IP %s reachable on 0.0.0.0 bind"):format(lan_ip))
else
    print("  SKIP: could not determine LAN IP, skipping LAN-reachable check")
end

server.stop(inst)

-- ─── Summary ─────────────────────────────────────────────────────────────────
print(string.format("\n========================================"))
print(string.format("Results: %d passed, %d failed", passed, failed))
print(string.format("========================================"))

if failed > 0 then vim.cmd("cq 1") end
