#!/bin/bash
# Contract test: orchestration/extension/launch-browser.cjs (formerly launch-chrome-detached.cjs)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

LAUNCHER="$CT_REPO_ROOT/orchestration/extension/launch-browser.cjs"

# --help exits 0
ct_run 0 timeout 60 node "$LAUNCHER" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input fails with message (documented: thrown error, non-zero exit)
ct_run 1 timeout 60 node "$LAUNCHER" --cdp-port nope
ct_assert_contains "$CT_OUT" "Invalid --cdp-port"
ct_run 1 timeout 60 node "$LAUNCHER" --cdp-port 9333
ct_assert_contains "$CT_OUT" "Missing --chrome-bin"

# happy path: stub chrome records argv; pid + log files written
ct_stub_extension_repo "$CT_TMP/ext"
CHROME="$(ct_stub_chrome_bin "$CT_TMP/bin")"
ct_run 0 timeout 60 node "$LAUNCHER" \
  --cdp-port 9333 \
  --chrome-bin "$CHROME" \
  --profile "$CT_TMP/profile" \
  --extension-dir "$CT_TMP/ext/dist/chrome" \
  --chrome-log "$CT_TMP/run/chrome.log" \
  --chrome-pid "$CT_TMP/run/chrome.pid"
ct_assert_file "$CT_TMP/run/chrome.pid"
ct_assert_file "$CT_TMP/run/chrome.log"
[ -d "$CT_TMP/profile" ] || ct_fail "profile dir not created"
# detached child: wait briefly (bounded) for the stub to record its argv
for _ in $(seq 1 50); do
  [ -f "$CT_TMP/bin/chrome-argv.log" ] && break
  sleep 0.1
done
grep -q -- "--remote-debugging-port=9333" "$CT_TMP/bin/chrome-argv.log" || ct_fail "cdp port not passed"
grep -q -- "--user-data-dir=$CT_TMP/profile" "$CT_TMP/bin/chrome-argv.log" || ct_fail "profile not passed"
grep -q -- "--load-extension=$CT_TMP/ext/dist/chrome" "$CT_TMP/bin/chrome-argv.log" || ct_fail "extension dir not passed"

# missing dist manifest refused
ct_run 1 timeout 60 node "$LAUNCHER" \
  --cdp-port 9333 --chrome-bin "$CHROME" --profile "$CT_TMP/p2" \
  --extension-dir "$CT_TMP/nodist" --chrome-log "$CT_TMP/r2/l" --chrome-pid "$CT_TMP/r2/p"
ct_assert_contains "$CT_OUT" "manifest not found"

