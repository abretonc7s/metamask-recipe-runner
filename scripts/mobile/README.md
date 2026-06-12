# Mobile runtime helpers

This directory is the runner-owned Mobile runtime adapter. The skills repo must not duplicate these files.

Responsibilities here:
- `launch.sh`, `live.sh`, `verify.sh`: runtime proof flows around a prepared MetaMask Mobile checkout.
- `path.sh`: shared harness path loading for source and installed copies.

Responsibilities outside this directory:
- `orchestration/mobile/inject.sh` installs bridge/HUD assets and these helpers under the configured recipe harness root for Mobile.
- `orchestration/mobile/cleanup.sh` removes the installed harness metadata/assets according to the runner safety contract.
- `bin/metamask-recipe` owns recipe execution and public runner commands.
- The `recipe-harness` skill only resolves this runner and delegates.
