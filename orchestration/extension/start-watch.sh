#!/usr/bin/env bash
# start-watch.sh — harness-owned webpack watcher with dual-writer prevention
# (formerly: the --start-watch block of the prepare_parts mega-string in
# scripts/extension/live.sh)
#
# Purpose:
#   Clean-build path for one extension checkout: clears the webpack cache,
#   starts (or reuses) the harness-owned `yarn start` watcher, and waits for
#   a compile success marker. Refuses to run if a slot-owned watcher is alive.
#
# Inputs (flags / env):
#   --target <metamask-extension> (default $PWD; becomes the working dir)
#   --runtime-dir <rel> (default from orchestration/lib path-defaults)
#   --runner-bin <path> (optional; records deps/cache baseline best-effort)
#   --summary <file> (optional; writes the standard summary.json shape)
#
# Outputs:
#   <runtime-dir>/recipe-harness-webpack.{pid,log}; optional --summary file
#   {feature,status,inputs,outputs,generatedAt}.
#   Exit 0 — compiled; 1 — slot watcher owns the checkout, build failed, or
#   compile-marker timeout (240x2s); 2 — bad args.
#
# Never touches: the slot-owned webpack.pid watcher process (refusal only,
# removes the pid file only when stale); product source files.
set -euo pipefail

TARGET="$PWD"
RUNTIME_DIR=""
RUNNER_BIN=""
SUMMARY=""
require_value() { [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) require_value "$@"; TARGET="$2"; shift 2 ;;
    --runtime-dir) require_value "$@"; RUNTIME_DIR="$2"; shift 2 ;;
    --runner-bin) require_value "$@"; RUNNER_BIN="$2"; shift 2 ;;
    --summary) require_value "$@"; SUMMARY="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: start-watch.sh [--target <metamask-extension>] [--runtime-dir <rel>] [--runner-bin <path>] [--summary <file>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$RUNTIME_DIR" ]; then
  # shellcheck disable=SC1091
  for _hp in "$SCRIPT_DIR/lib/harness-path.sh" "$SCRIPT_DIR/../lib/harness-path.sh"; do
    [ -f "$_hp" ] && { . "$_hp"; break; }
  done
  unset _hp
  if ! command -v recipe_runtime_dir >/dev/null 2>&1; then
    echo "start-watch: shared lib orchestration/lib/harness-path.sh not found; pass --runtime-dir." >&2
    exit 1
  fi
  RUNTIME_DIR="$(recipe_runtime_dir)"
fi

cd "$TARGET"
status=fail
finish() {
  if [ -n "$SUMMARY" ]; then
    mkdir -p "$(dirname "$SUMMARY")"
    STATUS_FOR_SUMMARY="$status" TARGET_FOR_SUMMARY="$PWD" RUNTIME_DIR_FOR_SUMMARY="$RUNTIME_DIR" SUMMARY_PATH="$SUMMARY" node <<'NODE' || true
const fs = require('fs');
fs.writeFileSync(process.env.SUMMARY_PATH, `${JSON.stringify({
  feature: 'extension/start-watch',
  status: process.env.STATUS_FOR_SUMMARY,
  inputs: { target: process.env.TARGET_FOR_SUMMARY, runtimeDir: process.env.RUNTIME_DIR_FOR_SUMMARY },
  outputs: {
    watchPidFile: `${process.env.RUNTIME_DIR_FOR_SUMMARY}/recipe-harness-webpack.pid`,
    watchLog: `${process.env.RUNTIME_DIR_FOR_SUMMARY}/recipe-harness-webpack.log`,
  },
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE
  fi
}
trap finish EXIT

mkdir -p "$RUNTIME_DIR"

# Explicit clean-build path: clear the target-scoped webpack cache before
# starting the harness-owned watcher. Faster incremental refresh stays on
# `mme-recipe refresh`; this script is for proving a clean build works.
echo '[recipe-harness] clean build: clearing webpack cache + harness watcher'
rm -rf node_modules/.cache/webpack
if [ -f "$RUNTIME_DIR/recipe-harness-webpack.pid" ]; then
  kill "$(cat "$RUNTIME_DIR/recipe-harness-webpack.pid" 2>/dev/null)" >/dev/null 2>&1 || true
  rm -f "$RUNTIME_DIR/recipe-harness-webpack.pid"
fi

# Do not start a second writer for dist/chrome. Slot-owned watches use
# webpack.pid; harness-owned watches use recipe-harness-webpack.pid.
slot_watch_pid_file="$RUNTIME_DIR/webpack.pid"
if [ -f "$slot_watch_pid_file" ]; then
  slot_watch_pid=$(cat "$slot_watch_pid_file" 2>/dev/null || true)
else
  slot_watch_pid=
fi
if [ -n "$slot_watch_pid" ] && kill -0 "$slot_watch_pid" >/dev/null 2>&1; then
  echo "[recipe-harness] Refusing to start yarn start: slot webpack watch already owns this checkout (pid $slot_watch_pid). Stop it first or reuse the live browser." >&2
  exit 1
fi
[ -z "$slot_watch_pid" ] || rm -f "$slot_watch_pid_file"

# Scope watcher reuse to this checkout. A machine-global pgrep can match an
# unrelated repo and leave this target validating stale dist/chrome output.
watch_pid_file="$RUNTIME_DIR/recipe-harness-webpack.pid"
watch_log="$RUNTIME_DIR/recipe-harness-webpack.log"
if [ -f "$watch_pid_file" ]; then
  watch_pid=$(cat "$watch_pid_file" 2>/dev/null || true)
else
  watch_pid=
fi
if [ -z "$watch_pid" ] || ! kill -0 "$watch_pid" >/dev/null 2>&1; then
  rm -f "$watch_pid_file"
  : > "$watch_log"
  echo "[recipe-harness] Starting yarn start; streaming $watch_log"
  nohup env -u BUNDLED_DEBUGPY_PATH yarn start > "$watch_log" 2>&1 &
  echo $! > "$watch_pid_file"
else
  echo "[recipe-harness] Reusing existing yarn start pid $watch_pid; streaming $watch_log"
fi

tail -n +1 -F "$watch_log" &
watch_tail_pid=$!
compiled=false
for i in {1..240}; do
  if grep -Eq 'Module build failed|^ERROR in |compiled with [1-9][0-9]* error' "$watch_log" 2>/dev/null; then
    kill "$watch_tail_pid" >/dev/null 2>&1 || true
    wait "$watch_tail_pid" 2>/dev/null || true
    echo '[recipe-harness] webpack BUILD FAILED (not waiting for timeout):' >&2
    grep -E -A3 'Module build failed|^ERROR in ' "$watch_log" 2>/dev/null | tail -30 >&2
    echo '[recipe-harness] If it is a stale-cache ENOENT it should have been auto-cleared; a recurring error here is a real source/build issue to fix.' >&2
    exit 1
  fi
  if grep -Eq 'compiled successfully|compiled with [0-9]+ warning|MetaMask .* compiled|Bundle end: service worker|Bundle end:.*app-init' "$watch_log" 2>/dev/null; then
    compiled=true
    break
  fi
  sleep 2
done
kill "$watch_tail_pid" >/dev/null 2>&1 || true
wait "$watch_tail_pid" 2>/dev/null || true
if [ "$compiled" != true ]; then
  echo 'Timed out waiting for target-scoped yarn start compilation marker' >&2
  tail -80 "$watch_log" >&2 || true
  exit 1
fi
echo '[recipe-harness] yarn start compiled successfully'
if [ -n "$RUNNER_BIN" ]; then
  "$RUNNER_BIN" runtime-decision --adapter extension --target . --record --json >/dev/null 2>&1 || true
  echo '[recipe-harness] recorded deps/cache baseline (runtime-decision --record)'
fi
status=pass
