#!/bin/bash
# Contract test: recipe/extension/wallet-fixture-state.cjs
# generate path only (prefill/seed need a Chrome profile / live CDP).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

WF="$CT_REPO_ROOT/recipe/extension/wallet-fixture-state.cjs"

# --help exits 0
ct_run 0 timeout 60 node "$WF" --help
ct_assert_contains "$CT_OUT" "Usage:"

# unknown subcommand exits 2 with usage
ct_run 2 timeout 60 node "$WF" frobnicate
ct_assert_contains "$CT_OUT" "Usage:"

# missing flags on a known subcommand fail with message
ct_run 1 timeout 60 node "$WF" generate
ct_assert_contains "$CT_OUT" "FAIL:"

# generate happy path: deterministic state from a stub fixture. The script
# requires keyring/passworder modules FROM THE TARGET, so the stub checkout
# carries tiny stand-ins (no real product deps, per the contract rules).
ct_stub_extension_repo "$CT_TMP/repo"
mkdir -p "$CT_TMP/repo/test/e2e/fixtures"
cat > "$CT_TMP/repo/test/e2e/fixtures/default-fixture.json" <<'JSON'
{ "data": { "AppStateController": {}, "KeyringController": {}, "PreferencesController": {} } }
JSON
stub_module() {
  local name="$1" body="$2"
  mkdir -p "$CT_TMP/repo/node_modules/$name"
  printf '{"name":"%s","version":"0.0.0","main":"index.js"}\n' "$name" > "$CT_TMP/repo/node_modules/$name/package.json"
  printf '%s\n' "$body" > "$CT_TMP/repo/node_modules/$name/index.js"
}
stub_module "@metamask/browser-passworder" "module.exports = {
  encrypt: async (password, data) => JSON.stringify({ stub: true, data }),
  decrypt: async () => [],
};"
stub_module "@metamask/eth-hd-keyring" "class HdKeyring {
  async deserialize(opts) { this.opts = opts; }
  async getAccounts() {
    return Array.from({ length: this.opts.numberOfAccounts }, (_, i) => '0x' + String(i + 1).padStart(40, '0'));
  }
  async serialize() { return { mnemonic: this.opts.mnemonic, numberOfAccounts: this.opts.numberOfAccounts }; }
}
module.exports = { HdKeyring };"
stub_module "@metamask/eth-simple-keyring" "module.exports = { default: class SimpleKeyring {} };"
stub_module "@ethereumjs/util" "module.exports = {
  privateToAddress: () => Buffer.alloc(20),
  bytesToHex: (b) => '0x' + Buffer.from(b).toString('hex'),
};"
cat > "$CT_TMP/fixture.json" <<'JSON'
{
  "password": "stub-password-123",
  "accounts": [
    { "type": "mnemonic", "value": "test test test test test test test test test test test junk", "count": 2 }
  ]
}
JSON
ct_run 0 timeout 60 node "$WF" generate --target "$CT_TMP/repo" \
  --fixture "$CT_TMP/fixture.json" --out "$CT_TMP/state.json"
ct_assert_file "$CT_TMP/state.json"
node -e "JSON.parse(require('fs').readFileSync('$CT_TMP/state.json','utf8'))" || ct_fail "state.json not valid JSON"

# legacy path forwards with deprecation notice
ct_run 0 timeout 60 node "$CT_REPO_ROOT/scripts/extension/wallet-fixture-state.cjs" --help
ct_assert_contains "$CT_OUT" "deprecated"
ct_assert_contains "$CT_OUT" "Usage:"
