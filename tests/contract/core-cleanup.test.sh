#!/bin/bash
# Contract test: orchestration/core/cleanup.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

INJECT="$CT_REPO_ROOT/orchestration/core/inject.sh"
CLEANUP="$CT_REPO_ROOT/orchestration/core/cleanup.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$CLEANUP" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$CLEANUP" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# idempotent: cleanup with nothing installed succeeds
TGT="$CT_TMP/core"
mkdir -p "$TGT"
ct_run 0 timeout 60 bash "$CLEANUP" --target "$TGT"
ct_assert_contains "$CT_OUT" "Cleaned core recipe harness"

# round-trip: inject then cleanup removes the overlay
echo '{"name":"core-stub"}' > "$TGT/package.json"
ct_run 0 timeout 60 bash "$INJECT" --target "$TGT"
ct_assert_file "$TGT/temp/recipe/harness/core/manifest.json"
ct_run 0 timeout 60 bash "$CLEANUP" --target "$TGT"
[ ! -e "$TGT/temp/recipe/harness/core" ] || ct_fail "core harness dir not removed"
