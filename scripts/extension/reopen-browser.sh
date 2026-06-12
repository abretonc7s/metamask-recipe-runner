#!/bin/bash
# reopen-browser.sh — Quick-reopen Playwright Chromium for extension slots.
# Project-specific (MetaMask Extension). No host framework dependency.
#
# Usage (from worker template — all vars are template-expanded):
#   bash <project>/setup/reopen-browser.sh \
#     --slot-id macwork-metamask-extension-5 \
#     --repo /Users/deeeed/dev/metamask/metamask-extension-5 \
#     --cdp-port 6665 \
#     --runtime-dir <runtime-dir>
#
# Requires: webpack watch running, valid build in dist/chrome.
set -euo pipefail

# --- Parse args ---
SLOT_ID=""
REPO=""
CDP_PORT=""
RUNTIME_DIR=""
WATCHER_PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slot-id)      SLOT_ID="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --cdp-port)     CDP_PORT="$2"; shift 2 ;;
    --runtime-dir)  RUNTIME_DIR="$2"; shift 2 ;;
    --watcher-port) WATCHER_PORT="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Auto-detect from script location or CWD ---
# Script lives at <repo>/<runtime_dir>/reopen-browser.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
for _hp in "$SCRIPT_DIR/lib/harness-path.sh" "$SCRIPT_DIR/../../orchestration/lib/harness-path.sh" "$SCRIPT_DIR/../lib/harness-path.sh" "$SCRIPT_DIR/../../../scripts/lib/harness-path.sh"; do
  [ -f "$_hp" ] && { . "$_hp"; break; }
done
unset _hp
if ! command -v harness_root >/dev/null 2>&1; then
  echo "reopen-browser: shared lib scripts/lib/harness-path.sh missing; reinstall the harness." >&2
  exit 1
fi
if [[ -z "$RUNTIME_DIR" ]]; then
  # Infer runtime_dir as relative path from repo root
  # Script is at <repo>/<runtime-dir>/reopen-browser.sh, so runtime_dir is inferred from that relative path
  if [[ -f "$SCRIPT_DIR/browser.pid" || -f "$SCRIPT_DIR/webpack.pid" || -f "$SCRIPT_DIR/wallet-fixture.json" ]]; then
    AGENT_DIR_ABS="$SCRIPT_DIR"
  elif [[ -f "$PWD/browser.pid" || -f "$PWD/webpack.pid" ]]; then
    AGENT_DIR_ABS="$PWD"
  fi
  if [[ -n "${AGENT_DIR_ABS:-}" ]]; then
    # Walk up to find repo root (has package.json + dist/chrome)
    d="$AGENT_DIR_ABS"
    while [[ "$d" != "/" ]]; do
      if [[ -f "$d/package.json" && -d "$d/dist/chrome" ]]; then
        REPO="${REPO:-$d}"
        # runtime_dir is the relative path from repo to agent dir
        RUNTIME_DIR="${AGENT_DIR_ABS#$d/}"
        break
      fi
      d="$(dirname "$d")"
    done
  fi
fi

[[ -z "$REPO" ]] && { echo "Error: cannot detect repo — pass --repo" >&2; exit 1; }
RUNTIME_DIR="${RUNTIME_DIR:-$(recipe_runtime_dir)}"

# Auto-detect slot-id from directory name (e.g. metamask-extension-6 → macwork-metamask-extension-6)
if [[ -z "$SLOT_ID" ]]; then
  REPO_BASENAME="$(basename "$REPO")"
  HOSTNAME_SHORT="$(hostname -s)"
  SLOT_ID="${HOSTNAME_SHORT}-${REPO_BASENAME}"
fi

# Auto-detect CDP port from existing browser launch args or agent files
if [[ -z "$CDP_PORT" && -f "${REPO}/${RUNTIME_DIR}/browser.pid" ]]; then
  BPID=$(cat "${REPO}/${RUNTIME_DIR}/browser.pid" 2>/dev/null)
  if [[ -n "$BPID" ]]; then
    CDP_PORT=$(ps -p "$BPID" -o args= 2>/dev/null | grep -oE 'remote-debugging-port=[0-9]+' | cut -d= -f2 || true)
  fi
fi

EXTENSION="${REPO}/dist/chrome"
AGENT_DIR="${REPO}/${RUNTIME_DIR}"
PROFILE="${CHROME_USER_DATA_DIR:-${AGENT_DIR}/chrome-profile-recipe}"
if [ ! -f "${PROFILE}/Default/Preferences" ] && [ -f "${AGENT_DIR}/chrome-profile-pw/Default/Preferences" ]; then
  PROFILE="${AGENT_DIR}/chrome-profile-pw"
fi
WALLET_FIXTURE="${AGENT_DIR}/wallet-fixture.json"
# Extension id resolution is delegated to the installed recipe-runner — the
# single source of truth (deterministic id from the loaded dist's manifest key).
# Honor the configured recipe harness root.
HARNESS_ROOT="$(harness_root)"
RUNNER_BIN="${REPO}/${HARNESS_ROOT}/extension/runner/bin/metamask-recipe"

# --- Preflight checks ---
if [ ! -f "${EXTENSION}/manifest.json" ]; then
  echo "FAIL: No build at ${EXTENSION}/manifest.json"
  echo "  Run preflight or: cd ${REPO} && PORT=${WATCHER_PORT:-9011} yarn start"
  exit 1
fi

if [ ! -f "${WALLET_FIXTURE}" ]; then
  echo "FAIL: wallet fixture missing at ${WALLET_FIXTURE}"
  exit 1
fi

if [ ! -f "${PROFILE}/Default/Preferences" ]; then
  echo "FAIL: existing browser profile not found at ${PROFILE}"
  echo "  Reopen only reuses an already-prepared profile. Run: metamask-recipe runtime-launch --adapter extension --target ${REPO} --cdp-port ${CDP_PORT} --chrome-user-data-dir ${PROFILE} --json"
  exit 1
fi

WEBPACK_PID=$(cat "${AGENT_DIR}/webpack.pid" 2>/dev/null || true)
if [ -z "$WEBPACK_PID" ] || ! kill -0 "$WEBPACK_PID" 2>/dev/null; then
  echo "WARN: webpack not running (no live PID in ${AGENT_DIR}/webpack.pid)"
  echo "  Hot reload won't work. Start it: cd ${REPO} && PORT=${WATCHER_PORT:-9011} yarn start"
  WEBPACK_PID=""
fi

wait_for_browser_exit() {
  local pid="$1"
  if [ -z "$pid" ]; then
    return 0
  fi
  for _ in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "[cleanup] Browser PID ${pid} did not exit after SIGTERM; forcing kill"
    kill -KILL "$pid" 2>/dev/null || true
  fi
  for _ in $(seq 1 10); do
    if [ ! -e "${PROFILE}/SingletonLock" ] && [ ! -e "${PROFILE}/SingletonSocket" ] && [ ! -e "${PROFILE}/SingletonCookie" ]; then
      return 0
    fi
    sleep 1
  done
  rm -f "${PROFILE}/SingletonLock" "${PROFILE}/SingletonSocket" "${PROFILE}/SingletonCookie" 2>/dev/null || true
}

cleanup_stale_profile_locks() {
  local lock_path="${PROFILE}/SingletonLock"
  if [ ! -L "$lock_path" ]; then
    return 0
  fi
  local target pid
  target=$(readlink "$lock_path" 2>/dev/null || true)
  pid=$(printf '%s' "$target" | sed -E 's/.*-([0-9]+)$/\1/' )
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "[cleanup] Profile lock owned by live Chromium PID ${pid}"
    return 0
  fi
  echo "[cleanup] Removing stale Chromium profile lock (${target:-unknown})"
  rm -f "${PROFILE}/SingletonLock" "${PROFILE}/SingletonSocket" "${PROFILE}/SingletonCookie" 2>/dev/null || true
}

kill_profile_processes() {
  local pids
  pids=$(pgrep -f "${PROFILE}" 2>/dev/null || true)
  if [ -z "$pids" ]; then
    return 0
  fi
  echo "[cleanup] Killing lingering profile processes: $(echo "$pids" | tr '\n' ' ')"
  echo "$pids" | xargs kill -TERM 2>/dev/null || true
  sleep 2
  pids=$(pgrep -f "${PROFILE}" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill -KILL 2>/dev/null || true
  fi
}

# --- Kill existing browser (by PID only — don't touch other slots) ---
PREV_PID=$(cat "${AGENT_DIR}/browser.pid" 2>/dev/null || true)
if [ -n "$PREV_PID" ] && kill -0 "$PREV_PID" 2>/dev/null; then
  echo "[cleanup] Killing browser PID ${PREV_PID}"
  kill "$PREV_PID" 2>/dev/null || true
  wait_for_browser_exit "$PREV_PID"
fi
kill_profile_processes
cleanup_stale_profile_locks
rm -f "${AGENT_DIR}/browser.pid" "${AGENT_DIR}/extension.id" "${AGENT_DIR}/launcher.pid"
echo "[cleanup] Reusing profile ${PROFILE}"

# Clear crash recovery state + re-enable any previously-disabled extensions
# (profile Preferences persists extensions.settings.<id>.state=0 after unsafe
# shutdowns; --load-extension re-advertises the path but does not flip it back,
# leaving MV3 service workers inert).
if [ -f "${PROFILE}/Default/Preferences" ]; then
  python3 -c "
import json
pf = '${PROFILE}/Default/Preferences'
prefs = json.load(open(pf))
prefs['profile'] = prefs.get('profile', {})
prefs['profile']['exit_type'] = 'Normal'
prefs['profile']['exited_cleanly'] = True
ext_settings = prefs.get('extensions', {}).get('settings', {})
for ext_id, ext_prefs in ext_settings.items():
    if isinstance(ext_prefs, dict) and ext_prefs.get('state') != 1:
        ext_prefs['state'] = 1
        ext_prefs.pop('disable_reasons', None)
json.dump(prefs, open(pf, 'w'))
" 2>/dev/null && echo "[cleanup] Cleared crash recovery state + re-enabled extensions"
fi

# Readiness gate: wait until webpack emits a loadable background entry before
# freezing dist/chrome. The entry differs by manifest version — MV3 emits
# service-worker.js, MV2 emits scripts/app-init.js — so accept EITHER (gated on
# manifest.json). Hardcoding the MV2 app-init.js path made this hang the full
# timeout and FAIL on MV3 builds, which is the #1 reason agents can't launch the
# browser and then burn tokens debugging. Deterministic and MV-agnostic.
build_entry_ready() {
  [ -s "${EXTENSION}/manifest.json" ] || return 1
  [ -s "${EXTENSION}/service-worker.js" ] || [ -s "${EXTENSION}/scripts/app-init.js" ]
}
for _ in $(seq 1 60); do
  build_entry_ready && break
  sleep 1
done

if ! build_entry_ready; then
  echo "FAIL: no loadable background entry (service-worker.js [MV3] or scripts/app-init.js [MV2]) under ${EXTENSION} after waiting for webpack output"
  exit 1
fi

resume_webpack() {
  if [ -n "${WEBPACK_PID:-}" ]; then
    kill -CONT -"$WEBPACK_PID" 2>/dev/null || kill -CONT "$WEBPACK_PID" 2>/dev/null || true
  fi
}

# Pause webpack process group so dist/chrome is stable during launch
if [ -n "$WEBPACK_PID" ]; then
  kill -STOP -"$WEBPACK_PID" 2>/dev/null || kill -STOP "$WEBPACK_PID" 2>/dev/null || true
  echo "[webpack] Paused (PID ${WEBPACK_PID})"
  trap resume_webpack EXIT
fi

echo "[reopen] ${SLOT_ID} — CDP:${CDP_PORT:-off}"

cd "${REPO}"

trap - EXIT
exec node -e "
const path = require('path');
const fs = require('fs');
const http = require('http');
const { execSync, execFileSync } = require('child_process');
let chromium; try { chromium = require('@playwright/test').chromium; } catch { chromium = require('playwright').chromium; }

const SLOT_ID = '${SLOT_ID}';
const AGENT_DIR = '${AGENT_DIR}';
const EXTENSION = '${EXTENSION}';
const REPO = '${REPO}';
const RUNNER_BIN = '${RUNNER_BIN}';
const PROFILE = '${PROFILE}';
const CDP_PORT = '${CDP_PORT}' || null;
const WEBPACK_PID = '${WEBPACK_PID}' || null;
const walletFixture = JSON.parse(fs.readFileSync('${WALLET_FIXTURE}', 'utf8'));
const PASSWORD = walletFixture.password;

if (!PASSWORD) {
  throw new Error('wallet-fixture.json is missing password');
}

const resumeWebpack = () => {
  if (WEBPACK_PID) { try { process.kill(-Number(WEBPACK_PID), 'SIGCONT'); } catch { try { process.kill(Number(WEBPACK_PID), 'SIGCONT'); } catch {} } }
};

(async () => {
  const args = [
    '--user-data-dir=' + PROFILE,
    '--disable-extensions-except=' + EXTENSION,
    '--load-extension=' + EXTENSION,
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding',
    '--no-first-run',
    '--no-default-browser-check',
    '--window-size=420,800',
  ];
  if (CDP_PORT) args.push('--remote-debugging-port=' + CDP_PORT);

  const chromiumApp = path.dirname(path.dirname(path.dirname(chromium.executablePath())));
  execFileSync('open', ['-n', '-a', chromiumApp, '--args', ...args], { stdio: 'ignore' });
  for (let i = 0; i < 60; i++) {
    try {
      const version = await new Promise((resolve, reject) => {
        const req = http.get('http://127.0.0.1:' + CDP_PORT + '/json/version', (res) => {
          let body = '';
          res.on('data', (chunk) => { body += chunk; });
          res.on('end', () => resolve(body));
        });
        req.on('error', reject);
      });
      if (version) break;
    } catch {}
    await new Promise(r => setTimeout(r, 1000));
  }
  const browser = await chromium.connectOverCDP('http://127.0.0.1:' + CDP_PORT);
  const ctx = browser.contexts()[0];
  try {
    const browserPid = execSync('lsof -ti tcp:' + CDP_PORT + ' -sTCP:LISTEN | head -1', { timeout: 2000 }).toString().trim();
    if (browserPid) {
      fs.writeFileSync(path.join(AGENT_DIR, 'browser.pid'), browserPid);
      fs.writeFileSync(path.join(AGENT_DIR, 'chromium.pid'), browserPid);
      console.log('[reopen] Chromium PID ' + browserPid);
    }
  } catch {}

  // Detect extension ID via the recipe-runner — the single source of truth.
  // Deterministic id from the loaded dist's manifest key; replaces a fragile
  // serviceWorkers()[0] scan that grabbed Chrome *component* extensions and
  // pointed home.html at the wrong (non-MetaMask) extension.
  let extId = '';
  try {
    extId = execFileSync(RUNNER_BIN, ['resolve-extension', '--adapter', 'extension', '--target', REPO], { encoding: 'utf8' }).trim();
  } catch (err) {
    resumeWebpack();
    console.error('[FAIL] runner resolve-extension failed: ' + (err && err.message ? err.message : String(err)));
    process.exit(1);
  }
  if (!/^[a-p]{32}$/.test(extId)) { resumeWebpack(); console.error('[FAIL] runner returned invalid extension id: ' + JSON.stringify(extId)); process.exit(1); }
  console.log('[reopen] Extension: ' + extId + ' (via runner resolve-extension)');

  // Navigate to MetaMask home
  const homeUrl = 'chrome-extension://' + extId + '/home.html';
  const page = ctx.pages().find(p => p.url().includes('chrome-extension://')) || ctx.pages()[0];
  await page.goto(homeUrl, { waitUntil: 'load', timeout: 15000 });

  // Set window title to slot ID
  await page.evaluate((id) => { document.title = id + ' \u2014 ' + document.title; }, SLOT_ID);

  // Wait for runtime state to settle, then unlock if needed.
  const unlockSelector = '[data-testid=\"unlock-password\"]';
  const homeSelector = '[data-testid=\"account-menu-icon\"]';
  let detectedState = 'unknown';
  for (let i = 0; i < 15; i++) {
    if (await page.locator(homeSelector).count()) {
      detectedState = 'unlocked';
      break;
    }
    if (await page.locator(unlockSelector).count()) {
      detectedState = 'locked';
      break;
    }
    if (page.url().includes('/onboarding')) {
      detectedState = 'onboarding';
      break;
    }
    await new Promise(r => setTimeout(r, 1000));
  }

  if (detectedState === 'locked') {
    console.log('[reopen] Unlocking wallet...');
    await page.fill(unlockSelector, PASSWORD);
    await page.click('[data-testid=\"unlock-submit\"]');
    await page.waitForSelector(homeSelector, { timeout: 30000 });
    console.log('[reopen] Unlocked');
  } else if (detectedState === 'onboarding') {
    console.log('[reopen] On onboarding — state injection may have failed');
  } else {
    console.log('[reopen] Screen: ' + page.url());
  }

  // Close extra extension tabs
  for (const p of ctx.pages()) {
    if (p !== page && p.url().includes('chrome-extension://')) await p.close().catch(() => {});
  }

  fs.writeFileSync(path.join(AGENT_DIR, 'extension.id'), extId);
  console.log('[reopen] Ready \u2014 ' + SLOT_ID + (CDP_PORT ? ' CDP:' + CDP_PORT : ''));

  // Resume webpack now that browser loaded the extension
  resumeWebpack();
  if (WEBPACK_PID) console.log('[webpack] Resumed');
  process.exit(0);
})().catch(e => {
  resumeWebpack();
  try { fs.unlinkSync(path.join(AGENT_DIR, 'browser.pid')); } catch {}
  try { fs.unlinkSync(path.join(AGENT_DIR, 'chromium.pid')); } catch {}
  try { fs.unlinkSync(path.join(AGENT_DIR, 'extension.id')); } catch {}
  console.error(e);
  process.exit(1);
});
"
