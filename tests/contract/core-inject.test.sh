#!/bin/bash
# Contract test: orchestration/core/inject.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

INJECT="$CT_REPO_ROOT/orchestration/core/inject.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$INJECT" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$INJECT" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# happy path: overlay-only install into a stub core checkout
TGT="$CT_TMP/core"
mkdir -p "$TGT/packages"
echo '{"name":"core-stub"}' > "$TGT/package.json"
git -C "$TGT" init -q
git -C "$TGT" -c user.email=t@t -c user.name=t add -A
git -C "$TGT" -c user.email=t@t -c user.name=t commit -qm stub

ct_run 0 timeout 60 bash "$INJECT" --target "$TGT"
ct_assert_contains "$CT_OUT" "Installed core recipe harness"

HARNESS="$TGT/temp/recipe/harness/core"
ct_assert_file "$HARNESS/manifest.json"
ct_assert_json_field "$HARNESS/manifest.json" "j.adapter" "core"
ct_assert_json_field "$HARNESS/manifest.json" "j.protocolVersion" "v1"
ct_assert_json_field "$HARNESS/manifest.json" "j.patchedFiles.length" "0"
[ -x "$HARNESS/runner/bin/metamask-recipe" ] || ct_fail "runner delegate not executable"
ct_assert_file "$HARNESS/action-manifest.json"
ct_assert_file "$HARNESS/runner/manifests/core.action-manifest.json"
ct_assert_file "$HARNESS/runner/manifests/mobile.action-manifest.json"
ct_assert_file "$HARNESS/runner/manifests/extension.action-manifest.json"
# overlay-only: product checkout untouched
[ -z "$(git -C "$TGT" status --porcelain -- packages package.json)" ] || ct_fail "product files touched"
# cleanupCommand points at an existing cleanup script
cleanup_path="$(node -e "
const m = JSON.parse(require('fs').readFileSync('$HARNESS/manifest.json','utf8'));
console.log(m.cleanupCommand.replace(/^RECIPE_HARNESS_ROOT=\S+ /, '').replace(/ --target.*$/, ''));")"
[ -f "$cleanup_path" ] || ct_fail "cleanupCommand path missing: $cleanup_path"

