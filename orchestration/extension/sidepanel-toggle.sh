#!/usr/bin/env bash
# sidepanel-toggle.sh — window-mode control for the extension instance.
# (formerly: scripts/extension/sidepanel-toggle.sh, recipe/extension/...)
#
# Purpose:
#   App control: drives chrome.sidePanel for one extension instance's CDP
#   browser (status/open/close/toggle/cycle) without global shortcuts.
#
# Inputs: subcommand (status|open|close|toggle|cycle, default status);
#   --cdp-port <port> (required), --ext-id <id>, --agent-dir <dir>,
#   --settle-ms <ms>; env REPO, CDP_PORT, EXT_ID, SETTLE_MS, AGENT_DIR.
# Outputs: status/progress lines on stdout.
#   Exit 0 — action done; 1 — repo/args missing or action failed;
#   2 — non-numeric port / CDP unreachable.
# Never touches: other instances' browsers (single CDP port scope); the
#   dist build (read-only).
#
# Usage:
#   bash sidepanel-toggle.sh status --cdp-port 6663
#   bash sidepanel-toggle.sh open   --cdp-port 6663 [--ext-id <extension id>]
#   bash sidepanel-toggle.sh close  --cdp-port 6663
#   bash sidepanel-toggle.sh toggle --cdp-port 6663
#   bash sidepanel-toggle.sh cycle  --cdp-port 6663 [--settle-ms 4000]
#
# CDP can inspect, activate, and close sidepanel targets. Opening the side panel
# is done from a clicked extension-page button so Chrome treats
# `chrome.sidePanel.open()` as a user gesture while the action remains scoped to
# this slot's CDP browser. This avoids global Alt+Shift+M shortcut ambiguity
# when several Chromium profiles are running.
set -euo pipefail

ACTION="${1:-status}"
if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
  echo "Usage: sidepanel-toggle.sh <status|open|close|toggle|cycle> --cdp-port <port> [--ext-id <id>] [--agent-dir <dir>] [--settle-ms <ms>]"
  exit 0
fi
shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-}"
if [ -z "$REPO" ]; then
  d="$SCRIPT_DIR"
  while [ "$d" != "/" ]; do
    if [ -f "$d/package.json" ] && [ -d "$d/dist/chrome" ]; then
      REPO="$d"
      break
    fi
    d="$(dirname "$d")"
  done
fi
if [ -z "$REPO" ]; then
  echo "FAIL: could not resolve repo root from ${SCRIPT_DIR}; pass REPO=/path/to/metamask-extension" >&2
  exit 1
fi
cd "$REPO"

CDP_PORT="${CDP_PORT:-}"
EXT_ID="${EXT_ID:-}"
SETTLE_MS="${SETTLE_MS:-4000}"
AGENT_DIR="${AGENT_DIR:-$SCRIPT_DIR}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cdp-port) CDP_PORT="$2"; shift 2 ;;
    --ext-id) EXT_ID="$2"; shift 2 ;;
    --agent-dir) AGENT_DIR="$2"; shift 2 ;;
    --settle-ms) SETTLE_MS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: sidepanel-toggle.sh <status|open|close|toggle|cycle> --cdp-port <port> [--ext-id <id>] [--agent-dir <dir>] [--settle-ms <ms>]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$CDP_PORT" ]; then
  echo "FAIL: --cdp-port is required" >&2
  exit 1
fi
if ! [[ "$CDP_PORT" =~ ^[0-9]+$ ]]; then
  echo "FAIL: CDP port \"$CDP_PORT\" must be numeric" >&2
  exit 2
fi
if ! curl -s -m 3 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  echo "FAIL: CDP not reachable on port ${CDP_PORT}" >&2
  exit 2
fi

json_list() {
  curl -s "http://127.0.0.1:${CDP_PORT}/json/list"
}

find_sidepanel_id() {
  json_list | python3 -c "import json,sys; d=json.load(sys.stdin); ids=[t.get('id','') for t in d if t.get('type')=='page' and 'sidepanel.html' in t.get('url','')]; print(ids[0] if ids else '')"
}

resolve_ext_id() {
  if [ -n "$EXT_ID" ]; then
    printf '%s\n' "$EXT_ID"
    return
  fi
  if [ -f "$AGENT_DIR/extension.id" ]; then
    tr -d '[:space:]' < "$AGENT_DIR/extension.id"
    return
  fi
  json_list | python3 -c "import json,re,sys; d=json.load(sys.stdin); ids=[]; [ids.extend(re.findall(r'^chrome-extension://([^/]+)/', t.get('url',''))) for t in d]; print(ids[0] if ids else '')"
}

activate_sandbox_page() {
  local ext_id target_id
  ext_id="$(resolve_ext_id)"
  target_id="$(
    EXT_ID="$ext_id" json_list | python3 -c "import json,os,sys; d=json.load(sys.stdin); ext=os.environ.get('EXT_ID',''); pages=[t for t in d if t.get('type')=='page']; target=next((t for t in pages if ext and t.get('url','').startswith('chrome-extension://'+ext+'/') and 'sidepanel.html' not in t.get('url','')), None) or next((t for t in pages if t.get('url','').startswith('http://') or t.get('url','').startswith('https://')), None) or (pages[0] if pages else None); print(target.get('id','') if target else '')"
  )"
  if [ -n "$target_id" ]; then
    curl -s "http://127.0.0.1:${CDP_PORT}/json/activate/${target_id}" >/dev/null || true
  fi
}

now_ms() {
  python3 -c "import time; print(int(time.time() * 1000))"
}

wait_for_sidepanel() {
  local start deadline now
  start="$(now_ms)"
  deadline=$((start + SETTLE_MS))
  while :; do
    if [ -n "$(find_sidepanel_id)" ]; then
      return 0
    fi
    now="$(now_ms)"
    if [ "$now" -ge "$deadline" ]; then
      return 1
    fi
    sleep 0.2
  done
}

print_targets() {
  json_list | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'  {t.get(\"type\",\"?\")[:18]:18s} {t.get(\"url\",\"\")[:100]}') for t in d]"
}

status_sidepanel() {
  local sp
  sp="$(find_sidepanel_id)"
  if [ -n "$sp" ]; then
    echo "[sidepanel] open target ${sp}"
  else
    echo "[sidepanel] closed"
  fi
}

close_sidepanel() {
  local sp
  sp="$(find_sidepanel_id)"
  if [ -z "$sp" ]; then
    echo "[sidepanel] already closed"
    return 0
  fi
  curl -s "http://127.0.0.1:${CDP_PORT}/json/close/${sp}" >/dev/null
  echo "[sidepanel] closed target ${sp}"
}

open_sidepanel() {
  if [ -n "$(find_sidepanel_id)" ]; then
    echo "[sidepanel] already open"
    return 0
  fi

  activate_sandbox_page

  local ext_id
  ext_id="$(resolve_ext_id)"
  if [ -z "$ext_id" ]; then
    echo "FAIL: could not resolve extension id for CDP ${CDP_PORT}" >&2
    exit 4
  fi

  CDP_PORT="$CDP_PORT" EXT_ID="$ext_id" node <<'NODE'
const { chromium } = require('playwright');

(async () => {
  const port = process.env.CDP_PORT;
  const extId = process.env.EXT_ID;
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
  const context = browser.contexts()[0];
  let createdPage = false;
  let page = context
    .pages()
    .find(
      (candidate) =>
        candidate.url().startsWith(`chrome-extension://${extId}/`) &&
        !candidate.url().includes('/sidepanel.html'),
    );

  if (!page) {
    page = await context.newPage();
    createdPage = true;
    await page.goto(`chrome-extension://${extId}/home.html`, {
      waitUntil: 'domcontentloaded',
      timeout: 15000,
    });
  }

  await page.bringToFront();
  const result = await page.evaluate(async () => {
    const currentWindow = await chrome.windows.getCurrent();
    const id = '__recipe_open_sidepanel__';
    document.getElementById(id)?.remove();
    const button = document.createElement('button');
    button.id = id;
    button.textContent = 'open sidepanel';
    button.style.cssText =
      'position:fixed;left:8px;top:8px;z-index:2147483647';
    button.onclick = async () => {
      try {
        await chrome.sidePanel.open({ windowId: currentWindow.id });
        button.dataset.result = `ok:${currentWindow.id}`;
      } catch (error) {
        button.dataset.result = `error:${
          error && error.message ? error.message : String(error)
        }`;
      }
    };
    document.documentElement.appendChild(button);
    return { windowId: currentWindow.id };
  });

  await page.locator('#__recipe_open_sidepanel__').click({ timeout: 5000 });
  const clickResult = await page
    .locator('#__recipe_open_sidepanel__')
    .evaluate((button) => button.dataset.result || '');
  if (!clickResult.startsWith('ok:')) {
    throw new Error(
      `chrome.sidePanel.open failed for window ${result.windowId}: ${clickResult}`,
    );
  }
  await page.evaluate(() => {
    document.getElementById('__recipe_open_sidepanel__')?.remove();
  });

  if (createdPage) {
    try {
      await page.close();
    } catch (error) {
      console.warn(
        `[sidepanel] helper page close failed after successful open: ${
          error && error.message ? error.message : error
        }`,
      );
    }
  }
  await browser.close();
})().catch((error) => {
  console.error(`FAIL: ${error.message || error}`);
  process.exit(4);
});
NODE

  if wait_for_sidepanel; then
    echo "[sidepanel] opened"
    return 0
  fi

  echo "FAIL: sidepanel did not appear within ${SETTLE_MS}ms" >&2
  echo "      Current CDP targets:" >&2
  print_targets >&2
  exit 3
}

case "$ACTION" in
  status) status_sidepanel ;;
  open) open_sidepanel ;;
  close) close_sidepanel ;;
  toggle)
    if [ -n "$(find_sidepanel_id)" ]; then
      close_sidepanel
    else
      open_sidepanel
    fi
    ;;
  cycle)
    close_sidepanel
    sleep 1
    open_sidepanel
    ;;
  *)
    echo "Usage: bash sidepanel-toggle.sh {status|open|close|toggle|cycle} --cdp-port PORT [--ext-id ID] [--agent-dir DIR] [--settle-ms N]" >&2
    exit 1
    ;;
esac
