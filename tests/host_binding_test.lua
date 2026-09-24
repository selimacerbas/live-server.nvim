-- tests/host_binding_test.lua
-- Verify that cfg.host controls the bind address:
--   - "127.0.0.1" (default) is reachable on loopback and refuses the LAN IP
--   - "0.0.0.0" is reachable on both
-- The socket's own address is asserted for both; the LAN probes are skipped,
-- counted, where a host firewall intercepts them.
--
-- Run: nvim --headless -u NONE -l tests/host_binding_test.lua

local H = dofile(vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "helpers.lua"))
H.isolate()
H.rtp()

local uv = vim.uv
local server = require("live_server.server")
local eq, http_get = H.eq, H.http_get

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
    if lan_ip then
        break
    end
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
eq(dinst.handle:getsockname().ip, "127.0.0.1", "socket bound to loopback")
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
eq(inst.handle:getsockname().ip, "127.0.0.1", "socket bound to loopback")
local port = inst.port

local r = http_get(("http://127.0.0.1:%d/"):format(port))
eq(r.status, 200, "loopback reachable on 127.0.0.1 bind")

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

-- Only a probe that never got an HTTP answer is a host firewall's doing:
-- curl 28 when it drops the connect, 52 or 56 when it accepts and then
-- closes or resets (this Mac's application firewall: 52 in 14 of 15 runs,
-- 56 in one). A listener reached with any status but 200, or a refused
-- connect (curl 7: nothing on the wildcard address), is this plugin's red.
-- lan_skipped says why the LAN probe did not measure; Section 3 skips on it.
local lan_skipped
if not (lan_ip and lan_ip ~= "127.0.0.1") then
    lan_skipped = "could not determine a LAN IP"
else
    r = http_get(("http://%s:%d/"):format(lan_ip, port))
    if r.curl_exit == 28 or r.curl_exit == 52 or r.curl_exit == 56 then
        lan_skipped = ("LAN IP %s gave no HTTP answer (curl %d): a host firewall"):format(lan_ip, r.curl_exit)
    end
end
if lan_skipped then
    H.skip("LAN IP reachable on 0.0.0.0 bind (" .. lan_skipped .. "; bind address asserted above)")
else
    eq(
        ("status %d, curl %d"):format(r.status, r.curl_exit),
        "status 200, curl 0",
        ("LAN IP %s reachable on 0.0.0.0 bind"):format(lan_ip)
    )
end

server.stop(inst)

-- ─── Section 3: a loopback bind refuses the LAN IP ───────────────────────────
H.section("Section 3: host = '127.0.0.1' refuses the LAN IP")
-- Refused is curl 7. A firewall that intercepts the LAN probe would pass any
-- weaker check, so where the wildcard bind's probe did not measure
-- (Section 2) this one is skipped rather than passed.
if lan_skipped then
    H.skip("LAN IP refuses a 127.0.0.1 bind (" .. lan_skipped .. ")")
else
    inst = server.start({
        port = 0,
        host = "127.0.0.1",
        root = tmpdir,
        default_index = idx,
        live = { inject_script = false },
        features = { dirlist = { enabled = false } },
    })
    r = http_get(("http://%s:%d/"):format(lan_ip, inst.port))
    eq(r.curl_exit, 7, ("LAN IP %s refuses a 127.0.0.1 bind (curl 7)"):format(lan_ip))
    server.stop(inst)
end

-- ─── Summary ─────────────────────────────────────────────────────────────────
H.finish()
