#!/usr/bin/env bash
# live.sh — mobile launch-then-verify chaining for one live slot run
#
# Purpose:
#   Runs launch.sh then verify.sh (verify with --no-auto-start; launch owns
#   startup) under a timestamped artifact dir and aggregates both results.
#
# Inputs (flags / env):
#   --target <metamask-mobile> (default $PWD)
#   --platform ios|android (default ios)
#   --preflight-mode|--mode fast|auto|default|rebuild-native|clean
#       (env RECIPE_HARNESS_MOBILE_PREFLIGHT_MODE, default fast)
#   --artifacts-dir <dir> (default <harness>/live/<UTC>)
#   --wallet-setup|--no-wallet-setup (default auto), --wallet-fixture <json>
#
# Outputs:
#   <artifacts>/summary.json (adapter/action/status, launch/verify exit codes
#   + child summary paths, easyCommand), <artifacts>/{launch,verify}/.
#   Exit 0 — launch and verify both passed; 1 — either failed; 2 — bad args.
#
# Never touches: product source files; anything outside the target's harness
# dir and the artifacts dir.
set -euo pipefail

TARGET="$PWD"
PLATFORM="ios"
PREFLIGHT_MODE="${RECIPE_HARNESS_MOBILE_PREFLIGHT_MODE:-fast}"
ARTIFACTS=""
WALLET_SETUP="auto"
WALLET_FIXTURE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --preflight-mode|--mode) PREFLIGHT_MODE="$2"; shift 2 ;;
    --artifacts-dir) ARTIFACTS="$2"; shift 2 ;;
    --wallet-setup) WALLET_SETUP="true"; shift ;;
    --no-wallet-setup) WALLET_SETUP="false"; shift ;;
    --wallet-fixture) WALLET_FIXTURE="$2"; shift 2 ;;
    -h|--help) echo "Usage: live.sh [--target <metamask-mobile>] [--platform ios|android] [--preflight-mode fast|auto|default|rebuild-native|clean] [--artifacts-dir <dir>] [--wallet-setup|--no-wallet-setup]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$PLATFORM" in ios|android) ;; *) echo "Unknown --platform: $PLATFORM" >&2; exit 2 ;; esac
case "$PREFLIGHT_MODE" in fast|auto|default|rebuild-native|clean) ;; *) echo "Unknown --preflight-mode: $PREFLIGHT_MODE" >&2; exit 2 ;; esac

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
# verify.sh is a recipe-tree feature: co-located in installed copies, under
# recipe/mobile in a repo checkout.
VERIFY_SH=""
for _v in "$SCRIPT_DIR/verify.sh" "$SCRIPT_DIR/../../recipe/mobile/verify.sh"; do
  [ -f "$_v" ] && { VERIFY_SH="$_v"; break; }
done
unset _v
if [ -z "$VERIFY_SH" ]; then
  echo "metamask-recipe: mobile verify.sh not found next to $SCRIPT_DIR; reinstall the runner." >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
WALLET_FIXTURE="${WALLET_FIXTURE:-$(recipe_runtime_dir)/wallet-fixture.json}"
ARTIFACTS="${ARTIFACTS:-$(harness_dir "$TARGET" mobile)/live/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$ARTIFACTS"

launch_args=(--target "$TARGET" --platform "$PLATFORM" --preflight-mode "$PREFLIGHT_MODE" --artifacts-dir "$ARTIFACTS/launch")
case "$WALLET_SETUP" in
  true) launch_args+=(--wallet-setup) ;;
  false) launch_args+=(--no-wallet-setup) ;;
esac
launch_args+=(--wallet-fixture "$WALLET_FIXTURE")

echo "Mobile live validation command:"
echo "  metamask-recipe live --platform $PLATFORM --preflight-mode $PREFLIGHT_MODE"
echo "Launch artifacts: $ARTIFACTS/launch"
echo "Verify artifacts: $ARTIFACTS/verify"

set +e
"$SCRIPT_DIR/launch.sh" "${launch_args[@]}"
launch_status=$?
set -e

verify_status=1
if [ "$launch_status" -eq 0 ]; then
  set +e
  "$VERIFY_SH" --target "$TARGET" --platform "$PLATFORM" --preflight-mode "$PREFLIGHT_MODE" --no-auto-start --artifacts-dir "$ARTIFACTS/verify"
  verify_status=$?
  set -e
else
  echo "Skipping Mobile live verify because launch failed; see $ARTIFACTS/launch/summary.json" >&2
fi

TARGET_FOR_SUMMARY="$TARGET" ARTIFACTS_FOR_SUMMARY="$ARTIFACTS" PLATFORM_FOR_SUMMARY="$PLATFORM" MODE_FOR_SUMMARY="$PREFLIGHT_MODE" LAUNCH_STATUS="$launch_status" VERIFY_STATUS="$verify_status" node <<'NODE'
const fs = require('fs');
const path = require('path');
const artifacts = process.env.ARTIFACTS_FOR_SUMMARY;
const launchSummary = path.join(artifacts, 'launch', 'summary.json');
const verifySummary = path.join(artifacts, 'verify', 'summary.json');
const launchStatus = Number(process.env.LAUNCH_STATUS);
const verifyStatus = Number(process.env.VERIFY_STATUS);
fs.writeFileSync(path.join(artifacts, 'summary.json'), `${JSON.stringify({
  adapter: 'mobile',
  action: 'live',
  status: launchStatus === 0 && verifyStatus === 0 ? 'pass' : 'fail',
  target: process.env.TARGET_FOR_SUMMARY,
  platform: process.env.PLATFORM_FOR_SUMMARY,
  preflightMode: process.env.MODE_FOR_SUMMARY,
  launch: { exitCode: launchStatus, summaryPath: fs.existsSync(launchSummary) ? launchSummary : null },
  verify: { exitCode: verifyStatus, summaryPath: fs.existsSync(verifySummary) ? verifySummary : null },
  easyCommand: `<skill-dir>/scripts/metamask-recipe live --platform ${process.env.PLATFORM_FOR_SUMMARY} --preflight-mode ${process.env.MODE_FOR_SUMMARY}`,
  note: 'Runs launch then live verify so a developer can validate app startup, runner-owned CDP bridge, screenshot capture, and tiny recipe control from one runner-owned command.',
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE

echo "Mobile live validation summary: $ARTIFACTS/summary.json"
[ "$launch_status" -eq 0 ] && [ "$verify_status" -eq 0 ]
