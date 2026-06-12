#!/bin/bash
# helpers.sh — shared assertions + stub-target fixtures for contract tests
#
# Purpose:
#   Sourced ONLY by tests/contract/*.test.sh (never by feature scripts).
#   Builds throwaway stub targets: fake extension checkout (dist/chrome/
#   manifest.json), fake pid files, stub chrome binary that records argv.
#
# Inputs:  none (functions only). Each test calls ct_init first.
# Outputs: $CT_TMP sandbox dir (auto-removed on exit).
# Never touches: anything outside the per-test $CT_TMP sandbox.

set -uo pipefail

CT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ct_init() {
  CT_TMP="$(mktemp -d -t contract-XXXXXX)"
  trap 'rm -rf "$CT_TMP"' EXIT
}

ct_fail() {
  echo "ASSERT FAIL: $*" >&2
  exit 1
}

# ct_run <expected_exit> cmd... — runs cmd, captures CT_OUT, asserts exit code
ct_run() {
  local expected="$1"
  shift
  CT_OUT="$("$@" 2>&1)"
  CT_CODE=$?
  if [ "$CT_CODE" -ne "$expected" ]; then
    echo "$CT_OUT" >&2
    ct_fail "expected exit $expected, got $CT_CODE: $*"
  fi
}

ct_assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) printf '%s\n' "$1" >&2; ct_fail "output missing: $2" ;;
  esac
}

ct_assert_file() {
  [ -f "$1" ] || ct_fail "expected file: $1"
}

# ct_assert_json_field <file> <node-expr-on-j> <expected>
ct_assert_json_field() {
  local got
  got="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log($2);" "$1")" \
    || ct_fail "unreadable json: $1"
  [ "$got" = "$3" ] || ct_fail "$1: $2 = '$got', expected '$3'"
}

# ct_stub_extension_repo <dir> — fake metamask-extension checkout with built dist
ct_stub_extension_repo() {
  local dir="$1"
  mkdir -p "$dir/dist/chrome/scripts"
  echo '{"name":"stub-extension","private":true}' > "$dir/package.json"
  cat > "$dir/dist/chrome/manifest.json" <<'JSON'
{
  "name": "Stub MetaMask",
  "version": "0.0.0",
  "manifest_version": 3,
  "description": "stub build from git id: deadbeef",
  "background": { "service_worker": "scripts/app-init.js" },
  "action": { "default_popup": "popup-init.html" },
  "side_panel": { "default_path": "sidepanel.html" }
}
JSON
  : > "$dir/dist/chrome/home.html"
  : > "$dir/dist/chrome/popup-init.html"
  : > "$dir/dist/chrome/sidepanel.html"
  : > "$dir/dist/chrome/scripts/app-init.js"
}

# ct_stub_chrome_bin <dir> — executable that records argv + env, then exits 0
# Writes invocations to <dir>/chrome-argv.log (one line per call).
ct_stub_chrome_bin() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/chrome" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$dir/chrome-argv.log"
exit 0
SH
  chmod +x "$dir/chrome"
  echo "$dir/chrome"
}

# ct_stub_pid_file <path> [pid] — pid file; default pid is this test (alive)
ct_stub_pid_file() {
  local path="$1" pid="${2:-$$}"
  mkdir -p "$(dirname "$path")"
  echo "$pid" > "$path"
}
