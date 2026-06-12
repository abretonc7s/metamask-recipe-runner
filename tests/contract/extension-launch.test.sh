#!/bin/bash
# Contract test: orchestration/extension/launch.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

LAUNCH="$CT_REPO_ROOT/orchestration/extension/launch.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$LAUNCH" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$LAUNCH" --cdp-port nope
ct_assert_contains "$CT_OUT" "Invalid --cdp-port"
ct_run 2 timeout 60 bash "$LAUNCH" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# harness not installed: exit 1 with actionable message
mkdir -p "$CT_TMP/bare"
ct_run 1 timeout 60 bash "$LAUNCH" --target "$CT_TMP/bare" --cdp-port 9333 --artifacts-dir "$CT_TMP/a0"
ct_assert_contains "$CT_OUT" "not installed"

# happy path: installed-style sandbox with stub readiness; prepare cmd runs in target
INST="$CT_TMP/installed"
mkdir -p "$INST/lib"
cp "$LAUNCH" "$INST/launch.sh"
cp "$CT_REPO_ROOT/orchestration/lib/harness-path.sh" "$INST/lib/"
cp "$CT_REPO_ROOT/orchestration/lib/path-defaults.json" "$INST/lib/"
cat > "$INST/readiness.mjs" <<'MJS'
#!/usr/bin/env node
console.log(JSON.stringify({ status: 'pass', stub: true }));
MJS
chmod +x "$INST"/*.sh "$INST"/*.mjs

TGT="$CT_TMP/target"
ct_stub_extension_repo "$TGT"
mkdir -p "$TGT/temp/recipe/harness/extension"
echo '{"adapter":"extension"}' > "$TGT/temp/recipe/harness/extension/manifest.json"

ART="$CT_TMP/artifacts"
ct_run 0 timeout 60 bash "$INST/launch.sh" --target "$TGT" --cdp-port 9333 \
  --prepare-cmd "pwd > prepare-cwd.txt" --artifacts-dir "$ART"
ct_assert_file "$ART/summary.json"
ct_assert_json_field "$ART/summary.json" "j.adapter" "extension"
ct_assert_json_field "$ART/summary.json" "j.action" "launch"
ct_assert_json_field "$ART/summary.json" "j.status" "pass"
ct_assert_json_field "$ART/summary.json" "j.prepare.commandSupplied" "true"
ct_assert_json_field "$ART/summary.json" "j.prepare.exitCode" "0"
ct_assert_json_field "$ART/summary.json" "j.appControl.status" "pass"
# prepare command must run with cwd = target
[ "$(cat "$TGT/prepare-cwd.txt")" = "$TGT" ] || ct_fail "prepare cmd cwd was $(cat "$TGT/prepare-cwd.txt")"
ct_assert_file "$ART/logs/launch.log"
ct_assert_file "$ART/logs/extension-readiness.json"

# failing prepare command -> status fail, exit 1
ct_run 1 timeout 60 bash "$INST/launch.sh" --target "$TGT" --cdp-port 9333 \
  --prepare-cmd "exit 7" --artifacts-dir "$CT_TMP/a2"
ct_assert_json_field "$CT_TMP/a2/summary.json" "j.status" "fail"
ct_assert_json_field "$CT_TMP/a2/summary.json" "j.prepare.exitCode" "7"

