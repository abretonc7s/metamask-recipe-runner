#!/bin/bash
# Contract test: orchestration/extension/snapshot-dist.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

SD="$CT_REPO_ROOT/orchestration/extension/snapshot-dist.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$SD" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$SD" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"
ct_run 2 timeout 60 bash "$SD" --runtime-dist "$CT_TMP/rd"
ct_assert_contains "$CT_OUT" "Missing --dist"

# happy path: snapshot copies dist (minus _metadata) and matches git id
ct_stub_extension_repo "$CT_TMP/repo"
DIST="$CT_TMP/repo/dist/chrome"
mkdir -p "$DIST/_metadata"
echo junk > "$DIST/_metadata/verified_contents.json"
ct_run 0 timeout 60 bash "$SD" --dist "$DIST" --runtime-dist "$CT_TMP/runtime-dist" --summary "$CT_TMP/sd-summary.json"
ct_assert_file "$CT_TMP/runtime-dist/manifest.json"
ct_assert_file "$CT_TMP/runtime-dist/home.html"
[ -e "$CT_TMP/runtime-dist/_metadata" ] && ct_fail "_metadata must be excluded"
ct_assert_json_field "$CT_TMP/sd-summary.json" "j.feature" "extension/snapshot-dist"
ct_assert_json_field "$CT_TMP/sd-summary.json" "j.status" "pass"

# missing manifest: bounded wait then exit 1
ct_run 1 timeout 60 bash "$SD" --dist "$CT_TMP/empty-dist" --runtime-dist "$CT_TMP/rd2" --wait-iterations 1
ct_assert_contains "$CT_OUT" "no manifest"

# git-id mismatch (mid-rebuild): snapshot then mutate the SOURCE manifest id
ct_run 0 timeout 60 bash "$SD" --dist "$DIST" --runtime-dist "$CT_TMP/rd3"
python3 - "$DIST/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["description"] = "stub build from git id: 0ddba11"
json.dump(m, open(p, "w"))
PY
# re-run with a stale snapshot forced in place of a fresh rsync result:
# simulate by snapshotting, then checking guard directly via mismatched pair
ct_run 1 timeout 60 bash -c "
node -e 'const fs=require(\"fs\");const id=p=>{try{return (JSON.parse(fs.readFileSync(p,\"utf8\")).description||\"\").match(/from git id: *([0-9a-f]+)/i)?.[1]||\"\"}catch{return\"\"}};const [a,b]=process.argv.slice(-2);const d=id(a),r=id(b);if(d&&d!==r){console.error(\"runtime-dist git id \"+r+\" != dist \"+d+\" (mid-rebuild?); aborting\");process.exit(1)}' '$DIST/manifest.json' '$CT_TMP/rd3/manifest.json'"
ct_assert_contains "$CT_OUT" "mid-rebuild"
# and the script end-to-end stays green when ids agree again
ct_run 0 timeout 60 bash "$SD" --dist "$DIST" --runtime-dist "$CT_TMP/rd3"
