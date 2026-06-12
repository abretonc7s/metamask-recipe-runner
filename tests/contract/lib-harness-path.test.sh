#!/bin/bash
# Contract test: orchestration/lib (harness-path.sh + json-field.sh + shims).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

LIB="$CT_REPO_ROOT/orchestration/lib"

# harness_root: default comes from path-defaults.json
default_root="$(node -e "console.log(JSON.parse(require('fs').readFileSync('$LIB/path-defaults.json','utf8')).recipeHarnessRoot)")"
got="$(bash -c "source '$LIB/harness-path.sh'; harness_root")"
[ "$got" = "$default_root" ] || ct_fail "harness_root default '$got' != '$default_root'"

# harness_root: rejects absolute and traversal values
ct_run 1 bash -c "source '$LIB/harness-path.sh'; RECIPE_HARNESS_ROOT=/abs harness_root"
ct_assert_contains "$CT_OUT" "relative path"
ct_run 1 bash -c "source '$LIB/harness-path.sh'; RECIPE_HARNESS_ROOT=a/../b harness_root"
ct_assert_contains "$CT_OUT" "path components"

# harness_dir composes target/root/adapter
got="$(bash -c "source '$LIB/harness-path.sh'; harness_dir /tgt mobile")"
[ "$got" = "/tgt/$default_root/mobile" ] || ct_fail "harness_dir '$got'"

# json-field.sh reads dotted fields; missing file returns 1
echo '{"a":{"b":"val"}}' > "$CT_TMP/ctx.json"
got="$(bash -c "source '$LIB/json-field.sh'; read_runtime_context_field '$CT_TMP/ctx.json' a.b")"
[ "$got" = "val" ] || ct_fail "json-field read '$got'"
ct_run 1 bash -c "source '$LIB/json-field.sh'; read_runtime_context_field '$CT_TMP/nope.json' a.b"
