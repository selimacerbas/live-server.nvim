# Security

## Supported versions

The latest release, and `main` between releases. Older tags receive no fixes.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: <https://github.com/selimacerbas/live-server.nvim/security/advisories/new>. Do not open a public issue for a security problem.

You get a reply within seven days. A confirmed report is fixed in a release and credited in the advisory unless you ask otherwise.

## What the server exposes

live-server serves the directory you point it at, on `127.0.0.1` by default. With `host = "0.0.0.0"` every file under that root is reachable by anyone who can reach the port, as the README's Design notes say; `token` gates the event stream, the inject endpoint, the asset route and the paths `protected_paths` names, and every other file stays readable. `cors = true` is a documented choice that lets any web page open in the same browser read the server cross-origin. A report that shows a way around the path containment, the token gate or the loopback bind is in scope.
