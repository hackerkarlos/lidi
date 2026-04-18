# Contributing to This Project

Thank you for your interest in this project. Please read this document
carefully before considering any contributions.

## Scope of Contributions

This project only accepts contributions related to security maintenance. No
other types of contributions are expected or will be accepted at this time.

## Support Policy

Thank you for understanding and respecting the limited scope of this project's
contributions and support. In particular, there is no commitment regarding
processing times.

### Limited Support Scope

- Support is provided exclusively to contributors working on security-related
  improvements.
- The project maintainers will only assist with issues directly related to your
  security maintenance contributions.

### No General Support

- We do not offer general support for using or setting up the project.
- Questions, feature requests, or issues unrelated to active security
  maintenance contributions will not be addressed.

## Development Setup

### Prerequisites

- Rust stable toolchain (`rustup install stable`)
- Rust edition 2024 support (requires rustc 1.85+)

### Building

```bash
cargo build --release
```

This produces the following binaries in `target/release/`:

<!-- AUTO-GENERATED: commands-table -->
| Binary | Description |
|--------|-------------|
| `diode-send` | Sender part of lidi (TCP/Unix to UDP) |
| `diode-receive` | Receiver part of lidi (UDP to TCP/Unix) |
| `diode-oneshot-send` | Read stdin, send to diode-oneshot-receive (standalone) |
| `diode-oneshot-receive` | Receive from diode-oneshot-send, write to stdout (standalone) |
| `diode-send-file` | Send files to diode-receive-file through lidi |
| `diode-receive-file` | Receive files sent by diode-send-file through lidi |
| `diode-send-udp` | Send UDP datagrams to diode-receive-udp |
| `diode-receive-udp` | Receive UDP packets sent by diode-send-udp |
| `diode-config` | Test and validate diode configuration parameters |
| `diode-flood-test` | Send random data to diode-send for stress testing |
<!-- AUTO-GENERATED: end -->

### Docker

Build and run using Docker Compose:

```bash
docker compose build
docker compose up
```

The Dockerfile produces two multi-stage targets: `send` and `receive`, based on
Google's distroless `cc:nonroot` image.

### Code Style

- Clippy pedantic and nursery lints are enforced (`deny` level). Run before
  submitting:

  ```bash
  cargo clippy --all-targets
  ```

- Format code with:

  ```bash
  cargo fmt
  ```

### Developer Documentation

Generate and view internal API documentation:

```bash
cargo doc --document-private-items --no-deps --lib --open
```

### Smoke / Load Testing

`scripts/flood-test.sh` exercises a running diode end-to-end: it pumps random
traffic into `diode-send`, polls the observability endpoint at 1 Hz, and
prints per-second and average throughput. See
[`doc/RUNBOOK.md`](doc/RUNBOOK.md#driving-test-traffic) for the full setup.

## How to Contribute

1. Ensure your contribution is strictly related to security maintenance.
2. Fork the repository and create a new branch for your work.
3. Submit a pull request with a clear description of your security-related
   improvements.

## Security Vulnerabilities

If you discover a security vulnerability, please report it according to our
security policy outlined in the [`SECURITY.md`](SECURITY.md).
