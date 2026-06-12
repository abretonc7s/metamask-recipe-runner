#!/bin/bash
# Contract test: orchestration/extension/sidepanel-toggle.sh
# No Chrome: exercises the documented arg/preflight contract.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

SP="$CT_REPO_ROOT/orchestration/extension/sidepanel-toggle.sh"

# --help exits 0 (handled before repo resolution)
ct_run 0 timeout 60 bash "$SP" --help
ct_assert_contains "$CT_OUT" "Usage:"

# repo not resolvable: actionable FAIL (script walks up from its own dir)
ct_run 1 timeout 60 bash "$SP" status
ct_assert_contains "$CT_OUT" "could not resolve repo root"

# stub repo: missing port exits 1; non-numeric port exits 2
ct_stub_extension_repo "$CT_TMP/repo"
ct_run 1 timeout 60 env REPO="$CT_TMP/repo" bash "$SP" status
ct_assert_contains "$CT_OUT" "--cdp-port is required"
ct_run 2 timeout 60 env REPO="$CT_TMP/repo" bash "$SP" status --cdp-port nope
ct_assert_contains "$CT_OUT" "must be numeric"

# unreachable CDP exits 2 (bounded: curl -m 3)
ct_run 2 timeout 60 env REPO="$CT_TMP/repo" bash "$SP" status --cdp-port 59999
ct_assert_contains "$CT_OUT" "CDP not reachable"

# unknown arg exits 1
ct_run 1 timeout 60 env REPO="$CT_TMP/repo" bash "$SP" status --bogus
ct_assert_contains "$CT_OUT" "unknown arg"
