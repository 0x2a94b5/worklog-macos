#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_PATH="${1:-$ROOT/build/DerivedData/Build/Products/Debug/WorkLog.app}"
APP_PATH="${APP_PATH:A}"
EXECUTABLE="$APP_PATH/Contents/MacOS/WorkLog"
TEST_ROOT=$(mktemp -d "${TMPDIR%/}/WorkLogUITest.XXXXXX")
DATA_DIR="$TEST_ROOT/Data"
DRIVER="$TEST_ROOT/UIInteractionDriver"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  local canonical_root="${TEST_ROOT:A}"
  local canonical_tmp="${TMPDIR:A}"
  case "$canonical_root" in
    "${canonical_tmp%/}/WorkLogUITest."*) rm -rf -- "$canonical_root" ;;
    *) print -u2 "Refusing to remove unexpected UI test path: $canonical_root" ;;
  esac
}
trap cleanup EXIT INT TERM

if [[ ! -x "$EXECUTABLE" ]]; then
  print -u2 "App executable not found: $EXECUTABLE"
  exit 1
fi

xcrun swiftc -parse-as-library "$ROOT/Tests/UIInteractionDriver.swift" -o "$DRIVER"

mkdir -p "$DATA_DIR"
WORKLOG_DATA_DIRECTORY="$DATA_DIR" WORKLOG_UI_TEST_MODE=1 \
  "$EXECUTABLE" >"$TEST_ROOT/app.log" 2>&1 &
APP_PID=$!
for _ in {1..40}; do
  kill -0 "$APP_PID" 2>/dev/null && break
  sleep 0.1
done
if ! kill -0 "$APP_PID" 2>/dev/null; then
  print -u2 "Unable to launch WorkLog for UI test bootstrap"
  cat "$TEST_ROOT/app.log" >&2
  exit 1
fi
sleep 2
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

MONTH=$(date +%Y-%m)
NOW=$(date +%s)
TASK_ID="ui-focus-test"
TASK_TITLE="UI Focus Test"
sqlite3 "$DATA_DIR/worklog.sqlite" <<SQL
INSERT INTO work_items (
    id, month, title, note, status, module, parent_id, level, sort_order,
    raw_text, started_at, completed_at, deleted_at, created_at, updated_at
) VALUES (
    '$TASK_ID', '$MONTH', '$TASK_TITLE', '', 'todo', '未分类', NULL, 0, 1,
    '', NULL, NULL, NULL, $NOW, $NOW
);
SQL

WORKLOG_DATA_DIRECTORY="$DATA_DIR" WORKLOG_UI_TEST_MODE=1 \
  "$EXECUTABLE" >"$TEST_ROOT/app.log" 2>&1 &
APP_PID=$!
for _ in {1..40}; do
  kill -0 "$APP_PID" 2>/dev/null && break
  sleep 0.1
done
if ! kill -0 "$APP_PID" 2>/dev/null; then
  print -u2 "Unable to launch WorkLog for UI interaction test"
  cat "$TEST_ROOT/app.log" >&2
  exit 1
fi
sleep 2

osascript - "$APP_PID" <<'APPLESCRIPT'
on run argv
  set targetPID to (item 1 of argv) as integer
  tell application "System Events"
    set frontmost of first process whose unix id is targetPID to true
  end tell
end run
APPLESCRIPT
for _ in {1..40}; do
  FRONT_STATE=$(osascript - "$APP_PID" <<'APPLESCRIPT'
on run argv
  set targetPID to (item 1 of argv) as integer
  tell application "System Events"
    tell first process whose unix id is targetPID
      return (frontmost as text) & ":" & (count of windows as text)
    end tell
  end tell
end run
APPLESCRIPT
)
  [[ "$FRONT_STATE" == "true:"* && "$FRONT_STATE" != "true:0" ]] && break
  sleep 0.1
done
if [[ "$FRONT_STATE" != "true:"* || "$FRONT_STATE" == "true:0" ]]; then
  print -u2 "WorkLog UI test window did not become active: $FRONT_STATE"
  exit 1
fi

if ! "$DRIVER" "$APP_PID" "$TASK_TITLE"; then
  cat "$TEST_ROOT/app.log" >&2
  exit 1
fi

SAVED_TITLE=$(sqlite3 "$DATA_DIR/worklog.sqlite" "SELECT title FROM work_items WHERE id = '$TASK_ID';")
if [[ "$SAVED_TITLE" != "$TASK_TITLE Enter Outside" ]]; then
  print -u2 "Unexpected saved title: $SAVED_TITLE"
  exit 1
fi

print "UI interaction database verification passed"
