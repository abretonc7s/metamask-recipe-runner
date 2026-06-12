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
metamask-recipe run       # recipe/proof: actions execute and evidence is saved
```

Do not mix those layers. Shell helpers may launch apps and check readiness; they
should not define recipe semantics.

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
recipe/         prove one change on ONE instance: typed runner core
                (recipe/src) + per-platform product control and verify
orchestration/  run MANY instances + delivery: launch/live/watch/inject/
                cleanup per platform, shared lib, manifest.json + doctor.mjs
library/        content: actions/ (per-platform action implementations),
                manifests/ (action manifests), recipes/ (reusable recipes)
scripts/        deprecated forwarding shims (+ check tooling)
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
bash -n bin/metamask-recipe bin/mm-recipe bin/mme-recipe scripts/*.sh scripts/mobile/*.sh scripts/extension/*.sh
node --check orchestration/extension/inject.mjs orchestration/extension/cleanup.mjs recipe/extension/extension-readiness.mjs orchestration/extension/launch-browser.cjs orchestration/lib/recipe-paths.mjs scripts/check.mjs
```

More detail: [Architecture](docs/architecture.md), [Package boundaries](docs/package-boundaries.md), [Runtime file conventions](docs/runtime-file-conventions.md).
