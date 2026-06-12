#!/bin/bash
# Contract test: golden capture of the PREPARE_CMD string that
# scripts/extension/live.sh generates for one fixed input (--start-watch,
# wallet fixture present, stub chrome bin). Captured BEFORE decomposing the
# prepare_parts mega-string; the decomposed sequencer is held to this
# documented behavior (any intentional delta must be explained in the
# decomposition commit body).
#
# Regenerate intentionally with: CT_GOLDEN_UPDATE=1 bash tests/contract/run.sh extension-live-prepare-cmd
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

GOLDEN="$CT_REPO_ROOT/tests/contract/fixtures/prepare-cmd.golden"
LIVE_SRC="$CT_REPO_ROOT/scripts/extension/live.sh"
[ -f "$LIVE_SRC" ] || LIVE_SRC="$CT_REPO_ROOT/orchestration/extension/live.sh"

# Installed-style sandbox: live.sh co-located with stub launch.sh/verify.sh
# (launch records the --prepare-cmd value), lib/ co-located.
INST="$CT_TMP/installed"
mkdir -p "$INST/lib"
cp "$LIVE_SRC" "$INST/live.sh"
cp "$CT_REPO_ROOT/orchestration/lib/harness-path.sh" "$INST/lib/"
cp "$CT_REPO_ROOT/orchestration/lib/path-defaults.json" "$INST/lib/"
cp "$CT_REPO_ROOT/orchestration/lib/json-field.sh" "$INST/lib/"
# path.sh shim for the legacy live.sh sourcing style
cat > "$INST/path.sh" <<'SH'
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/harness-path.sh"
SH
cp "$CT_REPO_ROOT/orchestration/extension/launch-chrome-detached.cjs" "$INST/launch-chrome-detached.cjs"
# the fixture script may still live in the legacy tree or in recipe/
for cand in "$CT_REPO_ROOT/recipe/extension/wallet-fixture-state.cjs" "$CT_REPO_ROOT/scripts/extension/wallet-fixture-state.cjs"; do
  [ -f "$cand" ] && { cp "$cand" "$INST/wallet-fixture-state.cjs"; break; }
done
cat > "$INST/launch.sh" <<SH
#!/bin/bash
prev=""
for a in "\$@"; do
  if [ "\$prev" = "--prepare-cmd" ]; then printf '%s' "\$a" > "$CT_TMP/prepare-cmd.txt"; fi
  prev="\$a"
done
exit 0
SH
cat > "$INST/verify.sh" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$INST"/*.sh "$INST"/*.cjs

# Fixed stub target: built dist + wallet fixture in the runtime dir
TGT="$CT_TMP/target"
ct_stub_extension_repo "$TGT"
mkdir -p "$TGT/temp/recipe/runtime"
echo '{"password":"stub-password"}' > "$TGT/temp/recipe/runtime/wallet-fixture.json"
CHROME="$(ct_stub_chrome_bin "$CT_TMP/cbin")"

ART="$CT_TMP/artifacts"
ct_run 0 timeout 60 env RECIPE_HARNESS_CHROME_BIN="$CHROME" \
  bash "$INST/live.sh" --target "$TGT" --cdp-port 9333 --start-watch --artifacts-dir "$ART"

ct_assert_file "$CT_TMP/prepare-cmd.txt"

# Normalize the only run-variable piece (the sandbox root) so the golden is stable.
sed -e "s|$CT_TMP|__SANDBOX__|g" "$CT_TMP/prepare-cmd.txt" > "$CT_TMP/prepare-cmd.normalized"

if [ "${CT_GOLDEN_UPDATE:-}" = "1" ]; then
  mkdir -p "$(dirname "$GOLDEN")"
  cp "$CT_TMP/prepare-cmd.normalized" "$GOLDEN"
  echo "golden updated: $GOLDEN"
  exit 0
fi

ct_assert_file "$GOLDEN"
if ! diff -u "$GOLDEN" "$CT_TMP/prepare-cmd.normalized" > "$CT_TMP/golden.diff"; then
  cat "$CT_TMP/golden.diff" >&2
  ct_fail "PREPARE_CMD deviates from the golden fixture"
fi
