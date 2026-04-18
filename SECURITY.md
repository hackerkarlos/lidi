# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please help us
address it responsibly by following these steps:

1. **Do not publicly disclose the vulnerability.**
2. Contact us directly at
   [opensource@ssi.gouv.fr](mailto:opensource@ssi.gouv.fr) with the following
   details:
   - A clear description of the issue.
   - Steps to reproduce the vulnerability.
   - Any potential impact or exploit scenarios.

Thank you for helping us keep this project secure!

## Observability HTTP Exposure Model

`diode-send` and `diode-receive` can optionally expose a read-only HTTP server
via `--http-addr` that serves an embedded dashboard, JSON status APIs, recent
log lines, and a `/metrics` endpoint in Prometheus text format. This server is
intended **only** for local operational visibility and has the following
constraints baked in:

- **No authentication and no transport security.** Any client able to reach
  the bound address can read all exposed data. Always bind to `127.0.0.1` (or
  an equivalently restricted interface) and front it with a reverse proxy if
  remote access is required.
- **Information disclosed.** Configuration (version, MTU, RaptorQ block size,
  repair percentage, listener/forward addresses), live counters (bytes,
  packets, transfers, active clients), recent log lines from the in-memory
  ring, and Prometheus counters/gauges. Treat anything the binary logs as
  exposed.
- **Single-threaded handler.** Connections are processed sequentially, with
  per-connection read/write timeouts (2 s / 5 s) and a request-size cap
  (8 KiB). This is sufficient for a trusted loopback consumer (browser at
  1 Hz, Prometheus scraper at typical intervals) but means an unauthenticated
  remote attacker could trivially stall the dashboard with slow reads. Do not
  expose the endpoint to untrusted networks.
- **Read-only.** All routes are `GET`; no state-changing operations are
  served, so CSRF is not a concern.
- **Disabled by default.** Omitting `--http-addr` skips the server entirely;
  the data path is unaffected either way.

In Docker deployments, the supplied `docker-compose.observability.yml`
publishes the host-side ports to `127.0.0.1` only; the container itself binds
`0.0.0.0` because Docker forwards only explicitly published ports.
