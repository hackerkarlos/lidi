# Ansible deployment for lidi

Production-grade install of [lidi](https://github.com/ANSSI-FR/lidi) on Linux
servers, covering the sender side, the receiver side, or both. Two install
methods are supported: build from source on the target, or push a pre-built
binary from the control node (for air-gapped receivers).

## What this provisions

For each host:

- A non-login `lidi` system user (UID < 1000) and `/var/lib/lidi/` home dir.
- Build dependencies (apt or dnf), rustup-managed `stable` toolchain, and the
  `diode-send` / `diode-receive` binaries under `/usr/local/bin/`.
- A hardened systemd unit per binary (`lidi-send.service`,
  `lidi-receive.service`) with `NoNewPrivileges`, `ProtectSystem=strict`,
  `MemoryDenyWriteExecute`, etc.
- On receiver hosts: a `/etc/sysctl.d/60-lidi.conf` drop-in sizing the kernel
  UDP receive buffers to `MTU * packets_per_block * 127`
  (see `doc/tweaking.rst` for the formula).

## Requirements

| Component        | Version                       |
|------------------|-------------------------------|
| Ansible          | 2.14+ (uses FQCN, no callbacks) |
| Target OS        | Debian 12+, Ubuntu 22.04+, RHEL 9+, Fedora 39+ |
| Target Python    | 3.9+ (stock on supported distros) |
| Target arch      | x86_64 (lidi enables AVX/AVX2 features in `Cargo.toml`) |
| Privileges       | sudo / become to root on the target |

The `source` install method also needs outbound HTTPS to `github.com` and
`crates.io` from the target host. The `binary` install method does not.

## Quick start

```bash
cd ansible/
cp inventory.example.yml inventory.yml
$EDITOR inventory.yml                          # set hostnames + addresses

# Dry run against one side at a time
ansible-playbook -i inventory.yml site.yml --check --diff --limit lidi_send
ansible-playbook -i inventory.yml site.yml --check --diff --limit lidi_receive

# Apply
ansible-playbook -i inventory.yml site.yml --limit lidi_send
ansible-playbook -i inventory.yml site.yml --limit lidi_receive
```

After the second run, on each side:

```bash
sudo systemctl status lidi-send         # or lidi-receive
journalctl -u lidi-send -f
```

## Inventory layout

Two groups, one host (or more) per side. The minimum host vars are the
addresses — everything else has a sensible default.

```yaml
all:
  children:
    lidi_send:
      hosts:
        diode-low.example.internal:
          ansible_host: 10.10.0.5
          lidi_send_from_tcp: "10.10.0.5:5000"
          lidi_send_to: "10.20.0.6:6000"

    lidi_receive:
      hosts:
        diode-high.example.internal:
          ansible_host: 10.20.0.6
          lidi_receive_from: "10.20.0.6:6000"
          lidi_receive_to_tcp: "10.20.0.7:7000"
```

`lidi_send_to` on the sender and `lidi_receive_from` on the receiver
**must be the same address:port pair**, since that's where UDP packets
land. Misalignment is the most common deploy bug.

## Variables

### Shared (`group_vars/all.yml`)

| Variable                    | Default                                  | Notes |
|-----------------------------|------------------------------------------|-------|
| `lidi_user` / `lidi_group`  | `lidi`                                   | service identity |
| `lidi_install_prefix`       | `/usr/local/bin`                         | binary install dir |
| `lidi_install_method`       | `source`                                 | `source` or `binary` |
| `lidi_source_repo`          | `https://github.com/ANSSI-FR/lidi.git`   | git URL |
| `lidi_source_version`       | `master`                                 | tag / branch / SHA |
| `lidi_force_rebuild`        | `false`                                  | force `cargo build` |
| `lidi_binary_send_path`     | `""`                                     | controller path, only when `lidi_install_method=binary` |
| `lidi_binary_receive_path`  | `""`                                     | same, for receiver |
| `lidi_mtu`                  | `null` (lidi default 1500)               | `--to-mtu` / `--from-mtu` |
| `lidi_block_bytes`          | `null`                                   | `--block` |
| `lidi_repair_pct`           | `null`                                   | `--repair` |
| `lidi_batch`                | `null`                                   | `--batch` |
| `lidi_log_level`            | `Info`                                   | `Off..Trace` |
| `lidi_log_file`             | `""`                                     | empty = journald only |
| `lidi_http_addr`            | `""`                                     | e.g. `127.0.0.1:8080` |

> **Block geometry must match on both sides.** Set `lidi_mtu`,
> `lidi_block_bytes`, `lidi_repair_pct`, `lidi_batch` once in
> `group_vars/all.yml`, not per-side.

### Sender (`roles/lidi_send/defaults/main.yml`)

| Variable                       | Required | Maps to             |
|--------------------------------|----------|---------------------|
| `lidi_send_from_tcp`           | one of two | `--from-tcp`     |
| `lidi_send_from_unix`          | one of two | `--from-unix`    |
| `lidi_send_to`                 | yes      | `--to`              |
| `lidi_send_to_bind`            | no       | `--to-bind`         |
| `lidi_send_encode_threads`     | no       | `--encode-threads`  |
| `lidi_send_cpu_affinity`       | no       | `--cpu-affinity`    |
| `lidi_send_heartbeat`          | no       | `--heartbeat`       |
| `lidi_send_hash`               | no       | `--hash`            |
| `lidi_send_flush`              | no       | `--flush`           |

### Receiver (`roles/lidi_receive/defaults/main.yml`)

| Variable                          | Required   | Maps to             |
|-----------------------------------|------------|---------------------|
| `lidi_receive_from`               | yes        | `--from`            |
| `lidi_receive_to_tcp`             | one of two | `--to-tcp`          |
| `lidi_receive_to_unix`            | one of two | `--to-unix`         |
| `lidi_receive_decode_threads`     | no         | `--decode-threads`  |
| `lidi_receive_cpu_affinity`       | no         | `--cpu-affinity`    |
| `lidi_receive_heartbeat`          | no         | `--heartbeat`       |
| `lidi_receive_min_repair`         | no         | `--min-repair`      |
| `lidi_receive_reset_timeout`      | no         | `--reset-timeout`   |
| `lidi_receive_abort_timeout`      | no         | `--abort-timeout`   |
| `lidi_receive_hash`               | no         | `--hash`            |
| `lidi_receive_flush`              | no         | `--flush`           |
| `lidi_receive_apply_sysctl`       | no (true)  | install kernel-buffer drop-in |
| `lidi_receive_udp_buffer_bytes`   | no (97_536_000) | UDP buffer size in bytes |

If you change `lidi_mtu` or override the default block geometry, recompute
`lidi_receive_udp_buffer_bytes` as `MTU * packets_per_block * 127`.

## Air-gap deployment

The high (receive) side typically has no path to GitHub or crates.io. Use
`binary` mode there:

1. **On a build host (low side or detached staging):**

   ```bash
   git clone https://github.com/ANSSI-FR/lidi.git
   cd lidi
   cargo build --release --locked
   cp target/release/diode-receive /tmp/diode-receive-2.1.1
   ```

2. **Move the binary to the high-side control node** (USB, the diode itself
   once it's up, sneakernet, etc.).

3. **In the high-side inventory:**

   ```yaml
   lidi_receive:
     hosts:
       diode-high.example.internal:
         lidi_install_method: binary
         lidi_binary_receive_path: /tmp/diode-receive-2.1.1
         lidi_receive_from: "10.20.0.6:6000"
         lidi_receive_to_tcp: "10.20.0.7:7000"
   ```

4. **Apply:** `ansible-playbook -i inventory.yml site.yml --limit lidi_receive`

The low side keeps `lidi_install_method: source` so it stays self-updating
from upstream.

## Operating

| Action                   | Command                                                |
|--------------------------|--------------------------------------------------------|
| Status                   | `systemctl status lidi-send` (or `lidi-receive`)       |
| Live logs                | `journalctl -u lidi-send -f`                           |
| Restart                  | `systemctl restart lidi-send`                          |
| Upgrade (source mode)    | bump `lidi_source_version`, re-run the playbook        |
| Upgrade (binary mode)    | replace `lidi_binary_*_path`, re-run the playbook      |
| Force rebuild            | `-e lidi_force_rebuild=true`                           |
| Disable                  | `systemctl disable --now lidi-send`                    |

## Observability

Set `lidi_http_addr` (in `group_vars/all.yml` or per host) to enable the
embedded dashboard and `/metrics` endpoint:

```yaml
lidi_http_addr: "127.0.0.1:8080"
```

After re-applying the playbook, scrape `http://127.0.0.1:8080/metrics` from
a local Prometheus. Sample scrape config and a Grafana dashboard ship in
`examples/grafana/`. See `doc/RUNBOOK.md` for the metric reference.

> **Always bind to `127.0.0.1` or front with a reverse proxy.** The HTTP
> server has no authentication and no TLS — see `SECURITY.md` for the full
> exposure model.

## Firewall

The playbook does **not** modify firewall rules — too environment-specific.
Open these manually in your firewall manager of choice:

| From          | To              | Proto | Port           | Purpose             |
|---------------|-----------------|-------|----------------|---------------------|
| upstream prod | sender host     | TCP   | `lidi_send_from_tcp` port | data ingress |
| sender host   | receiver host   | UDP   | `lidi_send_to` port       | the diode link |
| downstream    | receiver host   | TCP   | `lidi_receive_to_tcp` port | data egress  |

In a real diode deployment the UDP path is physically unidirectional —
return traffic is dropped at L1, so heartbeats from the receiver back to
the sender are impossible by design.

## Verifying the deploy

End-to-end smoke test on the receiver host:

```bash
# On receiver: capture what comes out of the diode
nc -lk 0.0.0.0 7000 > /tmp/received.bin &

# On sender: push a marker
echo "hello-from-ansible-$(date -u +%FT%TZ)" | nc -q1 <sender_host> 5000

# On receiver: tail the file
tail -f /tmp/received.bin
```

For sustained load, copy `scripts/flood-test.sh` from the repo to a host
that can reach the sender's `--from-tcp` and the dashboard's
`/api/status`. See `doc/RUNBOOK.md#driving-test-traffic`.

## Layout

```
ansible/
├── README.md                                 ← this file
├── site.yml                                  ← top-level playbook
├── inventory.example.yml                     ← starter inventory
├── group_vars/
│   └── all.yml                               ← shared vars
└── roles/
    ├── lidi_common/                          ← user, build, install
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   └── tasks/{main,build_from_source,install_artifact}.yml
    ├── lidi_send/                            ← diode-send unit
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/diode-send.service.j2
    └── lidi_receive/                         ← diode-receive unit + sysctls
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/main.yml
        └── templates/{diode-receive.service,lidi-sysctl.conf}.j2
```
