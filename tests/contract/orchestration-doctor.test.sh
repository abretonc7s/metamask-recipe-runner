#!/bin/bash
# Contract test: orchestration/manifest.json + orchestration/doctor.mjs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

DOCTOR="$CT_REPO_ROOT/orchestration/doctor.mjs"

# --help exits 0; bad arg exits 2
ct_run 0 timeout 60 node "$DOCTOR" --help
ct_assert_contains "$CT_OUT" "Usage:"
ct_run 2 timeout 60 node "$DOCTOR" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# the real surface must be healthy: every manifest entry exists and answers
# --help; no orchestration script is missing from the manifest
ct_run 0 timeout 120 node "$DOCTOR"
ct_assert_contains "$CT_OUT" "orchestration surface: pass"

# JSON mode reports pass with zero unlisted
out="$(timeout 120 node "$DOCTOR" --json)"
echo "$out" | node -e "
let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{
  const r=JSON.parse(s);
  if (r.status!=='pass') { console.error('status '+r.status); process.exit(1); }
  if (r.unlisted.length) { console.error('unlisted '+r.unlisted); process.exit(1); }
});" || ct_fail "doctor --json not healthy"
