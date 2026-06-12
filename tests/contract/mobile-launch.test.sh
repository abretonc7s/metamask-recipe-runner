#!/bin/bash
# Contract test: orchestration/mobile/launch.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

LAUNCH="$CT_REPO_ROOT/orchestration/mobile/launch.sh"

# --help exits 0
ct_run 0 bash "$LAUNCH" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 bash "$LAUNCH" --platform windows
ct_assert_contains "$CT_OUT" "Unknown --platform"
ct_run 2 bash "$LAUNCH" --bogus-flag
ct_assert_contains "$CT_OUT" "Unknown arg"

# missing runner install exits 1 with actionable message
mkdir -p "$CT_TMP/empty-target"
ct_run 1 bash "$LAUNCH" --target "$CT_TMP/empty-target" --artifacts-dir "$CT_TMP/art0"
ct_assert_contains "$CT_OUT" "not installed"

# happy path against a stub target: fake installed runner records argv
TGT="$CT_TMP/target"
HARNESS="$TGT/temp/recipe/harness/mobile"
mkdir -p "$HARNESS/runner/bin"
cat > "$HARNESS/runner/bin/metamask-recipe" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$CT_TMP/runner-argv.log"
case "\$2" in
  runtime-status) echo '{"ready":true,"metro":{"port":8099}}' ;;
esac
exit 0
SH
chmod +x "$HARNESS/runner/bin/metamask-recipe"

ART="$CT_TMP/artifacts"
ct_run 0 bash "$LAUNCH" --target "$TGT" --platform android --port 8099 \
  --adb-serial emulator-5554 --preflight-mode auto --artifacts-dir "$ART"

ct_assert_file "$ART/summary.json"
ct_assert_json_field "$ART/summary.json" "j.adapter" "mobile"
ct_assert_json_field "$ART/summary.json" "j.action" "launch"
ct_assert_json_field "$ART/summary.json" "j.status" "pass"
ct_assert_json_field "$ART/summary.json" "j.platform" "android"
ct_assert_json_field "$ART/summary.json" "j.preflightMode" "auto"
ct_assert_json_field "$ART/summary.json" "j.runtime.ready" "true"
ct_assert_json_field "$ART/summary.json" "j.runtime.port" "8099"
grep -q -- "mobile prepare --target $TGT --platform android --port 8099 --adb-serial emulator-5554" "$CT_TMP/runner-argv.log" \
  || ct_fail "prepare argv not threaded: $(cat "$CT_TMP/runner-argv.log")"
ct_assert_file "$ART/logs/prepare.log"
ct_assert_file "$ART/runtime-status.json"

# legacy path forwards with deprecation notice
ct_run 0 bash "$CT_REPO_ROOT/scripts/mobile/launch.sh" --help
ct_assert_contains "$CT_OUT" "deprecated"
ct_assert_contains "$CT_OUT" "Usage:"
