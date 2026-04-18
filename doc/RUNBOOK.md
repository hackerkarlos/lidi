# Runbook

Operational reference for deploying and running lidi.

## Deployment

### From Source

```bash
cargo build --release
# Binaries are in target/release/
```

### Docker

```bash
# Build both images
docker compose build

# Run with default parameters
docker compose up -d

# Check logs
docker compose logs -f send
docker compose logs -f receive
```

The default `docker-compose.yml` creates a bridge network (`172.16.0.0/16`)
with sender on `172.16.0.2` and receiver on `172.16.0.3`. The sender listens
for TCP connections on port `5000` (exposed to host) and forwards UDP to the
receiver on port `6000`. The receiver outputs to TCP on `172.16.0.1:7000`.

### Docker Image Details

- **Base image:** `gcr.io/distroless/cc:nonroot` (minimal, no shell)
- **Build targets:** `send` (contains `diode-send`), `receive` (contains
  `diode-receive`)
- **User:** `nonroot` (distroless default, UID 65534)

## Quick Start

Sender and receiver on the same machine:

```bash
# Terminal 1: sender
diode-send --from-tcp 127.0.0.1:5000 --to 127.0.0.1:6000

# Terminal 2: receiver
diode-receive --from 127.0.0.1:6000 --to-tcp 127.0.0.1:7000

# Terminal 3: data sink
nc -lv 127.0.0.1 7000

# Terminal 4: send data
echo "hello" | nc 127.0.0.1 5000
```

## Observability

Enable the embedded HTTP dashboard on either side:

```bash
diode-send --from-tcp 127.0.0.1:5000 --to 127.0.0.1:6000 --http-addr 127.0.0.1:8080
diode-receive --from 127.0.0.1:6000 --to-tcp 127.0.0.1:7000 --http-addr 127.0.0.1:8081
```

<!-- AUTO-GENERATED: http-endpoints -->
| Endpoint | Description |
|----------|-------------|
| `GET /` | Embedded HTML dashboard (auto-refreshes at 1 Hz) |
| `GET /api/info` | Static configuration snapshot (JSON) |
| `GET /api/status` | Live counters: bytes, packets, active clients (JSON) |
| `GET /api/logs` | Recent log lines (JSON), supports `?since=<cursor>` |
| `GET /metrics` | Prometheus text exposition format (counters + gauges) |
<!-- AUTO-GENERATED: end -->

**Warning:** The HTTP server has no authentication. Always bind to `127.0.0.1`.

### Docker

The base `docker-compose.yml` does not expose the dashboard. To enable it,
layer in the override file:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up
```

This publishes the sender's dashboard on `http://127.0.0.1:8080/` and the
receiver's on `http://127.0.0.1:8081/`. Inside the containers the server binds
to `0.0.0.0`; Docker only forwards the published ports, and the host-side
binding is restricted to `127.0.0.1`.

### Prometheus + Grafana

The `/metrics` endpoint exposes the same counters shown in the embedded
dashboard, in Prometheus text exposition format. Each instance produces
metrics labelled with its own `role` (`send` or `receive`), so a single
Prometheus can scrape both sides and graphs disambiguate by label.

Exposed series:

| Metric | Type | Purpose |
|--------|------|---------|
| `lidi_uptime_seconds` | gauge | Process uptime |
| `lidi_bytes_total` | counter | Bytes accepted (send) or forwarded (receive) |
| `lidi_packets_total` | counter | RaptorQ packets sent/received |
| `lidi_transfers_total{result="started\|finished\|aborted"}` | counter | Lifetime transfer outcomes |
| `lidi_active_transfers` | gauge | Currently active client transfers |
| `lidi_last_heartbeat_unix_seconds` | gauge | Unix time of last heartbeat (`0` = none yet) |
| `lidi_info{version,block_bytes,repair_pct,mtu}` | gauge | Always `1`; metadata in labels |

Sample configuration lives under `examples/grafana/`:

- `prometheus.yml` — scrape config stub
- `lidi-dashboard.json` — importable Grafana dashboard with throughput,
  packet rate, active transfers, heartbeat age, and transfer outcomes

Quick start on the host that runs Prometheus:

```bash
prometheus --config.file=examples/grafana/prometheus.yml
```

Import the dashboard in Grafana via *Dashboards → New → Import* and paste
`examples/grafana/lidi-dashboard.json`. Grafana will prompt for the
Prometheus datasource.

On the high side of a real diode the receiver can be scraped locally (same
host); data can't flow off-box without violating the air gap, so run a
Prometheus there and visualise it on the same side, or forward point-in-time
snapshots over the diode if your operational model allows it.

### Zabbix

The same `/metrics` endpoint is consumable from Zabbix natively — no
Prometheus, no exporter, no agent2 required. Zabbix ships HTTP-agent items
plus `Prometheus pattern` and `Prometheus to JSON` preprocessing steps that
parse the exposition format directly.

Best practice is the **master + dependent items** pattern: one HTTP scrape
feeds many derived items. A ready-to-import template lives at
`examples/zabbix/lidi-template.yaml` (Zabbix 6.0+ YAML format).

Items it defines:

| Item | Source | Notes |
|------|--------|-------|
| `lidi.metrics.raw` | HTTP agent, 30 s | master scrape, no history |
| `lidi.bytes.rate` | dependent | `lidi_bytes_total` + change-per-second |
| `lidi.packets.rate` | dependent | `lidi_packets_total` + change-per-second |
| `lidi.transfers.active` | dependent | `lidi_active_transfers` |
| `lidi.uptime` | dependent | `lidi_uptime_seconds` |
| `lidi.heartbeat.age` | dependent | `lidi_last_heartbeat_unix_seconds` → wall-clock age via JS preprocessing |
| `lidi.transfers.rate[{#RESULT}]` | LLD prototype | one per `result=started\|finished\|aborted` discovered from `lidi_transfers_total` |

Triggers shipped:

- **No heartbeat for `{$LIDI_HEARTBEAT_AGE_WARN}` s** (default 30) — fires
  on the receiver when the sender stops emitting heartbeats. lidi already
  warns in logs at 10 s; this is the page-the-oncall threshold.
- **Scrape failing for 2 min** — `/metrics` is silent, meaning lidi is
  down, `--http-addr` is not set, or the macros point at the wrong port.

Macros to override per host:

| Macro | Default | |
|-------|---------|--|
| `{$LIDI_HTTP_HOST}` | `127.0.0.1` | bind address of `--http-addr` |
| `{$LIDI_HTTP_PORT}` | `8080`      | port of `--http-addr` |
| `{$LIDI_HEARTBEAT_AGE_WARN}` | `30` | trigger threshold in seconds |

Quick start:

```text
Zabbix UI → Data collection → Templates → Import
  → examples/zabbix/lidi-template.yaml
Hosts → <your diode host> → Templates → link "lidi diode"
Macros → set {$LIDI_HTTP_PORT} per side if you bind differently
```

Same constraint as the Prometheus path: bind `--http-addr` to `127.0.0.1`
and run the Zabbix agent or proxy on the same host. The endpoint has no
authentication and no TLS (see `SECURITY.md`).

### Driving Test Traffic

`scripts/flood-test.sh` pumps sustained random data into a running
`diode-send` and prints live throughput sampled from `/api/status`. Use it to
exercise the dashboard or to benchmark a deployment.

```bash
# Defaults: 30s into 127.0.0.1:5000, polling http://127.0.0.1:8080/api/status
./scripts/flood-test.sh

# Override duration, target, or buffer size
DURATION=120 \
  SEND_TCP=127.0.0.1:5000 \
  STATUS_URL=http://127.0.0.1:8080/api/status \
  BUFFER_SIZE=4194304 \
  ./scripts/flood-test.sh
```

Preconditions: `diode-send` already listening on `$SEND_TCP` with
`--http-addr` enabled, and `diode-receive` writing to a reachable sink (e.g.
`nc -lk 127.0.0.1 7000`). The script auto-builds `diode-flood-test` if needed
and tears down the flood process on exit.

## Kernel Tuning (Receiver Side)

Required for reliable operation at speed. See `doc/tweaking.rst` for full details.

```bash
# Set NIC ring buffer to maximum
ethtool -G eth0 rx 4096

# Kernel UDP buffer sizing (value = MTU * packets_per_block * 127)
# For defaults: 1500 * 512 * 127 = 97536000
sysctl -w net.ipv4.udp_mem="97536000 97536000 97536000"
sysctl -w net.core.rmem_max=97536000
sysctl -w net.ipv4.udp_rmem_min=97536000
```

For sender-side high throughput (above 2.5 Gb/s):

```bash
sysctl -w net.ipv4.udp_mem="97536000 97536000 97536000"
sysctl -w net.core.wmem_max=97536000
sysctl -w net.ipv4.udp_wmem_min=97536000
```

## Validating Configuration

Before deploying, verify RaptorQ parameters are consistent:

```bash
diode-config --mtu 1500 --block 734928 --repair 2 --min-repair 1
```

This encodes a random block, shuffles packets, removes the specified percentage,
and verifies decoding succeeds. Use `--remove <percentage>` to simulate packet
loss.

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Receiver logs "no heartbeat" warnings | Sender not running, or firewall blocking UDP | Verify sender is running; check UDP path |
| Data loss / decode failures | Kernel UDP buffers too small | Apply sysctl tuning above |
| "Unix socket path already exists" | Previous run did not clean up | Remove stale socket file |
| Low throughput | Default parameters not tuned | Increase `--block`, adjust `--batch`, tune kernel buffers |
| Transfer hangs on receiver | `--reset-timeout` too long or `--abort-timeout` not set | Lower `--reset-timeout` or set `--abort-timeout` |

## Rollback

Lidi is a stateless binary with no persistent data. Rolling back is replacing
the binary with a previous version and restarting the process.
