#!/bin/bash
# Contract test: orchestration/extension/inject.mjs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

INJECT="$CT_REPO_ROOT/orchestration/extension/inject.mjs"

# --help exits 0
ct_run 0 timeout 60 node "$INJECT" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 node "$INJECT" --bogus
ct_assert_contains "$CT_OUT" "unknown arg"

# refuses a non-extension target
mkdir -p "$CT_TMP/not-ext"
echo '{"name":"something-else"}' > "$CT_TMP/not-ext/package.json"
ct_run 1 timeout 60 node "$INJECT" --target "$CT_TMP/not-ext"
ct_assert_contains "$CT_OUT" "not a MetaMask Extension checkout"

# happy path: stub extension checkout
TGT="$CT_TMP/metamask-extension-stub"
ct_stub_extension_repo "$TGT"
echo '{"name":"metamask-extension","private":true}' > "$TGT/package.json"
git -C "$TGT" init -q

ct_run 0 timeout 60 node "$INJECT" --target "$TGT"
ct_assert_contains "$CT_OUT" '"status": "pass"'

HARNESS="$TGT/temp/recipe/harness/extension"
ct_assert_file "$HARNESS/manifest.json"
ct_assert_json_field "$HARNESS/manifest.json" "j.adapter" "extension"
ct_assert_json_field "$HARNESS/manifest.json" "j.protocolVersion" "v1"
[ -x "$HARNESS/runner/bin/metamask-recipe" ] || ct_fail "runner delegate not executable"
ct_assert_file "$HARNESS/action-manifest.json"
ct_assert_file "$HARNESS/installed-scripts.sha256"
for f in live.sh refresh-build.sh reopen-browser.sh launch-browser.cjs launch-chrome-detached.cjs sidepanel-toggle.sh verify.sh lib/harness-path.sh; do
  ct_assert_file "$HARNESS/scripts/$f"
done
# installed copies of moved features must be real scripts, not shims
for f in refresh-build.sh reopen-browser.sh launch-browser.cjs launch-chrome-detached.cjs; do
  grep -q "deprecated" "$HARNESS/scripts/$f" && ct_fail "installed $f is a shim"
done
grep -q "temp/recipe/harness/" "$TGT/.git/info/exclude" || ct_fail "git exclude entry missing"
# cleanupCommand points at an existing cleanup script
cleanup_path="$(node -e "
const m = JSON.parse(require('fs').readFileSync('$HARNESS/manifest.json','utf8'));
const match = m.cleanupCommand.match(/'([^']*cleanup[^']*)'/);
console.log(match ? match[1] : '');
")"
[ -f "$cleanup_path" ] || ct_fail "cleanupCommand path missing: $cleanup_path"

# legacy path forwards with deprecation notice
ct_run 0 timeout 60 node "$CT_REPO_ROOT/scripts/inject-extension-harness.mjs" --help
ct_assert_contains "$CT_OUT" "deprecated"
ct_assert_contains "$CT_OUT" "Usage:"
