#!/bin/bash
# Contract test: orchestration/mobile/inject.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

INJECT="$CT_REPO_ROOT/orchestration/mobile/inject.sh"

# --help exits 0
ct_run 0 bash "$INJECT" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 bash "$INJECT" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# happy path (metadata-only mode): stub mobile checkout that tracks the
# in-app bridge, so install writes ONLY harness metadata + runner assets.
TGT="$CT_TMP/mobile"
mkdir -p "$TGT/app/core/AgenticService"
echo "// product-owned bridge" > "$TGT/app/core/AgenticService/AgenticService.ts"
git -C "$TGT" init -q
git -C "$TGT" -c user.email=t@t -c user.name=t add -A
git -C "$TGT" -c user.email=t@t -c user.name=t commit -qm stub

ct_run 0 bash "$INJECT" --target "$TGT"
ct_assert_contains "$CT_OUT" "metadata only"

HARNESS="$TGT/temp/recipe/harness/mobile"
ct_assert_file "$HARNESS/manifest.json"
ct_assert_json_field "$HARNESS/manifest.json" "j.adapter" "mobile"
ct_assert_json_field "$HARNESS/manifest.json" "j.installMode" "product-owned"
ct_assert_json_field "$HARNESS/manifest.json" "j.protocolVersion" "v1"
[ -x "$HARNESS/runner/bin/metamask-recipe" ] || ct_fail "runner delegate not executable"
ct_assert_file "$HARNESS/action-manifest.json"
ct_assert_file "$HARNESS/scripts/launch.sh"
ct_assert_file "$HARNESS/scripts/live.sh"
ct_assert_file "$HARNESS/scripts/verify.sh"
ct_assert_file "$HARNESS/scripts/lib/harness-path.sh"
# installed copies must be the real scripts, not forwarding shims
grep -q "deprecated" "$HARNESS/scripts/launch.sh" && ct_fail "installed launch.sh is a shim"
grep -q "deprecated" "$HARNESS/scripts/live.sh" && ct_fail "installed live.sh is a shim"
# git hygiene: exclude entry recorded and present
grep -q "temp/recipe/harness/" "$TGT/.git/info/exclude" || ct_fail "git exclude entry missing"
ct_assert_file "$HARNESS/added-git-exclude"
# product files untouched
[ -z "$(git -C "$TGT" status --porcelain -- app)" ] || ct_fail "product files touched in metadata-only mode"
# cleanupCommand points at an existing cleanup script
cleanup_cmd="$(node -e "console.log(JSON.parse(require('fs').readFileSync('$HARNESS/manifest.json','utf8')).cleanupCommand)")"
cleanup_path="$(printf '%s' "$cleanup_cmd" | sed -E 's/^RECIPE_HARNESS_ROOT=[^ ]+ //; s/ --target.*$//')"
[ -f "$cleanup_path" ] || ct_fail "cleanupCommand path missing: $cleanup_path"
