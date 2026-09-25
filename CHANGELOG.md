# Changelog

All notable changes to this project; versions follow SemVer. From `[Unreleased]` on, the format follows Keep a Changelog. The sections below it are the release notes as published on GitHub, with their headings moved one level down and the em dash written as a colon.

## [Unreleased]

### Changed

- The picker titles read `LiveServer: Choose path` and `LiveServer: Pick file`.

### Removed

- **BREAKING:** Neovim 0.8 and 0.9 support (v1.5.0's README declared 0.8+). Below 0.10 the plugin shows one notification, "live-server.nvim requires Neovim 0.10 or newer; on Neovim 0.9 pin the plugin to v1.5.0", every command refuses with the same message, the statusline component shows nothing, and requiring `live_server.server` or `live_server.util` raises the message. To stay on Neovim 0.8 or 0.9, pin v1.5.0, the last release that runs there (`tag = "v1.5.0"` in a lazy.nvim spec); v1.5.0 receives no further fixes.

## [1.5.0] - 2026-07-07

### Features
- **Configurable bind address**: new `host` setup option (default `127.0.0.1`); set `"0.0.0.0"` for network access. Thanks @icyveins7 (#5).
- **Token auth in setup**: `token` and `protected_paths` are now exposed as setup options, so network binding can actually be secured from the plugin config.
- **Asset route**: new token-gated `/__live/asset?p=<relpath>` endpoint serves files relative to a configurable `asset_root` (a directory or a function), with realpath containment. Powers relative-image support in markdown-preview.nvim.
- **Capability flags**: `require('live_server.server').features` lets sibling plugins feature-detect against an independently-versioned install.

### Security
- **Path-normalization auth bypass fixed**: the token gate matched the raw request path while files were served after URL-decoding and slash-collapsing, so `//content.md`, `/content%2emd`, and `/x/../content.md` could evade the token on a network bind. The path is now canonicalized once and used for both the auth check and the file mapper.
- **SSE CORS**: the reload stream no longer sends a hardcoded `Access-Control-Allow-Origin: *`; it emits CORS only when configured.

### Docs & tests
- README documents the network-exposure trade-offs and the `ssh -L` alternative.
- New test suites for host binding and the asset route; token-auth tests extended with path-normalization cases (44 tests total).

## [1.4.0] - 2026-05-24

- **Feature:** Optional token auth for protected endpoints. When `cfg.token` is set, the SSE stream (`/__live/events`), the event injection endpoint (`/__live/inject`), and any path matching `cfg.protected_paths` (list of Lua patterns) require `?t=<token>` on the request. Static assets stay reachable so the browser can bootstrap. (#4)
- **API:** New helpers `util.random_token(byte_len)` (hex token from `/dev/urandom`, with a `math.random` fallback) and `util.secure_compare(a, b)` for constant-time-ish validation.
- **Backward compatible:** `cfg.token = nil` (the default) keeps the previous behaviour. No existing caller is affected.

## [1.3.0] - 2026-04-19

- Add configurable host binding via the `host` field on `server.start({ host = ... })`. Default remains `127.0.0.1`. Set to `0.0.0.0` to expose externally (useful in containers).

## [1.2.2] - 2026-03-22

- Fix recursive file watching on Linux: v1.2.1 fallback never triggered because `UV_FS_EVENT_RECURSIVE` is silently ignored on Linux (no error)
- Now detects platform via `uv.os_uname()` and always uses per-directory watchers on Linux
- Fixed callback path construction for subdirectory watchers

## [1.2.1] - 2026-03-21

- Fix recursive file watching on Linux: subdirectory changes (e.g. `css/style.css`) now trigger reloads
- Falls back to per-directory watchers when `UV_FS_EVENT_RECURSIVE` is not supported
- Dynamically watches newly created directories

## [1.2.0] - 2026-03-13

- Add `/__live/inject` HTTP endpoint for external SSE event injection
- Support port 0 (OS-assigned) with actual port resolution via `getsockname()`

## [1.1.0] - 2026-02-15

### New

- **`S.send_event(inst, event_type, data)`**: public API for sending custom SSE events to connected browsers. Exposes the internal broadcast mechanism so consumers (e.g. markdown-preview.nvim) can send arbitrary event types beyond the built-in \`reload\`.

## [1.0.0] - 2026-02-12

### live-server.nvim v1.0.0

Pure-Lua local web server for Neovim with live-reload. Zero external dependencies.

#### Features

- **SSE live-reload** with configurable debouncing
- **CSS hot-inject**: swap stylesheets without full page reload
- **Auto-start** on filetype (e.g. open an HTML file → server starts)
- **Statusline component**: `[LS :8000]` for lualine/statusline
- **`.liveignore`**: skip file watcher noise (`node_modules`, `*.log`, etc.)
- **CORS headers**: configurable `Access-Control-Allow-Origin`
- **Telescope integration**: path and port pickers
- **Directory listing**: styled index when no `index.html` exists
- **Styled error pages**: dark-mode-aware 404/400 pages
- **Same-port retargeting**: reuse browser tab when switching roots
- **Custom index names**: try `index.html`, `index.htm`, or your own list
- **Vimdoc**: full `:help live-server.nvim` documentation
- **Graceful exit**: servers stop automatically on `VimLeavePre`

#### Install

```lua
{ "selimacerbas/live-server.nvim", opts = {} }
```

See [README](https://github.com/selimacerbas/live-server.nvim#readme) for full setup and configuration.

[Unreleased]: https://github.com/selimacerbas/live-server.nvim/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.5.0
[1.4.0]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.4.0
[1.3.0]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.3.0
[1.2.2]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.2.2
[1.2.1]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.2.1
[1.2.0]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.2.0
[1.1.0]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.1.0
[1.0.0]: https://github.com/selimacerbas/live-server.nvim/releases/tag/v1.0.0
