-- tests/host_binding_test.lua
-- Verify that cfg.host controls the bind address:
--   - "127.0.0.1" (default) is reachable on loopback but not on the LAN IP
--   - "0.0.0.0" is reachable on both
--
-- Run: nvim --headless -u NONE -l tests/host_binding_test.lua

local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
H.isolate()
H.rtp()

local uv = vim.uv or vim.loop
local server = require("live_server.server")
local ok, eq, http_get = H.ok, H.eq, H.http_get

-- Detect primary LAN IP via libuv (portable; `hostname -I` is Linux-only
-- and on macOS/BSD yields garbage that poisons the URL checks below).
local lan_ip
for _, addrs in pairs(uv.interface_addresses() or {}) do
    for _, a in ipairs(addrs) do
        if a.family == "inet" and not a.internal then
            lan_ip = a.ip
            break
        end
    end
    if lan_ip then break end
end

local tmpdir = H.tmpdir()
local idx = vim.fs.joinpath(tmpdir, "index.html")
H.write_file(idx, "<html><body>ok</body></html>")

-- ─── Section 0: cfg.host omitted defaults to loopback ────────────────────────
H.section("Section 0: default host is 127.0.0.1 when cfg.host is omitted")

local dinst = server.start({
    port = 0,
    root = tmpdir,
    default_index = idx,
    live = { inject_script = false },
    features = { dirlist = { enabled = false } },
})
eq(dinst.host, "127.0.0.1", "inst.host defaults to '127.0.0.1'")
local dr = http_get(("http://127.0.0.1:%d/"):format(dinst.port))
eq(dr.status, 200, "loopback reachable on default bind")
server.stop(dinst)

-- ─── Section 1: default host stores "127.0.0.1" on inst ──────────────────────
H.section("Section 1: inst.host reflects configured bind address")

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
H.section("Section 2: host = '0.0.0.0' reachable on loopback and LAN IP")

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

-- Assert the actual bind address on the socket; unlike a LAN curl this is
-- deterministic (host firewalls often block incoming non-loopback traffic).
local sn = inst.handle:getsockname()
eq(sn and sn.ip, "0.0.0.0", "socket bound to wildcard address")

r = http_get(("http://127.0.0.1:%d/"):format(port))
eq(r.status, 200, "loopback reachable on 0.0.0.0 bind")

if lan_ip and lan_ip ~= "127.0.0.1" then
    r = http_get(("http://%s:%d/"):format(lan_ip, port))
    if r.status == 200 then
        ok(true, ("LAN IP %s reachable on 0.0.0.0 bind"):format(lan_ip))
    else
        print(("  NOTE: LAN IP %s not reachable (status %d) — likely a host firewall; bind address asserted above")
            :format(lan_ip, r.status))
    end
else
    print("  SKIP: could not determine LAN IP, skipping LAN-reachable check")
end

server.stop(inst)

-- ─── Summary ─────────────────────────────────────────────────────────────────
H.finish()
