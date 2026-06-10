# Extension runtime helpers

This directory is the runner-owned Extension runtime adapter. The skills repo must not duplicate these files.

Responsibilities here:
- `launch.sh`, `live.sh`, `verify.sh`: runtime proof flows around a prepared MetaMask Extension checkout.
- `extension-readiness.mjs`: CDP/readiness classification and extension-id repair.
- `wallet-fixture-state.cjs`: deterministic fixture/profile state helpers.
- `refresh-build.sh`, `reopen-browser.sh`, `sidepanel-toggle.sh`: slot/operator helpers copied into the installed harness manifest.

Responsibilities outside this directory:
- `scripts/inject-extension-harness.mjs` installs this directory under the configured recipe harness root for Extension.
- `scripts/cleanup-extension-harness.mjs` removes that installed harness.
- `bin/metamask-recipe` owns recipe execution and public runner commands.
- The `recipe-harness` skill only resolves this runner and delegates.
