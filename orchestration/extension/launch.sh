#!/usr/bin/env bash
# launch.sh — extension instance launch: prepare command + CDP readiness
# (formerly: scripts/extension/launch.sh)
#
# Purpose:
#   Runs the caller-supplied prepare command (cwd = target) for one slot,
#   then confirms the app-control runtime via extension-readiness.
#
# Inputs (flags / env):
#   --target <metamask-extension> (default $PWD)
#   --cdp-port <port> (numeric-validated)
#   --prepare-cmd <cmd> (env RECIPE_HARNESS_EXTENSION_LAUNCH_CMD)
#   --artifacts-dir <dir> (default <harness>/launch/<UTC>)
#
# Outputs:
#   <artifacts>/summary.json (adapter/action/status/prepare/appControl),
#   <artifacts>/logs/{launch.log,extension-readiness.json}.
#   Exit 0 — launch pass; 1 — harness not installed / prepare or readiness
#   failed; 2 — bad args.
#
# Never touches: product source files; anything outside the target's
# harness dir and the artifacts dir.
set -euo pipefail

TARGET="$PWD"
CDP_PORT=""
ARTIFACTS=""
PREPARE_CMD="${RECIPE_HARNESS_EXTENSION_LAUNCH_CMD:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --cdp-port) CDP_PORT="$2"; shift 2 ;;
    --artifacts-dir) ARTIFACTS="$2"; shift 2 ;;
    --prepare-cmd) PREPARE_CMD="$2"; shift 2 ;;
    -h|--help) echo "Usage: launch.sh [--target <metamask-extension>] [--cdp-port <port>] [--prepare-cmd <cmd>] [--artifacts-dir <dir>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Reject a non-numeric --cdp-port before it reaches the prepare/launch command.
if [ -n "$CDP_PORT" ]; then
  case "$CDP_PORT" in
    *[!0-9]*) echo "Invalid --cdp-port (must be numeric): $CDP_PORT" >&2; exit 2 ;;
  esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
for _hp in "$SCRIPT_DIR/lib/harness-path.sh" "$SCRIPT_DIR/../lib/harness-path.sh"; do
  [ -f "$_hp" ] && { . "$_hp"; break; }
done
unset _hp
if ! command -v harness_root >/dev/null 2>&1; then
  echo "metamask-recipe: shared lib orchestration/lib/harness-path.sh not found; reinstall the runner." >&2
  exit 1
fi
READINESS_MJS="$SCRIPT_DIR/readiness.mjs"
if [ ! -f "$READINESS_MJS" ]; then
  echo "metamask-recipe: readiness.mjs not found next to $SCRIPT_DIR; reinstall the runner." >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
HARNESS_DIR="$(harness_dir "$TARGET" extension)"
ARTIFACTS="${ARTIFACTS:-$HARNESS_DIR/launch/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$ARTIFACTS/logs"

if [ ! -f "$HARNESS_DIR/manifest.json" ]; then
  echo "Extension recipe harness is not installed in $TARGET. Run metamask-recipe extension prepare --target $TARGET first." >&2
  exit 1
fi

if [ -n "$PREPARE_CMD" ]; then
  echo "Launching Extension harness runtime with caller-supplied prepare command" | tee "$ARTIFACTS/logs/launch.log"
  set +e
  (
    cd "$TARGET"
    bash -lc "$PREPARE_CMD"
  ) 2>&1 | tee -a "$ARTIFACTS/logs/launch.log"
  prepare_status=${PIPESTATUS[0]}
  set -e
else
  echo "No Extension prepare command supplied; reusing existing CDP runtime if reachable." | tee "$ARTIFACTS/logs/launch.log"
  prepare_status=0
fi

status="pass"
if [ "$prepare_status" -ne 0 ]; then
  status="fail"
elif [ -z "$CDP_PORT" ]; then
  echo "Missing --cdp-port; cannot confirm Extension app-control runtime." | tee -a "$ARTIFACTS/logs/launch.log"
  status="fail"
elif node "$READINESS_MJS" --target "$TARGET" --cdp-port "$CDP_PORT" --json > "$ARTIFACTS/logs/extension-readiness.json" 2>&1; then
  :
else
  status="fail"
fi

TARGET_FOR_SUMMARY="$TARGET" ARTIFACTS_FOR_SUMMARY="$ARTIFACTS" STATUS_FOR_SUMMARY="$status" CDP_PORT_FOR_SUMMARY="$CDP_PORT" PREPARE_SUPPLIED="$([ -n "$PREPARE_CMD" ] && echo true || echo false)" PREPARE_STATUS="$prepare_status" node <<'NODE'
const fs = require('fs');
const path = require('path');
const target = process.env.TARGET_FOR_SUMMARY;
const artifacts = process.env.ARTIFACTS_FOR_SUMMARY;
let readiness = null;
try { readiness = JSON.parse(fs.readFileSync(path.join(artifacts, 'logs/extension-readiness.json'), 'utf8')); } catch {}
const appControlStatus =
  process.env.STATUS_FOR_SUMMARY === 'pass' && readiness && readiness.status !== 'fail' ? 'pass' : 'fail';
fs.writeFileSync(path.join(artifacts, 'summary.json'), `${JSON.stringify({
  adapter: 'extension',
  action: 'launch',
  status: process.env.STATUS_FOR_SUMMARY,
  target,
  cdpPort: process.env.CDP_PORT_FOR_SUMMARY || null,
  prepare: {
    commandSupplied: process.env.PREPARE_SUPPLIED === 'true',
    status: Number(process.env.PREPARE_STATUS) === 0 ? 'pass' : 'fail',
    exitCode: Number(process.env.PREPARE_STATUS),
    logPath: path.join(artifacts, 'logs/launch.log'),
  },
  runtimePolicy: {
    runtimeReusePolicy: 'reuse a running harness-compatible CDP target when possible; caller-supplied startup commands must use cached/watch-only paths unless the human explicitly permits a rebuild',
  },
  appControl: {
    status: appControlStatus,
    readiness,
  },
  cleanupCommand: 'Use the installed harness manifest cleanupCommand.',
  note: 'Launch starts/reuses the harness runtime only; it does not run a recipe or claim evidence validation. Extension startup commands are caller-supplied so the runner does not encode local machine aliases.',
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE

echo "Extension harness launch $status: $ARTIFACTS/summary.json"
[ "$status" = "pass" ]
