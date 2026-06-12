# MetaMask Recipe Runner

Run Recipe Protocol checks against a local MetaMask Mobile or Extension checkout.

One package, two responsibilities:

- **Recipe layer:** manifests, recipes, Mobile/Extension adapters, proof output.
- **Runtime layer:** start/reuse Metro or Chrome, seed fixtures, wait for readiness.

Farmslot and skills are wrappers around this CLI; they should not copy runner
logic.

## Quick start

```bash
# 1) Prepare a runtime
metamask-recipe mobile prepare --target <metamask-mobile> --platform ios --port 8062 --simulator mm-2
metamask-recipe extension prepare --target <metamask-extension> --cdp-port 6662

# 2) Run a recipe
metamask-recipe run recipe.json --adapter mobile --project-root <metamask-mobile> --artifacts-dir /tmp/recipe-artifacts --json
```

Outputs: `summary.json`, `trace.json`, screenshots, logs, and an artifact
manifest.

## Mental model

```text
metamask-recipe prepare   # runtime/orchestration: app is ready
metamask-recipe run       # runner/proof: actions execute and evidence is saved
```

Do not mix those layers. library/ = what recipes ARE (recipes, actions,
manifests — the content). runner/ = what EXECUTES them (engine, verify,
evidence). orchestration/ = what CONTROLS the app and its instances (start,
windows, wallet state, health, ports, parallel).

## Useful commands

```bash
# Capabilities
metamask-recipe manifest --adapter mobile --json
metamask-recipe manifest --adapter extension --json
metamask-recipe actions --adapter mobile --json
metamask-recipe actions --adapter extension --json

# Runtime status
metamask-recipe mobile runtime-status --target <mobile> --port 8062 --json
metamask-recipe extension runtime-status --target <extension> --cdp-port 6662 --json
metamask-recipe ensure-ready --adapter extension --target <extension> --cdp-port 6662 --json
```

## Layout

```text
bin/            CLI and platform convenience commands
runner/         what EXECUTES recipes: engine glue (runner/src) +
                per-platform verify (engine, verify, evidence)
orchestration/  what CONTROLS the app and its instances: launch/live/
                watch/windows/wallet state/health/inject/cleanup per
                platform, shared lib, manifest.json + doctor.mjs
library/        what recipes ARE: recipes/ (recipe JSONs), actions/
                (per-platform implementations), manifests/ (capability)
scripts/        dev tooling (yarn check, local farmslot link, e2e validation)
docs/           details when this README is not enough
```

Defaults for installed harness/runtime paths live in
`orchestration/lib/path-defaults.json`.

## Runtime notes

- `tmux` is recommended for long-lived Metro/webpack processes; standalone use
  falls back to detached `nohup` where possible.
- Mobile may inject a local development bridge/HUD into older checkouts. Do not
  commit those product patches.
- Extension does not patch product source; it drives `dist/chrome` through Chrome
  CDP.

## Validate changes

```bash
yarn check
bash -n bin/metamask-recipe bin/mm-recipe bin/mme-recipe orchestration/{mobile,extension,core}/*.sh runner/{mobile,extension}/verify.sh
node --check orchestration/extension/inject.mjs orchestration/extension/cleanup.mjs orchestration/extension/readiness.mjs orchestration/extension/launch-browser.cjs orchestration/lib/recipe-paths.mjs scripts/check.mjs
```

More detail: [Architecture](docs/architecture.md), [Package boundaries](docs/package-boundaries.md), [Runtime file conventions](docs/runtime-file-conventions.md).
