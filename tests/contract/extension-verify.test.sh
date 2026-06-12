#!/bin/bash
# Contract test: runner/extension/verify.sh
# No CDP/runner: exercises the documented arg + --out safety contract.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

VF="$CT_REPO_ROOT/runner/extension/verify.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$VF" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$VF" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"
ct_run 2 timeout 60 bash "$VF" --cdp-port nope
ct_assert_contains "$CT_OUT" "Invalid --cdp-port"

# --out escaping the target is refused
ct_stub_extension_repo "$CT_TMP/repo"
ct_run 2 timeout 60 bash "$VF" --target "$CT_TMP/repo" --out '../escape'
ct_assert_contains "$CT_OUT" "did not resolve to a safe path"

# --out without the smoke recipe is refused (no silent fallback)
mkdir -p "$CT_TMP/repo/task-recipes"
ct_run 2 timeout 60 bash "$VF" --target "$CT_TMP/repo" --out task-recipes
ct_assert_contains "$CT_OUT" "no smoke.extension.recipe.json"
