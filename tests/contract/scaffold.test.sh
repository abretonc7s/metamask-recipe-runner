#!/bin/bash
# Contract test: test scaffold itself (helpers + stub fixtures behave).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

# stub extension repo
ct_stub_extension_repo "$CT_TMP/ext"
ct_assert_file "$CT_TMP/ext/dist/chrome/manifest.json"
ct_assert_json_field "$CT_TMP/ext/dist/chrome/manifest.json" "j.manifest_version" "3"

# stub chrome bin records argv
CHROME="$(ct_stub_chrome_bin "$CT_TMP/bin")"
ct_run 0 "$CHROME" --user-data-dir=/tmp/x --remote-debugging-port=9333
ct_assert_file "$CT_TMP/bin/chrome-argv.log"
grep -q -- '--remote-debugging-port=9333' "$CT_TMP/bin/chrome-argv.log" \
  || ct_fail "argv not recorded"

# pid file helper
ct_stub_pid_file "$CT_TMP/run/webpack.pid"
kill -0 "$(cat "$CT_TMP/run/webpack.pid")" || ct_fail "stub pid not alive"

# ct_run exit-code assertion path
ct_run 3 bash -c 'echo boom >&2; exit 3'
ct_assert_contains "$CT_OUT" "boom"
