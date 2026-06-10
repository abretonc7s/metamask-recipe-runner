# MetaMask Recipe Runner

MetaMask-specific runner for Recipe Protocol v1. This package owns the reusable
MetaMask recipe surface: manifests, Mobile and Extension live adapters, harness
injection, runtime checks, and the public `metamask-recipe` CLI.

You can use this runner directly from a MetaMask Mobile or Extension checkout; no
slot farm is required. Farm/slot orchestration is only a way to scale the same
loop across many checkouts. External tools should resolve this package and invoke
its CLI instead of copying runner logic.

Start with [Architecture](docs/architecture.md) if you need to understand how the
CLI, injected harness, HUD, Mobile bridge, Extension CDP runtime, and Recipe v1
packages fit together.

## Public CLI

```bash
metamask-recipe mobile prepare --target <metamask-mobile> --platform ios --port 8062 --simulator mm-2 [--runtime-dir <runtime-dir>]
metamask-recipe mobile runtime-status --target <metamask-mobile> --port 8062 --json
metamask-recipe mobile status
metamask-recipe mobile run <recipe.json> --artifacts-dir <dir>

metamask-recipe extension prepare --target <metamask-extension> --cdp-port 6662 [--runtime-dir <runtime-dir>]
metamask-recipe extension runtime-status --target <metamask-extension> --cdp-port 6662 --json
metamask-recipe extension decision --target <metamask-extension> --cdp-port 6662 --json
metamask-recipe extension status --target <metamask-extension> --cdp-port 6662 --json
metamask-recipe extension run <recipe.json> --artifacts-dir <dir>
```

Direct typed commands are also available:

```bash
metamask-recipe manifest --adapter mobile --json
metamask-recipe manifest --adapter extension --json
metamask-recipe actions --adapter mobile --json
metamask-recipe actions --adapter extension --json
metamask-recipe runtime-decision --adapter extension --target <repo> --cdp-port <port> --json
metamask-recipe runtime-health --adapter extension --target <repo> --cdp-port <port> --json
metamask-recipe runtime-launch --adapter extension --target <repo> --cdp-port <port> --json
metamask-recipe runtime-launch --adapter extension --target <repo> --cdp-port <port> --start-watch --json
metamask-recipe ensure-ready --adapter extension --target <repo> --cdp-port <port> --json
metamask-recipe run <recipe.json> --adapter <mobile|extension> --project-root <repo> --artifacts-dir <dir> --json
```

## Two parts of this repo

This repo deliberately contains two separate concerns:

1. **Recipe capability/execution** — manifests, reusable recipes, typed runner
   binding, and Mobile/Extension live adapters. This answers “what actions can a
   recipe call and how is proof produced?”
2. **Runtime lifecycle / sandbox helpers** — harness install/cleanup,
   Metro/iOS/Android launch, bundle prewarm, isolated Chrome/CDP launch, Extension
   full-screen or popup-style presentation, build freshness, fixture/profile
   setup, and runtime health checks. This answers “how do I give the agent a
   reproducible local app session?”

Keep changes on the right side of that boundary. Shell scripts should prepare an
isolated sandbox runtime, not define recipe semantics. Recipe adapters should
prove MetaMask behavior, not start Metro or Chrome.

Long term, app clients should expose their own debug automation surface. The
runner's injected harness exists so recipes can still run on older app versions, historical branches, and eval/replay runs that do not have that surface built in.

## Layout

The short version is below; the detailed ownership map is in
[Architecture](docs/architecture.md).

```text
bin/                         public CLI and platform convenience commands
src/                         typed runner core, manifest loading, runtime decisions
live-adapters/               Mobile/Extension action implementations
scripts/                     harness install/cleanup and platform runtime helpers
scripts/lib/path-defaults.json single source for default runtime/harness paths
manifests/                   executable action manifests
recipes/                     reusable smoke/action-validation recipes
docs/                        architecture and contracts
```

Both platforms install ignored runtime helpers under the configured recipe
harness root and write runtime state under the configured recipe runtime dir. The
defaults live in `scripts/lib/path-defaults.json`; use `RECIPE_HARNESS_ROOT` and
`RECIPE_RUNTIME_DIR` only as relative-path overrides.

Runtime file extensions are intentional, not arbitrary. Typed runner logic lives
in `src/**/*.ts`; direct no-build adapters/helpers use `.mjs`; `.cjs` is reserved
for compatibility islands; shell scripts stay at the OS/device edge. See
[Runtime File Conventions](docs/runtime-file-conventions.md).

Extension status includes fixture presence and the resolved fixture path. Launch
uses `RECIPE_WALLET_FIXTURE` when set, then local runtime fixture locations. Use
`runtime-launch --start-watch` when the proof needs a clean webpack build; it
clears the webpack cache, starts the harness-owned watcher, seeds the wallet
fixture, launches Chrome, and runs live smoke verification.

## Boundary

- Shared protocol/runtime packages own graph execution, protocol validation,
  trace/summary/artifact writing, and generic `ui.*` transports.
- This runner owns MetaMask semantics: `metamask.wallet.*`,
  `metamask.perps.*`, action manifests, live adapters, and platform injection.
- Hosts and wrappers own orchestration only: resolve the runner, call
  `metamask-recipe <platform> prepare`, then run recipes.

Do not add shared actions for ticket IDs, exact copy, test IDs, styling, or other
one-off proof details. Use official `ui.*` actions and screenshot claims for
visible acceptance criteria. Direct product/controller calls are allowed only for
setup, teardown, or read/assert paths that do not fabricate user-visible proof.

Every non-terminal recipe node should include `intent` so the live HUD can show
one clear current action while trace files retain full detail.

## Local protocol co-development

Normal installs use the package dependencies declared in `package.json` for the
Recipe v1 protocol and harness runtime. For local protocol/runtime package
development only:

```bash
FARMSLOT_ROOT=/path/to/protocol-checkout npm run dev:link-farmslot
```

Do not commit local TypeScript path shims.

## Validation

```bash
yarn check
bash -n bin/metamask-recipe bin/mm-recipe bin/mme-recipe scripts/*.sh scripts/mobile/*.sh scripts/extension/*.sh
node --check scripts/inject-extension-harness.mjs scripts/cleanup-extension-harness.mjs \
  scripts/extension/extension-readiness.mjs scripts/extension/launch-chrome-detached.cjs \
  scripts/lib/recipe-paths.mjs scripts/check.mjs
```

For live validation, run platform `prepare`, run a smoke/action-validation recipe,
then validate artifacts:

```bash
node scripts/validate-action-e2e-artifacts.mjs <artifacts-dir> manifests/mobile.action-manifest.json mobile
node scripts/validate-action-e2e-artifacts.mjs <artifacts-dir> manifests/extension.action-manifest.json extension
```
