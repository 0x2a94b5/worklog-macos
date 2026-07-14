#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_PATH="${1:-$ROOT/build/DerivedData/Build/Products/Debug/WorkLog.app}"
EXECUTABLE="$APP_PATH/Contents/MacOS/WorkLog"
LOG_FILE="$ROOT/build/app-smoke-test.log"

if [[ ! -x "$EXECUTABLE" ]]; then
  print -u2 "App executable not found: $EXECUTABLE"
  exit 1
fi

"$EXECUTABLE" >"$LOG_FILE" 2>&1 &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

sleep 2

if ! kill -0 "$APP_PID" 2>/dev/null; then
  print -u2 "WorkLog exited during startup:"
  tail -80 "$LOG_FILE" >&2
  exit 1
fi

print "App startup smoke test passed"
