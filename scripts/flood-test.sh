#!/usr/bin/env bash
#
# flood-test.sh — drive sustained random traffic into a running diode-send and
# poll its observability dashboard for live throughput.
#
# Assumes diode-send is already listening on $SEND_TCP and that its HTTP
# observability endpoint is reachable at $STATUS_URL. It does NOT spin up the
# diode itself — start it first via cargo or docker compose.
#
# Usage:
#   scripts/flood-test.sh                    # 30s flood with defaults
#   DURATION=120 scripts/flood-test.sh       # longer run
#   SEND_TCP=127.0.0.1:5000 \
#     STATUS_URL=http://127.0.0.1:8080/api/status \
#     BUFFER_SIZE=$((4*1024*1024)) \
#     scripts/flood-test.sh
#
# Exit codes: 0 = ran to completion, 1 = setup/precondition failure.

set -euo pipefail

SEND_TCP="${SEND_TCP:-127.0.0.1:5000}"
STATUS_URL="${STATUS_URL:-http://127.0.0.1:8080/api/status}"
DURATION="${DURATION:-30}"
BUFFER_SIZE="${BUFFER_SIZE:-4194304}"
FLOOD_BIN="${FLOOD_BIN:-./target/release/diode-flood-test}"

cd "$(git rev-parse --show-toplevel)"

if [[ ! -x "$FLOOD_BIN" ]]; then
  echo "diode-flood-test not found at $FLOOD_BIN — building release profile..." >&2
  cargo build --release --bin diode-flood-test >&2
fi

if ! curl -fsS --max-time 2 "$STATUS_URL" >/dev/null; then
  echo "ERROR: dashboard unreachable at $STATUS_URL" >&2
  echo "       start diode-send with --http-addr first" >&2
  exit 1
fi

# Snapshot a numeric field from the /api/status JSON without depending on jq.
status_field() {
  curl -fsS --max-time 2 "$STATUS_URL" \
    | grep -oE "\"$1\":[0-9]+" \
    | head -1 \
    | cut -d: -f2
}

flood_pid=""
cleanup() {
  if [[ -n "$flood_pid" ]] && kill -0 "$flood_pid" 2>/dev/null; then
    kill "$flood_pid" 2>/dev/null || true
    wait "$flood_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

bytes_start=$(status_field bytes_total)
ts_start=$(date +%s)

echo "Flooding $SEND_TCP for ${DURATION}s (buffer ${BUFFER_SIZE} bytes)"
echo "Polling $STATUS_URL"
echo

"$FLOOD_BIN" --to-tcp "$SEND_TCP" --buffer-size "$BUFFER_SIZE" --log-level Off \
  >/dev/null 2>&1 &
flood_pid=$!

prev_bytes=$bytes_start
prev_ts=$ts_start
printf '%-8s  %-12s  %-12s  %-10s\n' 'elapsed' 'bytes_total' 'delta_bytes' 'MB/s'
for ((i = 1; i <= DURATION; i++)); do
  sleep 1
  if ! kill -0 "$flood_pid" 2>/dev/null; then
    echo "flood-test exited unexpectedly" >&2
    exit 1
  fi
  now_bytes=$(status_field bytes_total)
  now_ts=$(date +%s)
  delta=$((now_bytes - prev_bytes))
  rate=$(awk -v d="$delta" -v t=$((now_ts - prev_ts)) \
    'BEGIN { if (t > 0) printf "%.1f", (d / 1048576) / t; else print "0.0" }')
  printf '%-8s  %-12s  %-12s  %-10s\n' "${i}s" "$now_bytes" "$delta" "$rate"
  prev_bytes=$now_bytes
  prev_ts=$now_ts
done

bytes_end=$(status_field bytes_total)
total=$((bytes_end - bytes_start))
elapsed=$(( $(date +%s) - ts_start ))
avg=$(awk -v t="$total" -v s="$elapsed" \
  'BEGIN { if (s > 0) printf "%.1f", (t / 1048576) / s; else print "0.0" }')

echo
echo "Total bytes through diode-send : $total"
echo "Elapsed                        : ${elapsed}s"
echo "Average                        : ${avg} MB/s"
