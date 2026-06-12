#!/bin/bash
# Contract test: orchestration/mobile/live.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

LIVE="$CT_REPO_ROOT/orchestration/mobile/live.sh"

# --help exits 0
ct_run 0 bash "$LIVE" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 bash "$LIVE" --preflight-mode warp
ct_assert_contains "$CT_OUT" "Unknown --preflight-mode"

# happy path: installed-style co-located layout with stub launch/verify
INST="$CT_TMP/installed"
mkdir -p "$INST/lib"
cp "$LIVE" "$INST/live.sh"
cp "$CT_REPO_ROOT/orchestration/lib/harness-path.sh" "$INST/lib/"
cp "$CT_REPO_ROOT/orchestration/lib/path-defaults.json" "$INST/lib/"
cat > "$INST/launch.sh" <<SH
#!/bin/bash
printf 'launch %s\n' "\$*" >> "$CT_TMP/child-argv.log"
exit 0
SH
cat > "$INST/verify.sh" <<SH
#!/bin/bash
printf 'verify %s\n' "\$*" >> "$CT_TMP/child-argv.log"
exit 0
SH
chmod +x "$INST"/*.sh

TGT="$CT_TMP/target"
mkdir -p "$TGT"
ART="$CT_TMP/artifacts"
ct_run 0 bash "$INST/live.sh" --target "$TGT" --platform ios --preflight-mode fast \
  --no-wallet-setup --artifacts-dir "$ART"

ct_assert_file "$ART/summary.json"
ct_assert_json_field "$ART/summary.json" "j.adapter" "mobile"
ct_assert_json_field "$ART/summary.json" "j.action" "live"
ct_assert_json_field "$ART/summary.json" "j.status" "pass"
ct_assert_json_field "$ART/summary.json" "j.launch.exitCode" "0"
ct_assert_json_field "$ART/summary.json" "j.verify.exitCode" "0"
grep -q "^launch .*--no-wallet-setup" "$CT_TMP/child-argv.log" || ct_fail "launch args not threaded"
grep -q "^verify .*--no-auto-start" "$CT_TMP/child-argv.log" || ct_fail "verify must get --no-auto-start"

# failing launch skips verify and exits 1
sed -i '' 's/exit 0/exit 1/' "$INST/launch.sh"
: > "$CT_TMP/child-argv.log"
ct_run 1 bash "$INST/live.sh" --target "$TGT" --artifacts-dir "$CT_TMP/art2"
ct_assert_contains "$CT_OUT" "Skipping"
grep -q "^verify" "$CT_TMP/child-argv.log" && ct_fail "verify ran despite launch failure"
ct_assert_json_field "$CT_TMP/art2/summary.json" "j.status" "fail"
