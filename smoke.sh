#!/usr/bin/env bash
# Three stages: offline logic (always), the popup layout regression (needs a GUI
# session), then the real web load (needs the internet and a login).
set -uo pipefail

APP_NAME="Google Suite"
SELFTEST_LIMIT="${SELFTEST_LIMIT:-60}"
SMOKE_LIMIT="${SMOKE_LIMIT:-90}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/$APP_NAME.app/Contents/MacOS/$APP_NAME"
STATUS=0

[[ -x "$BIN" ]] || { echo "not built: run ./build.sh" >&2; exit 1; }

# macOS has no `timeout`, so arm a watchdog per stage: a wedged UI test must
# fail the run, not hang it forever.
run_limited() {
  local limit=$1; shift
  "$@" & local pid=$!
  ( sleep "$limit"; kill -9 "$pid" 2>/dev/null ) & local watchdog=$!
  wait "$pid"; local code=$?
  kill -9 "$watchdog" 2>/dev/null
  if (( code == 137 )); then echo "KILLED after ${limit}s"; return 1; fi
  return $code
}

echo "== selftest (offline, ${SELFTEST_LIMIT}s limit) =="
if ! run_limited "$SELFTEST_LIMIT" "$BIN" --selftest; then STATUS=1; fi

if [[ "${SKIP_SMOKE:-0}" == "1" ]]; then
  echo "== smoke skipped (SKIP_SMOKE=1) =="
  exit $STATUS
fi

echo "== popup layout (window must survive a window.open panel, ${PROBE_LIMIT:-45}s) =="
if ! run_limited "${PROBE_LIMIT:-45}" "$BIN" --popupprobe; then STATUS=1; fi

echo "== gmail chrome (rails must be gone, controls must remain) =="
if ! run_limited "${CHECK_LIMIT:-60}" "$BIN" --domcheck; then STATUS=1; fi

echo "== smoke (live: calendar.google.com + mail.google.com, ${SMOKE_LIMIT}s limit) =="
if ! run_limited "$SMOKE_LIMIT" "$BIN" --smoke; then STATUS=1; fi

exit $STATUS
