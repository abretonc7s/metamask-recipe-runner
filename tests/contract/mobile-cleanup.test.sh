#!/bin/bash
# Contract test: orchestration/mobile/cleanup.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

INJECT="$CT_REPO_ROOT/orchestration/mobile/inject.sh"
CLEANUP="$CT_REPO_ROOT/orchestration/mobile/cleanup.sh"

# --help exits 0
ct_run 0 bash "$CLEANUP" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 bash "$CLEANUP" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# no harness installed: exits 1 with message
TGT0="$CT_TMP/empty"
mkdir -p "$TGT0"
git -C "$TGT0" init -q
ct_run 1 bash "$CLEANUP" --target "$TGT0"
ct_assert_contains "$CT_OUT" "No mobile harness backup"

# happy path: inject (metadata-only) then cleanup restores pristine state
TGT="$CT_TMP/mobile"
mkdir -p "$TGT/app/core/AgenticService"
echo "// product-owned bridge" > "$TGT/app/core/AgenticService/AgenticService.ts"
git -C "$TGT" init -q
git -C "$TGT" -c user.email=t@t -c user.name=t add -A
git -C "$TGT" -c user.email=t@t -c user.name=t commit -qm stub

ct_run 0 bash "$INJECT" --target "$TGT"
HARNESS="$TGT/temp/recipe/harness/mobile"
ct_assert_file "$HARNESS/manifest.json"
grep -q "temp/recipe/harness/" "$TGT/.git/info/exclude" || ct_fail "exclude entry missing after inject"

ct_run 0 bash "$CLEANUP" --target "$TGT"
ct_assert_contains "$CT_OUT" "Cleaned mobile recipe harness"
[ -e "$HARNESS" ] && ct_fail "harness dir not removed"
grep -q "temp/recipe/harness/" "$TGT/.git/info/exclude" 2>/dev/null && ct_fail "exclude entry not removed"
[ -z "$(git -C "$TGT" status --porcelain)" ] || ct_fail "target not pristine after cleanup"

# legacy path forwards with deprecation notice
ct_run 0 bash "$CT_REPO_ROOT/scripts/cleanup-mobile-harness.sh" --help
ct_assert_contains "$CT_OUT" "deprecated"
ct_assert_contains "$CT_OUT" "Usage:"
