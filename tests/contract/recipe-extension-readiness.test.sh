#!/bin/bash
# Contract test: recipe/extension/extension-readiness.mjs
# No Chrome: dist-file readiness paths only (CDP checks need a live browser).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

RD="$CT_REPO_ROOT/recipe/extension/extension-readiness.mjs"

# --help exits 0
ct_run 0 timeout 60 node "$RD" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input fails with message (documented: thrown error, non-zero exit)
ct_run 1 timeout 60 node "$RD" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# happy path: complete stub dist passes all expected-file checks
ct_stub_extension_repo "$CT_TMP/repo"
ct_run 0 timeout 60 node "$RD" --target "$CT_TMP/repo" --json
ct_assert_contains "$CT_OUT" '"manifestVersion": 3'
echo "$CT_OUT" | grep -q '"status": "fail"' && ct_fail "unexpected failing check"

# missing entry file -> failing check, non-zero exit
rm -f "$CT_TMP/repo/dist/chrome/sidepanel.html"
ct_run 1 timeout 60 node "$RD" --target "$CT_TMP/repo" --json
ct_assert_contains "$CT_OUT" '"status": "fail"'

# missing dist entirely -> error
ct_run 1 timeout 60 node "$RD" --target "$CT_TMP/nodist" --json

