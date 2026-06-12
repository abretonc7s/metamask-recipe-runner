#!/bin/bash
# Contract test: recipe/mobile/verify.sh
# No simulator/runner: exercises the documented arg + gate contract.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

VF="$CT_REPO_ROOT/recipe/mobile/verify.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$VF" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$VF" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"
ct_run 2 timeout 60 bash "$VF" --platform windows
ct_assert_contains "$CT_OUT" "Unknown --platform"
ct_run 2 timeout 60 bash "$VF" --preflight-mode warp
ct_assert_contains "$CT_OUT" "Unknown --preflight-mode"

# auto-start gate env validation: bogus value exits 2
ct_run 2 timeout 60 env RECIPE_HARNESS_MOBILE_AUTO_START=maybe bash "$VF" --target "$CT_TMP"
ct_assert_contains "$CT_OUT" "Unknown RECIPE_HARNESS_MOBILE_AUTO_START"

