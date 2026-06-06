#!/bin/bash
# refresh-build.sh — one-shot rebuild for a frozen extension slot
#
# Usage:
#   bash refresh-build.sh --repo /path/to/metamask-extension [--watcher-port 9013]
#
# Context:
#   In sidepanel mode, preflight.sh defaults to `watch=off` and kills the
#   webpack watcher once dist/chrome is stable. That guarantees side-panel
#   close/reopen never races a rebuild, but means code edits do not reach
#   the browser until an explicit rebuild.
#
#   This script runs `yarn start` once, waits until the critical extension
#   entry points are back on disk, then kills the watcher again — leaving
#   dist/chrome fresh AND frozen. After it returns:
#     - Close any open extension pages (sidepanel / popup / fullscreen)
#     - Reopen them to pick up the new build
#   e.g. `bash sidepanel-toggle.sh cycle --cdp-port $CDP_PORT`
#
# Exit codes:
#   0 — success
#   1 — bad args / repo missing
#   2 — rebuild did not complete within the timeout

set -euo pipefail

REPO=""
WATCHER_PORT=""
TIMEOUT_S="180"
CLEAN_TIMEOUT_S=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --watcher-port) WATCHER_PORT="$2"; shift 2 ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --clean-timeout) CLEAN_TIMEOUT_S="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$REPO" ] || [ ! -f "$REPO/package.json" ]; then
  echo "FAIL: --repo must point to a metamask-extension checkout" >&2
  exit 1
fi

PORT_ARG=""
if [ -n "$WATCHER_PORT" ]; then
  PORT_ARG="PORT=${WATCHER_PORT}"
fi

cd "$REPO"

HTML_ENTRIES=()
while IFS= read -r entry; do
  [ -n "$entry" ] && HTML_ENTRIES+=("dist/chrome/$entry")
done < <(node <<'NODE'
const fs = require('fs');
const manifestPath = 'dist/chrome/manifest.json';
if (!fs.existsSync(manifestPath)) {
  console.log('home.html');
  console.log('scripts/app-init.js');
  console.log('popup-init.html');
  console.log('sidepanel.html');
  process.exit(0);
}
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const entries = new Set(['home.html']);
if (manifest.background?.service_worker) entries.add(manifest.background.service_worker);
for (const script of manifest.background?.scripts || []) entries.add(script);
const popup = manifest.action?.default_popup || manifest.browser_action?.default_popup || manifest.page_action?.default_popup;
if (popup) entries.add(popup);
if (manifest.side_panel?.default_path) entries.add(manifest.side_panel.default_path);
for (const entry of entries) console.log(entry);
NODE
)

ASDF_SHIMS="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
if [ -d "$ASDF_SHIMS" ]; then
  export PATH="$ASDF_SHIMS:$PATH"
fi
echo "[refresh] Using node $(node -v 2>/dev/null || echo 'not found')"
echo "[refresh] Starting yarn start (watcher-port=${WATCHER_PORT:-default})..."
LOG="$(mktemp -t refresh-build-XXXXXX.log)"
echo "[refresh] Log: $LOG"
env ${PORT_ARG} yarn start > "$LOG" 2>&1 &
BUILD_PID=$!
echo "[refresh] Build PID: $BUILD_PID"

cleanup() {
  if kill -0 "$BUILD_PID" 2>/dev/null; then
    kill "$BUILD_PID" 2>/dev/null || true
  fi
  # Also clear any child yarn/gulp workers holding the watcher port
  if [ -n "$WATCHER_PORT" ]; then
    lsof -i ":$WATCHER_PORT" -t 2>/dev/null | xargs kill 2>/dev/null || true
  fi
}
trap cleanup EXIT

# First wait for the clean pass (confirms this build, not a pre-existing stale
# dist, owns the next entry files we observe).
CLEAN_TIMEOUT_S="${CLEAN_TIMEOUT_S:-$TIMEOUT_S}"
echo "[refresh] Waiting for clean pass (timeout ${CLEAN_TIMEOUT_S}s)..."
for i in $(seq 1 "$CLEAN_TIMEOUT_S"); do
  if grep -q "Finished 'clean'" "$LOG" 2>/dev/null; then
    echo "[refresh] Clean pass reached (${i}s)"
    break
  fi
  if grep -q "webpack.Progress.*100%" "$LOG" 2>/dev/null; then
    echo "[refresh] Webpack reached 100% (${i}s)"
    break
  fi
  if ! kill -0 "$BUILD_PID" 2>/dev/null; then
    echo "FAIL: yarn start exited before clean pass" >&2
    tail -40 "$LOG" 2>/dev/null || true
    exit 2
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo "[refresh] still waiting for clean... (${i}s)"
    tail -5 "$LOG" 2>/dev/null | sed 's/^/[refresh:log] /' || true
  fi
  sleep 1
done
if ! grep -q "Finished 'clean'" "$LOG" 2>/dev/null && ! grep -q "webpack.Progress.*100%" "$LOG" 2>/dev/null; then
  echo "FAIL: build did not reach clean/100% within ${CLEAN_TIMEOUT_S}s" >&2
  tail -40 "$LOG" 2>/dev/null || true
  exit 2
fi

echo "[refresh] Waiting for entry points (timeout ${TIMEOUT_S}s): ${HTML_ENTRIES[*]}"
for i in $(seq 1 "$TIMEOUT_S"); do
  ready=true
  for entry in "${HTML_ENTRIES[@]}"; do
    if [ ! -f "$REPO/${entry}" ]; then
      ready=false
      break
    fi
  done
  $ready && break
  if [ $((i % 15)) -eq 0 ]; then
    echo "[refresh] still building entry points... (${i}s)"
    tail -5 "$LOG" 2>/dev/null | sed 's/^/[refresh:log] /' || true
  fi
  sleep 1
done

all_present=true
for entry in "${HTML_ENTRIES[@]}"; do
  if [ ! -f "$REPO/${entry}" ]; then
    all_present=false
    echo "[refresh] MISSING: ${entry}"
  fi
done

if ! $all_present; then
  echo "FAIL: rebuild did not restore all entry points within ${TIMEOUT_S}s" >&2
  tail -40 "$LOG" 2>/dev/null || true
  exit 2
fi

# Kill the watcher — leave dist fresh and frozen.
kill "$BUILD_PID" 2>/dev/null || true
wait "$BUILD_PID" 2>/dev/null || true
trap - EXIT

echo "[refresh] Build refreshed and frozen — run: recipe reopen"
echo "[refresh] Log kept at: $LOG"
