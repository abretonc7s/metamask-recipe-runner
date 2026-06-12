#!/bin/bash
# Contract test: content/engine seam regression net.
# (a) every library/actions module must be importable (catches stale relative
#     imports after tree moves — the class of break behind xreview blocker 1);
# (b) the runner self-test must pass end-to-end (engine + adapters + library).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

# --- (a) dynamic-import every action module + the adapter binding ---
cat > "$CT_TMP/import-all.mjs" <<'MJS'
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.argv[2];
const targets = [path.join(root, 'runner/src/adapters.ts')];
(function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(file);
    else if (entry.name.endsWith('.mjs')) targets.push(file);
  }
})(path.join(root, 'library/actions'));

let failures = 0;
for (const target of targets) {
  try {
    await import(pathToFileURL(target).href);
  } catch (error) {
    failures += 1;
    console.error(`IMPORT FAIL ${path.relative(root, target)}: ${error.message}`);
  }
}
console.log(`imported ${targets.length - failures}/${targets.length} modules`);
process.exit(failures === 0 ? 0 : 1);
MJS

RUNNER_JS="$CT_REPO_ROOT/node_modules/.bin/tsx"
[ -x "$RUNNER_JS" ] || RUNNER_JS="node"
ct_run 0 timeout 120 "$RUNNER_JS" "$CT_TMP/import-all.mjs" "$CT_REPO_ROOT"
ct_assert_contains "$CT_OUT" "imported"
case "$CT_OUT" in *"IMPORT FAIL"*) ct_fail "module import failures: $CT_OUT" ;; esac
# the loop must actually cover the action library (46 modules at last count)
count="$(printf '%s' "$CT_OUT" | sed -n 's/imported \([0-9]*\)\/.*/\1/p')"
[ "${count:-0}" -ge 40 ] || ct_fail "import sweep too small: $CT_OUT"

# --- (b) end-to-end self-test through the real CLI wrapper ---
ct_run 0 timeout 120 "$CT_REPO_ROOT/bin/metamask-recipe" self-test --json
ct_assert_contains "$CT_OUT" '"status": "pass"'
