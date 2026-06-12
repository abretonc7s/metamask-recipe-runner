#!/bin/bash
# Contract test: orchestration/extension/start-watch.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

SW="$CT_REPO_ROOT/orchestration/extension/start-watch.sh"
RUNTIME=temp/recipe/runtime

kill_watcher() {
  local pidfile="$1"
  [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null
  return 0
}

# --help exits 0
ct_run 0 timeout 60 bash "$SW" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$SW" --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"

# stub target + stub yarn on PATH
TGT="$CT_TMP/repo"
ct_stub_extension_repo "$TGT"
mkdir -p "$CT_TMP/stubbin"
cat > "$CT_TMP/stubbin/yarn" <<'SH'
#!/bin/bash
echo "compiled successfully"
sleep 600
SH
chmod +x "$CT_TMP/stubbin/yarn"

# dual-writer refusal: alive slot-owned webpack.pid
mkdir -p "$TGT/$RUNTIME"
ct_stub_pid_file "$TGT/$RUNTIME/webpack.pid"
ct_run 1 timeout 60 env PATH="$CT_TMP/stubbin:$PATH" bash "$SW" --target "$TGT"
ct_assert_contains "$CT_OUT" "Refusing to start yarn start"
rm -f "$TGT/$RUNTIME/webpack.pid"

# happy path: watcher starts, compile marker observed, summary written
ct_run 0 timeout 60 env PATH="$CT_TMP/stubbin:$PATH" bash "$SW" --target "$TGT" --summary "$CT_TMP/sw-summary.json"
ct_assert_contains "$CT_OUT" "yarn start compiled successfully"
ct_assert_file "$TGT/$RUNTIME/recipe-harness-webpack.pid"
ct_assert_file "$TGT/$RUNTIME/recipe-harness-webpack.log"
ct_assert_json_field "$CT_TMP/sw-summary.json" "j.feature" "extension/start-watch"
ct_assert_json_field "$CT_TMP/sw-summary.json" "j.status" "pass"
# watcher stays alive by design (kill it for the next case)
kill -0 "$(cat "$TGT/$RUNTIME/recipe-harness-webpack.pid")" || ct_fail "watcher not left running"

# second run: clean-build step kills the previous harness watcher and starts fresh
PID_BEFORE="$(cat "$TGT/$RUNTIME/recipe-harness-webpack.pid")"
ct_run 0 timeout 60 env PATH="$CT_TMP/stubbin:$PATH" bash "$SW" --target "$TGT"
ct_assert_contains "$CT_OUT" "Starting yarn start"
sleep 0.2
kill -0 "$PID_BEFORE" 2>/dev/null && ct_fail "previous harness watcher not killed by clean step"
[ "$(cat "$TGT/$RUNTIME/recipe-harness-webpack.pid")" != "$PID_BEFORE" ] || ct_fail "pid file not refreshed"
kill_watcher "$TGT/$RUNTIME/recipe-harness-webpack.pid"

# build failure: early exit 1 with diagnostics
cat > "$CT_TMP/stubbin/yarn" <<'SH'
#!/bin/bash
echo "Module build failed: stub error"
sleep 600
SH
chmod +x "$CT_TMP/stubbin/yarn"
rm -f "$TGT/$RUNTIME/recipe-harness-webpack.pid"
ct_run 1 timeout 60 env PATH="$CT_TMP/stubbin:$PATH" bash "$SW" --target "$TGT" --summary "$CT_TMP/fail-summary.json"
ct_assert_contains "$CT_OUT" "webpack BUILD FAILED"
ct_assert_json_field "$CT_TMP/fail-summary.json" "j.status" "fail"
kill_watcher "$TGT/$RUNTIME/recipe-harness-webpack.pid"

# runner-bin baseline recording is best-effort and threaded through
cat > "$CT_TMP/stubbin/yarn" <<'SH'
#!/bin/bash
echo "compiled successfully"
sleep 600
SH
cat > "$CT_TMP/stubbin/runner" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$CT_TMP/runner-argv.log"
exit 0
SH
chmod +x "$CT_TMP/stubbin/yarn" "$CT_TMP/stubbin/runner"
rm -f "$TGT/$RUNTIME/recipe-harness-webpack.pid"
ct_run 0 timeout 60 env PATH="$CT_TMP/stubbin:$PATH" bash "$SW" --target "$TGT" --runner-bin "$CT_TMP/stubbin/runner"
ct_assert_contains "$CT_OUT" "recorded deps/cache baseline"
grep -q "runtime-decision --adapter extension --target . --record --json" "$CT_TMP/runner-argv.log" \
  || ct_fail "runtime-decision baseline not recorded"
kill_watcher "$TGT/$RUNTIME/recipe-harness-webpack.pid"
