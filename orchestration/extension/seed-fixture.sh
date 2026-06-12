#!/usr/bin/env bash
# seed-fixture.sh — wallet fixture resolution chain + generate/prefill/seed
# prepare_parts mega-string in scripts/extension/live.sh)
#
# Purpose:
#   Resolves which wallet fixture a slot run should use (env override then
#   runtime-dir/legacy/port-scoped candidates) and drives the recipe-tree
#   wallet-fixture-state.cjs phases around the browser launch.
#
# Subcommands (flags):
#   resolve   --target <repo> --cdp-port <port> [--source-out <file>]
#             Prints the fixture path (empty if none). Chain:
#             RECIPE_WALLET_FIXTURE env > <runtime-dir>/wallet-fixture.json >
#             temp/runtime/ > temp/.recipe-validation-<port>/ >
#             temp/.agent-validation/.
#   prefill   --fixture <json> --target <repo> --state <file> --profile <dir>
#             --extension-dir <dist> --extension-id-file <file>
#             Runs fixture-state generate then prefill-profile (pre-launch).
#   seed-cdp  --fixture <json> --target <repo> --state <file> --cdp-port <p>
#             --extension-dir <dist> --extension-id-file <file> --out <file>
#             Runs fixture-state seed-cdp (post-launch).
#   Common: [--fixture-script <path>] [--summary <file>]
#
# Outputs:
#   resolve: fixture path on stdout, optional --source-out provenance JSON;
#   prefill/seed-cdp: whatever wallet-fixture-state.cjs writes (--state/--out).
#   Optional --summary file {feature,status,inputs,outputs,generatedAt}.
#   Exit 0 — ok (resolve: also when no fixture found); 1 — env fixture not a
#   file or fixture-state phase failed; 2 — bad args.
#
# Never touches: product source files; the fixture file (read-only).
set -euo pipefail

SUBCOMMAND="${1:-}"
case "$SUBCOMMAND" in
  resolve|prefill|seed-cdp) shift ;;
  -h|--help)
    echo "Usage: seed-fixture.sh <resolve|prefill|seed-cdp> [flags] (see header)"
    exit 0
    ;;
  *) echo "Unknown subcommand: ${SUBCOMMAND:-<none>} (want resolve|prefill|seed-cdp)" >&2; exit 2 ;;
esac

TARGET="$PWD"
CDP_PORT=""
FIXTURE=""
STATE=""
PROFILE=""
EXTENSION_DIR=""
EXTENSION_ID_FILE=""
OUT=""
SOURCE_OUT=""
FIXTURE_SCRIPT=""
SUMMARY=""
require_value() { [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) require_value "$@"; TARGET="$2"; shift 2 ;;
    --cdp-port) require_value "$@"; CDP_PORT="$2"; shift 2 ;;
    --fixture) require_value "$@"; FIXTURE="$2"; shift 2 ;;
    --state) require_value "$@"; STATE="$2"; shift 2 ;;
    --profile) require_value "$@"; PROFILE="$2"; shift 2 ;;
    --extension-dir) require_value "$@"; EXTENSION_DIR="$2"; shift 2 ;;
    --extension-id-file) require_value "$@"; EXTENSION_ID_FILE="$2"; shift 2 ;;
    --out) require_value "$@"; OUT="$2"; shift 2 ;;
    --source-out) require_value "$@"; SOURCE_OUT="$2"; shift 2 ;;
    --fixture-script) require_value "$@"; FIXTURE_SCRIPT="$2"; shift 2 ;;
    --summary) require_value "$@"; SUMMARY="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: seed-fixture.sh <resolve|prefill|seed-cdp> [flags] (see header)"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

status=fail
finish() {
  if [ -n "$SUMMARY" ]; then
    mkdir -p "$(dirname "$SUMMARY")"
    STATUS_FOR_SUMMARY="$status" SUB_FOR_SUMMARY="$SUBCOMMAND" TARGET_FOR_SUMMARY="$TARGET" FIXTURE_FOR_SUMMARY="$FIXTURE" STATE_FOR_SUMMARY="$STATE" OUT_FOR_SUMMARY="$OUT" SUMMARY_PATH="$SUMMARY" node <<'NODE' || true
const fs = require('fs');
fs.writeFileSync(process.env.SUMMARY_PATH, `${JSON.stringify({
  feature: 'extension/seed-fixture',
  status: process.env.STATUS_FOR_SUMMARY,
  inputs: {
    subcommand: process.env.SUB_FOR_SUMMARY,
    target: process.env.TARGET_FOR_SUMMARY,
    fixture: process.env.FIXTURE_FOR_SUMMARY || null,
  },
  outputs: { state: process.env.STATE_FOR_SUMMARY || null, out: process.env.OUT_FOR_SUMMARY || null },
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE
  fi
}
trap finish EXIT

resolve_fixture_script() {
  if [ -n "$FIXTURE_SCRIPT" ]; then
    [ -f "$FIXTURE_SCRIPT" ] || { echo "seed-fixture: --fixture-script not found: $FIXTURE_SCRIPT" >&2; exit 2; }
    printf '%s' "$FIXTURE_SCRIPT"
    return 0
  fi
  if [ -f "$SCRIPT_DIR/wallet-fixture-state.cjs" ]; then
    printf '%s' "$SCRIPT_DIR/wallet-fixture-state.cjs"
    return 0
  fi
  echo "seed-fixture: wallet-fixture-state.cjs not found next to $SCRIPT_DIR; reinstall the runner." >&2
  exit 1
}

if [ "$SUBCOMMAND" = resolve ]; then
  RUNTIME_DIR=""
  # shellcheck disable=SC1091
  for _hp in "$SCRIPT_DIR/lib/harness-path.sh" "$SCRIPT_DIR/../lib/harness-path.sh"; do
    [ -f "$_hp" ] && { . "$_hp"; break; }
  done
  unset _hp
  if command -v recipe_runtime_dir >/dev/null 2>&1; then
    RUNTIME_DIR="$(recipe_runtime_dir)"
  fi
  resolved=""
  resolve_status=found
  if [ -n "${RECIPE_WALLET_FIXTURE:-}" ]; then
    if [ ! -f "$RECIPE_WALLET_FIXTURE" ]; then
      echo "[recipe-harness] RECIPE_WALLET_FIXTURE is not a file: $RECIPE_WALLET_FIXTURE" >&2
      exit 1
    fi
    resolved="$RECIPE_WALLET_FIXTURE"
  else
    for candidate in \
      ${RUNTIME_DIR:+"$TARGET/$RUNTIME_DIR/wallet-fixture.json"} \
      "$TARGET/temp/runtime/wallet-fixture.json" \
      ${CDP_PORT:+"$TARGET/temp/.recipe-validation-${CDP_PORT}/wallet-fixture.json"} \
      "$TARGET/temp/.agent-validation/wallet-fixture.json"
    do
      [ -f "$candidate" ] && { resolved="$candidate"; break; }
    done
  fi
  [ -n "$resolved" ] || resolve_status=missing
  if [ -n "$SOURCE_OUT" ]; then
    node - "$SOURCE_OUT" "$resolved" <<'NODE'
const fs = require('fs');
const [out, fixture] = process.argv.slice(2);
fs.mkdirSync(require('path').dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify({
  status: fixture ? 'present' : 'missing',
  fixturePath: fixture || null,
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE
  fi
  [ -n "$resolved" ] && printf '%s\n' "$resolved"
  status=pass
  exit 0
fi

# prefill / seed-cdp phases
[ -n "$FIXTURE" ] || { echo "Missing --fixture" >&2; exit 2; }
[ -n "$STATE" ] || { echo "Missing --state" >&2; exit 2; }
[ -n "$EXTENSION_DIR" ] || { echo "Missing --extension-dir" >&2; exit 2; }
[ -n "$EXTENSION_ID_FILE" ] || { echo "Missing --extension-id-file" >&2; exit 2; }
FS_SCRIPT="$(resolve_fixture_script)"

if [ "$SUBCOMMAND" = prefill ]; then
  [ -n "$PROFILE" ] || { echo "Missing --profile" >&2; exit 2; }
  node "$FS_SCRIPT" generate --target "$TARGET" --fixture "$FIXTURE" --out "$STATE" || exit 1
  node "$FS_SCRIPT" prefill-profile --target "$TARGET" --state "$STATE" --profile "$PROFILE" --extension-dir "$EXTENSION_DIR" --extension-id-file "$EXTENSION_ID_FILE" || exit 1
else
  [ -n "$CDP_PORT" ] || { echo "Missing --cdp-port" >&2; exit 2; }
  [ -n "$OUT" ] || { echo "Missing --out" >&2; exit 2; }
  node "$FS_SCRIPT" seed-cdp --target "$TARGET" --fixture "$FIXTURE" --state "$STATE" --cdp-port "$CDP_PORT" --extension-dir "$EXTENSION_DIR" --extension-id-file "$EXTENSION_ID_FILE" --out "$OUT" || exit 1
fi
status=pass
