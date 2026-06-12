#!/usr/bin/env bash
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
. "$SCRIPT_DIR/path.sh"
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

resolve_wallet_fixture() {
  if [ -n "${RECIPE_WALLET_FIXTURE:-}" ]; then
    [ -f "$RECIPE_WALLET_FIXTURE" ] || { echo "[recipe-harness] RECIPE_WALLET_FIXTURE is not a file: $RECIPE_WALLET_FIXTURE" >&2; return 1; }
    printf '%s\n' "$RECIPE_WALLET_FIXTURE"
    return 0
  fi
  for candidate in \
    "$TARGET/$RUNTIME_DIR/wallet-fixture.json" \
    "$TARGET/temp/runtime/wallet-fixture.json" \
    "$TARGET/temp/.recipe-validation-${CDP_PORT}/wallet-fixture.json" \
    "$TARGET/temp/.agent-validation/wallet-fixture.json"
  do
    [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
}

if $LAUNCH_EXISTING_DIST && [ -z "$PREPARE_CMD" ]; then
  DIST_ABS="$TARGET/$DIST_DIR"
  RUNTIME_DIST_ABS="$ARTIFACTS/runtime-dist"
  PROFILE_ABS="${CHROME_USER_DATA_DIR:-$ARTIFACTS/chrome-profile}"
  WALLET_FIXTURE_ABS="$(resolve_wallet_fixture || true)"
  FIXTURE_STATE_ABS="$ARTIFACTS/fixture-state.json"
  FIXTURE_VALIDATION_ABS="$ARTIFACTS/logs/fixture-account-parity.json"
  node - "$ARTIFACTS/logs/fixture-source.json" "$WALLET_FIXTURE_ABS" <<'NODE'
const fs = require('fs');
const [out, fixture] = process.argv.slice(2);
fs.mkdirSync(require('path').dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify({
  status: fixture ? 'present' : 'missing',
  fixturePath: fixture || null,
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE
  mkdir -p "$PROFILE_ABS"
  quoted_dist="$(printf '%q' "$DIST_ABS")"
  quoted_runtime_dist="$(printf '%q' "$RUNTIME_DIST_ABS")"
  quoted_profile="$(printf '%q' "$PROFILE_ABS")"
  quoted_fixture_script="$(printf '%q' "$SCRIPT_DIR/wallet-fixture-state.cjs")"
  # Moved feature: prefer the repo orchestration home, else the installed co-located copy.
  chrome_launcher="$SCRIPT_DIR/../../orchestration/extension/launch-chrome-detached.cjs"
  [ -f "$chrome_launcher" ] || chrome_launcher="$SCRIPT_DIR/launch-chrome-detached.cjs"
  quoted_chrome_launcher="$(printf '%q' "$chrome_launcher")"
  quoted_fixture_state="$(printf '%q' "$FIXTURE_STATE_ABS")"
  quoted_fixture_validation="$(printf '%q' "$FIXTURE_VALIDATION_ABS")"
  quoted_extension_id_file="$(printf '%q' "$TARGET/$RUNTIME_DIR/extension.id")"
  quoted_target="$(printf '%q' "$TARGET")"
  quoted_runner="$(printf '%q' "$RUNNER_BIN")"
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
    prepare_parts+=("mkdir -p "$RUNTIME_DIR"")
    # Explicit clean-build path: clear the target-scoped webpack cache before
    # starting the harness-owned watcher. Faster incremental refresh stays on
    # `mme-recipe refresh`; `--start-watch` is for proving a clean build works.
    prepare_parts+=("echo '[recipe-harness] clean build: clearing webpack cache + harness watcher'; rm -rf node_modules/.cache/webpack; if [ -f ${RUNTIME_DIR}/recipe-harness-webpack.pid ]; then kill \"\$(cat ${RUNTIME_DIR}/recipe-harness-webpack.pid 2>/dev/null)\" >/dev/null 2>&1 || true; rm -f ${RUNTIME_DIR}/recipe-harness-webpack.pid; fi")
    # Do not start a second writer for dist/chrome. Slot-owned watches use
    # webpack.pid; harness-owned watches use recipe-harness-webpack.pid.
    prepare_parts+=("slot_watch_pid_file=${RUNTIME_DIR}/webpack.pid; if [ -f \"\$slot_watch_pid_file\" ]; then slot_watch_pid=\$(cat \"\$slot_watch_pid_file\" 2>/dev/null || true); else slot_watch_pid=; fi; if [ -n \"\$slot_watch_pid\" ] && kill -0 \"\$slot_watch_pid\" >/dev/null 2>&1; then echo \"[recipe-harness] Refusing to start yarn start: slot webpack watch already owns this checkout (pid \$slot_watch_pid). Stop it first or reuse the live browser.\" >&2; exit 1; fi; [ -z \"\$slot_watch_pid\" ] || rm -f \"\$slot_watch_pid_file\"")
    # Scope watcher reuse to this checkout. A machine-global pgrep can match an
    # unrelated repo and leave this target validating stale dist/chrome output.
    prepare_parts+=("watch_pid_file=${RUNTIME_DIR}/recipe-harness-webpack.pid; watch_log=${RUNTIME_DIR}/recipe-harness-webpack.log; if [ -f \"\$watch_pid_file\" ]; then watch_pid=\$(cat \"\$watch_pid_file\" 2>/dev/null || true); else watch_pid=; fi; if [ -z \"\$watch_pid\" ] || ! kill -0 \"\$watch_pid\" >/dev/null 2>&1; then rm -f \"\$watch_pid_file\"; : > \"\$watch_log\"; echo '[recipe-harness] Starting yarn start; streaming ${RUNTIME_DIR}/recipe-harness-webpack.log'; nohup env -u BUNDLED_DEBUGPY_PATH yarn start > \"\$watch_log\" 2>&1 & echo \$! > \"\$watch_pid_file\"; else echo \"[recipe-harness] Reusing existing yarn start pid \$watch_pid; streaming ${RUNTIME_DIR}/recipe-harness-webpack.log\"; fi")
    prepare_parts+=("tail -n +1 -F ${RUNTIME_DIR}/recipe-harness-webpack.log & watch_tail_pid=\$!")
    prepare_parts+=("compiled=false; for i in {1..240}; do if grep -Eq 'Module build failed|^ERROR in |compiled with [1-9][0-9]* error' ${RUNTIME_DIR}/recipe-harness-webpack.log 2>/dev/null; then kill \"\$watch_tail_pid\" >/dev/null 2>&1 || true; wait \"\$watch_tail_pid\" 2>/dev/null || true; echo '[recipe-harness] webpack BUILD FAILED (not waiting for timeout):' >&2; grep -E -A3 'Module build failed|^ERROR in ' ${RUNTIME_DIR}/recipe-harness-webpack.log 2>/dev/null | tail -30 >&2; echo '[recipe-harness] If it is a stale-cache ENOENT it should have been auto-cleared; a recurring error here is a real source/build issue to fix.' >&2; exit 1; fi; if grep -Eq 'compiled successfully|compiled with [0-9]+ warning|MetaMask .* compiled|Bundle end: service worker|Bundle end:.*app-init' ${RUNTIME_DIR}/recipe-harness-webpack.log 2>/dev/null; then compiled=true; break; fi; sleep 2; done; kill \"\$watch_tail_pid\" >/dev/null 2>&1 || true; wait \"\$watch_tail_pid\" 2>/dev/null || true; if [ \"\$compiled\" != true ]; then echo 'Timed out waiting for target-scoped yarn start compilation marker' >&2; tail -80 ${RUNTIME_DIR}/recipe-harness-webpack.log >&2 || true; exit 1; fi; echo '[recipe-harness] yarn start compiled successfully'; ${quoted_runner} runtime-decision --adapter extension --target . --record --json >/dev/null 2>&1 || true; echo '[recipe-harness] recorded deps/cache baseline (runtime-decision --record)'")
  fi
  prepare_parts+=("for i in {1..180}; do [ -f ${quoted_dist}/manifest.json ] && break; sleep 2; done")
  prepare_parts+=("test -f ${quoted_dist}/manifest.json || exit 1")
  prepare_parts+=("rm -rf ${quoted_runtime_dist} && mkdir -p ${quoted_runtime_dist} && rsync -a --delete --exclude _metadata ${quoted_dist}/ ${quoted_runtime_dist}/ || exit 1")
  # Freshness guard: the loaded runtime-dist must match dist/chrome's git id. A
  # mismatch means the rsync caught a mid-rebuild dist; abort rather than load
  # an inconsistent bundle (the "Element type is invalid: undefined" class of crash).
  prepare_parts+=("node -e 'const fs=require(\"fs\");const id=p=>{try{return (JSON.parse(fs.readFileSync(p,\"utf8\")).description||\"\").match(/from git id: *([0-9a-f]+)/i)?.[1]||\"\"}catch{return\"\"}};const [distManifest,runtimeManifest]=process.argv.slice(-2);const d=id(distManifest),r=id(runtimeManifest);if(d&&d!==r){console.error(\"runtime-dist git id \"+r+\" != dist \"+d+\" (mid-rebuild?); aborting\");process.exit(1)}' ${quoted_dist}/manifest.json ${quoted_runtime_dist}/manifest.json")
  if [ -n "$WALLET_FIXTURE_ABS" ]; then
    quoted_wallet_fixture="$(printf '%q' "$WALLET_FIXTURE_ABS")"
    prepare_parts+=("node ${quoted_fixture_script} generate --target ${quoted_target} --fixture ${quoted_wallet_fixture} --out ${quoted_fixture_state}")
    prepare_parts+=("node ${quoted_fixture_script} prefill-profile --target ${quoted_target} --state ${quoted_fixture_state} --profile ${quoted_profile} --extension-dir ${quoted_runtime_dist} --extension-id-file ${quoted_extension_id_file}")
  fi
  chrome_launch_cmd="node ${quoted_chrome_launcher} --chrome-bin ${quoted_chrome} --profile ${quoted_profile} --cdp-port ${CDP_PORT} --extension-dir ${quoted_runtime_dist} --chrome-log ${quoted_chrome_log} --chrome-pid ${quoted_chrome_pid}"
  prepare_parts+=("$chrome_launch_cmd")
  prepare_parts+=("for i in {1..60}; do curl -fsS --max-time 1 http://127.0.0.1:${CDP_PORT}/json/version >/dev/null 2>&1 && break; sleep 1; done; curl -fsS --max-time 1 http://127.0.0.1:${CDP_PORT}/json/version >/dev/null")
  if [ -n "$WALLET_FIXTURE_ABS" ]; then
    prepare_parts+=("node ${quoted_fixture_script} seed-cdp --target ${quoted_target} --fixture ${quoted_wallet_fixture} --state ${quoted_fixture_state} --cdp-port ${CDP_PORT} --extension-dir ${quoted_runtime_dist} --extension-id-file ${quoted_extension_id_file} --out ${quoted_fixture_validation}")
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
  "$SCRIPT_DIR/verify.sh" --target "$TARGET" --out "$OUT" --cdp-port "$CDP_PORT" --artifacts-dir "$ARTIFACTS/verify"
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
