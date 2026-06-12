#!/usr/bin/env bash
# live.sh — extension launch-then-verify sequencer for one live slot run
# (formerly: scripts/extension/live.sh, including the prepare_parts
# mega-string now decomposed into start-watch.sh / snapshot-dist.sh /
# seed-fixture.sh)
#
# Purpose:
#   Builds the per-run prepare command from the named feature scripts
#   (watch, dist snapshot, fixture seed, detached chrome, CDP poll), then
#   runs launch.sh and verify.sh under a timestamped artifact dir.
#
# Inputs (flags / env):
#   --target <metamask-extension> (default $PWD)
#   --cdp-port <port> (required, numeric-validated)
#   --launch-existing-dist | --start-watch | --prepare-cmd <cmd>
#       (env RECIPE_HARNESS_EXTENSION_LAUNCH_CMD)
#   --dist-dir <rel> (default dist/chrome), --chrome-user-data-dir <dir>,
#   --out <recipes-dir>, --artifacts-dir <dir>
#   env RECIPE_HARNESS_CHROME_BIN (validated executable; else Playwright
#   chromium with approval-gated install messaging), RECIPE_WALLET_FIXTURE,
#   RECIPE_HARNESS_LIVE_KEEP (artifact pruning, default 5)
#
# Outputs:
#   <artifacts>/summary.json (adapter/action/status, launch/verify exit
#   codes + child summary paths, easyCommand), <artifacts>/{launch,verify},
#   <artifacts>/logs/fixture-source.json provenance.
#   Exit 0 — launch and verify both passed; 1 — either failed; 2 — bad args.
#
# Never touches: product source files; live artifact dirs newer than the
# pruning window; anything outside the target's harness dir.
set -euo pipefail

TARGET="$PWD"
CDP_PORT=""
ARTIFACTS=""
OUT=""
PREPARE_CMD="${RECIPE_HARNESS_EXTENSION_LAUNCH_CMD:-}"
LAUNCH_EXISTING_DIST=false
START_WATCH=false
DIST_DIR="dist/chrome"
CHROME_USER_DATA_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; TARGET="$2"; shift 2 ;;
    --out) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; OUT="$2"; shift 2 ;;
    --cdp-port) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; CDP_PORT="$2"; shift 2 ;;
    --artifacts-dir) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; ARTIFACTS="$2"; shift 2 ;;
    --prepare-cmd) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; PREPARE_CMD="$2"; shift 2 ;;
    --launch-existing-dist) LAUNCH_EXISTING_DIST=true; shift ;;
    --start-watch|--start-test-watch) START_WATCH=true; LAUNCH_EXISTING_DIST=true; shift ;;
    --dist-dir) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; DIST_DIR="$2"; shift 2 ;;
    --chrome-user-data-dir) [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; CHROME_USER_DATA_DIR="$2"; shift 2 ;;
    -h|--help) echo "Usage: live.sh [--target <metamask-extension>] [--out <recipes-dir>] --cdp-port <port> [--launch-existing-dist|--start-watch|--prepare-cmd <cmd>] [--dist-dir dist/chrome] [--artifacts-dir <dir>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$CDP_PORT" ] || { echo "Missing --cdp-port for Extension live validation" >&2; exit 2; }
# Reject a non-numeric port before it is interpolated into the Chrome launch
# command and the CDP HTTP probes.
case "$CDP_PORT" in
  *[!0-9]*) echo "Invalid --cdp-port (must be numeric): $CDP_PORT" >&2; exit 2 ;;
esac

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
# runner/extension in a repo checkout.
VERIFY_SH=""
for _v in "$SCRIPT_DIR/verify.sh" "$SCRIPT_DIR/../../runner/extension/verify.sh"; do
  [ -f "$_v" ] && { VERIFY_SH="$_v"; break; }
done
unset _v
if [ -z "$VERIFY_SH" ]; then
  echo "metamask-recipe: extension verify.sh not found next to $SCRIPT_DIR; reinstall the runner." >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
RUNTIME_DIR="$(recipe_runtime_dir)"
# Runner bin (installed wrapper → source runner). Used by the watch prepare path
# to defer the cache-clear DECISION to `runtime-decision` (single source) and to
# record the deps/cache baseline after a confirmed-good build.
RUNNER_BIN="$(harness_dir "$TARGET" extension)/runner/bin/metamask-recipe"
OUT="${OUT:-$(harness_root)/extension/runner/recipes}"
ARTIFACTS="${ARTIFACTS:-$(harness_dir "$TARGET" extension)/live/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$ARTIFACTS/logs"

# Prune stale live artifact dirs (configurable harness root, not a hardcoded path)
# so old runtime-dist snapshots can't be loaded and don't accumulate to GBs.
# Keep the most recent few; override count with RECIPE_HARNESS_LIVE_KEEP.
LIVE_ROOT="$(harness_dir "$TARGET" extension)/live"
LIVE_KEEP="${RECIPE_HARNESS_LIVE_KEEP:-5}"
# Must be a positive integer: a non-numeric value would break the arithmetic and a
# 0 would `tail -n +1` and delete every dir including this run's fresh $ARTIFACTS.
case "$LIVE_KEEP" in ''|*[!0-9]*) LIVE_KEEP=5 ;; esac
[ "$LIVE_KEEP" -ge 1 ] 2>/dev/null || LIVE_KEEP=5
if [ -d "$LIVE_ROOT" ]; then
  # `|| true`: an empty live/ (no child dirs) makes ls exit non-zero, which would
  # abort the script under `set -euo pipefail`. Pruning is best-effort.
  ls -1dt "$LIVE_ROOT"/*/ 2>/dev/null | tail -n "+$((LIVE_KEEP + 1))" | while IFS= read -r _old; do rm -rf "$_old"; done || true
fi

if $LAUNCH_EXISTING_DIST && [ -z "$PREPARE_CMD" ]; then
  DIST_ABS="$TARGET/$DIST_DIR"
  RUNTIME_DIST_ABS="$ARTIFACTS/runtime-dist"
  PROFILE_ABS="${CHROME_USER_DATA_DIR:-$ARTIFACTS/chrome-profile}"
  FIXTURE_STATE_ABS="$ARTIFACTS/fixture-state.json"
  FIXTURE_VALIDATION_ABS="$ARTIFACTS/logs/fixture-account-parity.json"
  # Wallet fixture resolution chain + provenance live in seed-fixture.sh.
  WALLET_FIXTURE_ABS="$(bash "$SCRIPT_DIR/seed-fixture.sh" resolve --target "$TARGET" --cdp-port "$CDP_PORT" --source-out "$ARTIFACTS/logs/fixture-source.json" || true)"
  if [ ! -f "$ARTIFACTS/logs/fixture-source.json" ]; then
    # resolve failed before writing provenance (invalid RECIPE_WALLET_FIXTURE);
    # keep the documented missing-provenance artifact.
    node - "$ARTIFACTS/logs/fixture-source.json" "" <<'NODE'
const fs = require('fs');
const [out, fixture] = process.argv.slice(2);
fs.mkdirSync(require('path').dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify({
  status: fixture ? 'present' : 'missing',
  fixturePath: fixture || null,
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE
  fi
  mkdir -p "$PROFILE_ABS"
  quoted_dist="$(printf '%q' "$DIST_ABS")"
  quoted_runtime_dist="$(printf '%q' "$RUNTIME_DIST_ABS")"
  quoted_profile="$(printf '%q' "$PROFILE_ABS")"
  quoted_seed_fixture="$(printf '%q' "$SCRIPT_DIR/seed-fixture.sh")"
  quoted_start_watch="$(printf '%q' "$SCRIPT_DIR/start-watch.sh")"
  quoted_snapshot_dist="$(printf '%q' "$SCRIPT_DIR/snapshot-dist.sh")"
  quoted_chrome_launcher="$(printf '%q' "$SCRIPT_DIR/launch-browser.cjs")"
  quoted_fixture_state="$(printf '%q' "$FIXTURE_STATE_ABS")"
  quoted_fixture_validation="$(printf '%q' "$FIXTURE_VALIDATION_ABS")"
  quoted_extension_id_file="$(printf '%q' "$TARGET/$RUNTIME_DIR/extension.id")"
  quoted_target="$(printf '%q' "$TARGET")"
  quoted_runner="$(printf '%q' "$RUNNER_BIN")"
  quoted_runtime_dir="$(printf '%q' "$RUNTIME_DIR")"
  if [ -n "${RECIPE_HARNESS_CHROME_BIN:-}" ]; then
    CHROME_BIN="$RECIPE_HARNESS_CHROME_BIN"
    if [ ! -f "$CHROME_BIN" ] || [ ! -x "$CHROME_BIN" ]; then
      echo "[recipe-harness] RECIPE_HARNESS_CHROME_BIN is not an executable file: $CHROME_BIN" >&2
      exit 1
    fi
  else
    CHROME_BIN="$(cd "$TARGET" && node <<'NODE' || true
const fs = require('fs');

let chromium = null;
function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}
for (const pkg of ['@playwright/test', 'playwright']) {
  try {
    chromium = require(pkg).chromium;
    if (chromium) break;
  } catch (_error) {
    // Optional Playwright package unavailable; try the next package name.
  }
}
if (!chromium) {
  console.error('[recipe-harness] Playwright is not available from this checkout; install dependencies first, or set RECIPE_HARNESS_CHROME_BIN to an explicitly approved browser.');
  process.exit(1);
}

let executable = '';
try {
  executable = chromium.executablePath();
} catch (error) {
  const message = error && error.message ? error.message : String(error);
  console.error(`[recipe-harness] Could not resolve Playwright Chromium executable: ${message}. Manual approval required before installing the Playwright Chromium browser cache (no package.json changes); ask the user before running yarn exec playwright install chromium.`);
  process.exit(1);
}
if (!fs.existsSync(executable)) {
  console.error(`[recipe-harness] Playwright Chromium is not installed at ${executable}. Manual approval required before installing the Playwright Chromium browser cache (no package.json changes). Ask the user for approval; if they agree, run: cd ${shellQuote(process.cwd())} && yarn exec playwright install chromium`);
  console.error('[recipe-harness] To use a browser that is already installed, set RECIPE_HARNESS_CHROME_BIN=/path/to/chrome explicitly.');
  process.exit(1);
}

process.stdout.write(executable);
NODE
)"
    if [ -z "$CHROME_BIN" ]; then
      echo "[recipe-harness] No approved Chromium binary selected; stopping before live Extension launch." >&2
      exit 1
    fi
  fi
  quoted_chrome="$(printf '%q' "$CHROME_BIN")"
  quoted_chrome_log="$(printf '%q' "$ARTIFACTS/logs/chrome.log")"
  quoted_chrome_pid="$(printf '%q' "$ARTIFACTS/logs/chrome.pid")"
  prepare_parts=()
  if $START_WATCH; then
    prepare_parts+=("bash ${quoted_start_watch} --runtime-dir ${quoted_runtime_dir} --runner-bin ${quoted_runner}")
  fi
  prepare_parts+=("bash ${quoted_snapshot_dist} --dist ${quoted_dist} --runtime-dist ${quoted_runtime_dist}")
  if [ -n "$WALLET_FIXTURE_ABS" ]; then
    quoted_wallet_fixture="$(printf '%q' "$WALLET_FIXTURE_ABS")"
    prepare_parts+=("bash ${quoted_seed_fixture} prefill --target ${quoted_target} --fixture ${quoted_wallet_fixture} --state ${quoted_fixture_state} --profile ${quoted_profile} --extension-dir ${quoted_runtime_dist} --extension-id-file ${quoted_extension_id_file}")
  fi
  chrome_launch_cmd="node ${quoted_chrome_launcher} --chrome-bin ${quoted_chrome} --profile ${quoted_profile} --cdp-port ${CDP_PORT} --extension-dir ${quoted_runtime_dist} --chrome-log ${quoted_chrome_log} --chrome-pid ${quoted_chrome_pid}"
  prepare_parts+=("$chrome_launch_cmd")
  prepare_parts+=("for i in {1..60}; do curl -fsS --max-time 1 http://127.0.0.1:${CDP_PORT}/json/version >/dev/null 2>&1 && break; sleep 1; done; curl -fsS --max-time 1 http://127.0.0.1:${CDP_PORT}/json/version >/dev/null")
  if [ -n "$WALLET_FIXTURE_ABS" ]; then
    prepare_parts+=("bash ${quoted_seed_fixture} seed-cdp --target ${quoted_target} --fixture ${quoted_wallet_fixture} --state ${quoted_fixture_state} --cdp-port ${CDP_PORT} --extension-dir ${quoted_runtime_dist} --extension-id-file ${quoted_extension_id_file} --out ${quoted_fixture_validation}")
  fi
  PREPARE_CMD="$(IFS='; '; printf '%s' "${prepare_parts[*]}")"
fi

echo "Extension live validation command:"
display_args=(metamask-recipe runtime-launch --adapter extension --target "$TARGET" --cdp-port "$CDP_PORT")
$LAUNCH_EXISTING_DIST && display_args+=(--launch-existing-dist)
$START_WATCH && display_args+=(--start-watch)
printf '  '
printf '%q ' "${display_args[@]}"
printf '\n'
echo "Launch artifacts: $ARTIFACTS/launch"
echo "Verify artifacts: $ARTIFACTS/verify"

launch_args=(--target "$TARGET" --cdp-port "$CDP_PORT" --artifacts-dir "$ARTIFACTS/launch")
[ -n "$PREPARE_CMD" ] && launch_args+=(--prepare-cmd "$PREPARE_CMD")

set +e
"$SCRIPT_DIR/launch.sh" "${launch_args[@]}"
launch_status=$?
set -e

verify_status=1
if [ "$launch_status" -eq 0 ]; then
  set +e
  "$VERIFY_SH" --target "$TARGET" --out "$OUT" --cdp-port "$CDP_PORT" --artifacts-dir "$ARTIFACTS/verify"
  verify_status=$?
  set -e
else
  echo "Skipping Extension live verify because launch failed; see $ARTIFACTS/launch/summary.json" >&2
fi

TARGET_FOR_SUMMARY="$TARGET" ARTIFACTS_FOR_SUMMARY="$ARTIFACTS" CDP_PORT_FOR_SUMMARY="$CDP_PORT" LAUNCH_STATUS="$launch_status" VERIFY_STATUS="$verify_status" LAUNCH_EXISTING_DIST="$LAUNCH_EXISTING_DIST" START_WATCH="$START_WATCH" node <<'NODE'
const fs = require('fs');
const path = require('path');
const artifacts = process.env.ARTIFACTS_FOR_SUMMARY;
const launchSummary = path.join(artifacts, 'launch', 'summary.json');
const verifySummary = path.join(artifacts, 'verify', 'summary.json');
const launchStatus = Number(process.env.LAUNCH_STATUS);
const verifyStatus = Number(process.env.VERIFY_STATUS);
fs.writeFileSync(path.join(artifacts, 'summary.json'), `${JSON.stringify({
  adapter: 'extension',
  action: 'live',
  status: launchStatus === 0 && verifyStatus === 0 ? 'pass' : 'fail',
  target: process.env.TARGET_FOR_SUMMARY,
  cdpPort: process.env.CDP_PORT_FOR_SUMMARY,
  launchExistingDist: process.env.LAUNCH_EXISTING_DIST === 'true',
  startWatch: process.env.START_WATCH === 'true',
  launch: { exitCode: launchStatus, summaryPath: fs.existsSync(launchSummary) ? launchSummary : null },
  verify: { exitCode: verifyStatus, summaryPath: fs.existsSync(verifySummary) ? verifySummary : null },
  easyCommand: `metamask-recipe runtime-launch --adapter extension --target <repo> --cdp-port ${process.env.CDP_PORT_FOR_SUMMARY}`,
  note: 'Runs launch then live verify so a developer can validate browser startup, CDP readiness, recipe bridge, screenshots/fallback classification, and sample recipes from one runner-owned command.',
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE

echo "Extension live validation summary: $ARTIFACTS/summary.json"
[ "$launch_status" -eq 0 ] && [ "$verify_status" -eq 0 ]
