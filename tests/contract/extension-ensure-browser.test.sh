#!/bin/bash
# Contract test: orchestration/extension/ensure-browser.sh (formerly reopen-browser.sh)
# No Chrome/Playwright: exercises the documented arg + preflight contract.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

REOPEN="$CT_REPO_ROOT/orchestration/extension/ensure-browser.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$REOPEN" --help
ct_assert_contains "$CT_OUT" "Usage:"

# bad input fails with message (documented exit 1)
ct_run 1 timeout 60 bash "$REOPEN" --bogus
ct_assert_contains "$CT_OUT" "Unknown flag"

# no repo detectable: actionable error
ct_run 1 timeout 60 env -u CHROME_USER_DATA_DIR bash "$REOPEN" --slot-id t --cdp-port 9333
ct_assert_contains "$CT_OUT" "cannot detect repo"

# missing build manifest: preflight FAIL before touching anything
mkdir -p "$CT_TMP/repo"
echo '{}' > "$CT_TMP/repo/package.json"
ct_run 1 timeout 60 bash "$REOPEN" --repo "$CT_TMP/repo" --cdp-port 9333 --runtime-dir temp/recipe/runtime
ct_assert_contains "$CT_OUT" "No build at"

# build present but wallet fixture missing: next documented refusal
ct_stub_extension_repo "$CT_TMP/repo"
ct_run 1 timeout 60 bash "$REOPEN" --repo "$CT_TMP/repo" --cdp-port 9333 --runtime-dir temp/recipe/runtime
ct_assert_contains "$CT_OUT" "wallet fixture missing"

# legacy path forwards with deprecation notice
ct_run 0 timeout 60 bash "$CT_REPO_ROOT/scripts/extension/reopen-browser.sh" --help
ct_assert_contains "$CT_OUT" "deprecated"
ct_assert_contains "$CT_OUT" "Usage:"
