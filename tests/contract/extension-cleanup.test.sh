#!/bin/bash
# Contract test: orchestration/extension/cleanup.mjs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

INJECT="$CT_REPO_ROOT/orchestration/extension/inject.mjs"
CLEANUP="$CT_REPO_ROOT/orchestration/extension/cleanup.mjs"

# --help exits 0
ct_run 0 timeout 60 node "$CLEANUP" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 node "$CLEANUP" --bogus
ct_assert_contains "$CT_OUT" "unknown arg"

# happy path: inject then cleanup leaves the stub checkout pristine
TGT="$CT_TMP/metamask-extension-stub"
ct_stub_extension_repo "$TGT"
echo '{"name":"metamask-extension","private":true}' > "$TGT/package.json"
git -C "$TGT" init -q
git -C "$TGT" -c user.email=t@t -c user.name=t add -A
git -C "$TGT" -c user.email=t@t -c user.name=t commit -qm stub

ct_run 0 timeout 60 node "$INJECT" --target "$TGT"
HARNESS="$TGT/temp/recipe/harness/extension"
ct_assert_file "$HARNESS/manifest.json"
grep -q "temp/recipe/harness/" "$TGT/.git/info/exclude" || ct_fail "exclude entry missing after inject"

ct_run 0 timeout 60 node "$CLEANUP" --target "$TGT"
ct_assert_contains "$CT_OUT" "Cleaned extension recipe harness"
[ -e "$HARNESS" ] && ct_fail "harness dir not removed"
grep -q "temp/recipe/harness/" "$TGT/.git/info/exclude" 2>/dev/null && ct_fail "exclude entry not removed"
[ -z "$(git -C "$TGT" status --porcelain)" ] || ct_fail "target not pristine after cleanup"

# idempotent on a target with nothing installed
ct_run 0 timeout 60 node "$CLEANUP" --target "$TGT"
