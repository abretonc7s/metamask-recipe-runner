#!/usr/bin/env bash
set -euo pipefail

TARGET="$PWD"
PLATFORM="ios"
PREFLIGHT_MODE="${RECIPE_HARNESS_MOBILE_PREFLIGHT_MODE:-fast}"
ARTIFACTS=""
PORT="${WATCHER_PORT:-${METRO_PORT:-${CDP_PORT:-}}}"
SIMULATOR="${IOS_SIMULATOR:-${SIM_UDID:-}}"
ADB_SERIAL_ARG="${ADB_SERIAL:-${ANDROID_SERIAL:-}}"
RUNTIME_DIR_ARG="${RECIPE_RUNTIME_DIR:-}"
WALLET_SETUP=false
require_value() { [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) require_value "$@"; TARGET="$2"; shift 2 ;;
    --platform) require_value "$@"; PLATFORM="$2"; shift 2 ;;
    --preflight-mode|--mode) require_value "$@"; PREFLIGHT_MODE="$2"; shift 2 ;;
    --artifacts-dir) require_value "$@"; ARTIFACTS="$2"; shift 2 ;;
    --port|--watcher-port|--cdp-port) require_value "$@"; PORT="$2"; shift 2 ;;
    --simulator) require_value "$@"; SIMULATOR="$2"; shift 2 ;;
    --adb-serial) require_value "$@"; ADB_SERIAL_ARG="$2"; shift 2 ;;
    --runtime-dir) require_value "$@"; RUNTIME_DIR_ARG="$2"; shift 2 ;;
    --wallet-setup) WALLET_SETUP=true; shift ;;
    --no-wallet-setup) WALLET_SETUP=false; shift ;;
    --wallet-fixture) shift 2 ;;
    -h|--help)
      echo "Usage: launch.sh [--target <metamask-mobile>] [--platform ios|android] [--port <port>] [--simulator <sim>] [--runtime-dir <dir>] [--wallet-setup]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$PLATFORM" in ios|android) ;; *) echo "Unknown --platform: $PLATFORM" >&2; exit 2 ;; esac
case "$PREFLIGHT_MODE" in fast|auto|default|rebuild-native|clean) ;; *) echo "Unknown --preflight-mode: $PREFLIGHT_MODE" >&2; exit 2 ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/path.sh"
TARGET="$(cd "$TARGET" && pwd)"
HARNESS_DIR="$(harness_dir "$TARGET" mobile)"
RUNNER_BIN="$HARNESS_DIR/runner/bin/metamask-recipe"
ARTIFACTS="${ARTIFACTS:-$HARNESS_DIR/launch/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$ARTIFACTS/logs"

if [ ! -x "$RUNNER_BIN" ]; then
  echo "Mobile recipe runner is not installed in $TARGET. Run metamask-recipe mobile install --target $TARGET first." >&2
  exit 1
fi

prepare_args=(mobile prepare --target "$TARGET" --platform "$PLATFORM")
[ -n "$PORT" ] && prepare_args+=(--port "$PORT")
[ -n "$SIMULATOR" ] && prepare_args+=(--simulator "$SIMULATOR")
[ -n "$ADB_SERIAL_ARG" ] && prepare_args+=(--adb-serial "$ADB_SERIAL_ARG")
[ -n "$RUNTIME_DIR_ARG" ] && prepare_args+=(--runtime-dir "$RUNTIME_DIR_ARG")
$WALLET_SETUP && prepare_args+=(--wallet-setup)

status="pass"
if (cd "$TARGET" && "$RUNNER_BIN" "${prepare_args[@]}") > "$ARTIFACTS/logs/prepare.log" 2>&1; then
  runtime_status="pass"
else
  runtime_status="fail"
  status="fail"
fi

status_args=(mobile runtime-status --target "$TARGET" --json)
[ -n "$PORT" ] && status_args+=(--port "$PORT")
[ -n "$RUNTIME_DIR_ARG" ] && status_args+=(--runtime-dir "$RUNTIME_DIR_ARG")
(cd "$TARGET" && "$RUNNER_BIN" "${status_args[@]}") > "$ARTIFACTS/runtime-status.json" 2> "$ARTIFACTS/logs/runtime-status.err" || true

TARGET_FOR_SUMMARY="$TARGET" ARTIFACTS_FOR_SUMMARY="$ARTIFACTS" STATUS_FOR_SUMMARY="$status" RUNTIME_STATUS="$runtime_status" PLATFORM_FOR_SUMMARY="$PLATFORM" MODE_FOR_SUMMARY="$PREFLIGHT_MODE" node <<'NODE'
const fs = require('fs');
const path = require('path');
const artifacts = process.env.ARTIFACTS_FOR_SUMMARY;
let runtime = null;
try { runtime = JSON.parse(fs.readFileSync(path.join(artifacts, 'runtime-status.json'), 'utf8')); } catch {}
fs.writeFileSync(path.join(artifacts, 'summary.json'), `${JSON.stringify({
  adapter: 'mobile',
  action: 'launch',
  status: process.env.STATUS_FOR_SUMMARY,
  platform: process.env.PLATFORM_FOR_SUMMARY,
  preflightMode: process.env.MODE_FOR_SUMMARY,
  target: process.env.TARGET_FOR_SUMMARY,
  runtime: {
    status: process.env.RUNTIME_STATUS,
    ready: runtime?.ready === true,
    reason: runtime?.reason || null,
    port: runtime?.metro?.port || null,
    prepareLogPath: path.join(artifacts, 'logs/prepare.log'),
    runtimeStatusPath: path.join(artifacts, 'runtime-status.json'),
  },
  runtimePolicy: {
    nativeBuildPolicy: 'launch installs native app only when missing; otherwise starts/reuses Metro, prewarms the bundle, opens the dev client, and waits for the bridge',
  },
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE

echo "Mobile harness launch $status: $ARTIFACTS/summary.json"
[ "$status" = "pass" ]
