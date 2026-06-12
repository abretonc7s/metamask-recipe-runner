#!/bin/bash
# Contract test: orchestration/extension/seed-fixture.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

SF="$CT_REPO_ROOT/orchestration/extension/seed-fixture.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$SF" --help
ct_assert_contains "$CT_OUT" "Usage:"

# invalid input exits 2 with message
ct_run 2 timeout 60 bash "$SF" frobnicate
ct_assert_contains "$CT_OUT" "Unknown subcommand"
ct_run 2 timeout 60 bash "$SF" prefill --bogus
ct_assert_contains "$CT_OUT" "Unknown arg"
ct_run 2 timeout 60 bash "$SF" prefill --target "$CT_TMP"
ct_assert_contains "$CT_OUT" "Missing --fixture"

# resolve: env override wins; non-file env value exits 1
TGT="$CT_TMP/target"
mkdir -p "$TGT/temp/recipe/runtime" "$TGT/temp/runtime" "$TGT/temp/.recipe-validation-9333" "$TGT/temp/.agent-validation"
echo '{}' > "$CT_TMP/env-fixture.json"
ct_run 0 timeout 60 env RECIPE_WALLET_FIXTURE="$CT_TMP/env-fixture.json" bash "$SF" resolve --target "$TGT" --cdp-port 9333
ct_assert_contains "$CT_OUT" "$CT_TMP/env-fixture.json"
ct_run 1 timeout 60 env RECIPE_WALLET_FIXTURE="$CT_TMP/nope.json" bash "$SF" resolve --target "$TGT" --cdp-port 9333
ct_assert_contains "$CT_OUT" "not a file"

# resolve: candidate chain order (runtime-dir > temp/runtime > port-scoped > agent)
echo '{}' > "$TGT/temp/.agent-validation/wallet-fixture.json"
out="$(timeout 60 bash "$SF" resolve --target "$TGT" --cdp-port 9333)"
[ "$out" = "$TGT/temp/.agent-validation/wallet-fixture.json" ] || ct_fail "agent fallback: got '$out'"
echo '{}' > "$TGT/temp/.recipe-validation-9333/wallet-fixture.json"
out="$(timeout 60 bash "$SF" resolve --target "$TGT" --cdp-port 9333)"
[ "$out" = "$TGT/temp/.recipe-validation-9333/wallet-fixture.json" ] || ct_fail "port-scoped: got '$out'"
echo '{}' > "$TGT/temp/runtime/wallet-fixture.json"
out="$(timeout 60 bash "$SF" resolve --target "$TGT" --cdp-port 9333)"
[ "$out" = "$TGT/temp/runtime/wallet-fixture.json" ] || ct_fail "temp/runtime: got '$out'"
echo '{}' > "$TGT/temp/recipe/runtime/wallet-fixture.json"
out="$(timeout 60 bash "$SF" resolve --target "$TGT" --cdp-port 9333)"
[ "$out" = "$TGT/temp/recipe/runtime/wallet-fixture.json" ] || ct_fail "runtime-dir: got '$out'"

# resolve: missing fixture -> empty stdout, exit 0, provenance written
mkdir -p "$CT_TMP/bare"
out="$(timeout 60 bash "$SF" resolve --target "$CT_TMP/bare" --cdp-port 9333 --source-out "$CT_TMP/src.json")"
[ -z "$out" ] || ct_fail "expected empty resolve, got '$out'"
ct_assert_json_field "$CT_TMP/src.json" "j.status" "missing"

# prefill / seed-cdp: drive a stub wallet-fixture-state.cjs and check argv threading
INST="$CT_TMP/installed"
mkdir -p "$INST"
cp "$SF" "$INST/seed-fixture.sh"
cat > "$INST/wallet-fixture-state.cjs" <<CJS
#!/usr/bin/env node
require('fs').appendFileSync('$CT_TMP/fs-argv.log', process.argv.slice(2).join(' ') + '\n');
CJS
chmod +x "$INST"/*

ct_run 0 timeout 60 bash "$INST/seed-fixture.sh" prefill --target "$TGT" \
  --fixture "$TGT/temp/recipe/runtime/wallet-fixture.json" --state "$CT_TMP/state.json" \
  --profile "$CT_TMP/profile" --extension-dir "$CT_TMP/rd" --extension-id-file "$CT_TMP/ext.id" \
  --summary "$CT_TMP/prefill-summary.json"
grep -q "^generate --target $TGT --fixture .* --out $CT_TMP/state.json$" "$CT_TMP/fs-argv.log" || ct_fail "generate not invoked"
grep -q "^prefill-profile --target $TGT --state $CT_TMP/state.json --profile $CT_TMP/profile" "$CT_TMP/fs-argv.log" || ct_fail "prefill-profile not invoked"
ct_assert_json_field "$CT_TMP/prefill-summary.json" "j.status" "pass"

ct_run 0 timeout 60 bash "$INST/seed-fixture.sh" seed-cdp --target "$TGT" \
  --fixture "$TGT/temp/recipe/runtime/wallet-fixture.json" --state "$CT_TMP/state.json" \
  --cdp-port 9333 --extension-dir "$CT_TMP/rd" --extension-id-file "$CT_TMP/ext.id" --out "$CT_TMP/parity.json"
grep -q "^seed-cdp --target $TGT .* --cdp-port 9333 .* --out $CT_TMP/parity.json$" "$CT_TMP/fs-argv.log" || ct_fail "seed-cdp not invoked"

# failing fixture-state phase propagates exit 1
cat > "$INST/wallet-fixture-state.cjs" <<'CJS'
#!/usr/bin/env node
console.error('stub fixture failure');
process.exit(1);
CJS
ct_run 1 timeout 60 bash "$INST/seed-fixture.sh" prefill --target "$TGT" \
  --fixture "$TGT/temp/recipe/runtime/wallet-fixture.json" --state "$CT_TMP/state.json" \
  --profile "$CT_TMP/profile" --extension-dir "$CT_TMP/rd" --extension-id-file "$CT_TMP/ext.id"
ct_assert_contains "$CT_OUT" "stub fixture failure"
