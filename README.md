# MetaMask Recipe Runner

MetaMask-specific runner for Recipe Protocol v1. Protocol reference:
https://farmslot.io/docs/reference/recipe-protocol-v1.

This package owns the reusable MetaMask recipe surface: manifests, Mobile and
Extension live adapters, harness injection, runtime checks, and the public
`metamask-recipe` CLI. Hosts and thin wrappers should invoke this CLI instead of
copying runner logic.

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

## Layout

```text
bin/
  metamask-recipe              public CLI wrapper
  mm-recipe                    Mobile convenience/runtime commands
  mme-recipe                   Extension convenience/runtime commands

scripts/
  inject-mobile-harness.sh
  cleanup-mobile-harness.sh
  inject-extension-harness.mjs
  cleanup-extension-harness.mjs
  extension/                    Extension runtime helper scripts installed into the harness
  validate-action-e2e-artifacts.mjs
  lib/                         shared path/hash helpers

src/
  cli.ts                       typed Recipe Protocol CLI
  runner.ts                    adapter registration over the shared recipe harness
  adapters.ts                  manifest action bindings
  extension-*.ts               Extension runtime decision/readiness logic
  doctor.ts                    static/runtime diagnostics

live-adapters/
  mobile/                      React Native bridge + Mobile action implementations
  extension/                   CDP/browser-extension action implementations

manifests/                     executable action manifests
recipes/                       reusable smoke/action-validation recipes
```

Both platforms use the same harness root convention:
the configured recipe harness root. Injection writes a manifest, a runner delegate,
manifest/recipe snapshots, and a cleanup command.

Both platforms also expose structured runtime state:
`metamask-recipe <platform> runtime-status --json`. The command writes the same
payload to the configured runtime status path so external hosts can poll
one JSON document instead of parsing terminal logs.

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

Normal installs use package dependencies: `@farmslot/protocol` and
`@farmslot/recipe-harness`. For local protocol/runtime package development only:

```bash
FARMSLOT_ROOT=/path/to/protocol-checkout npm run dev:link-farmslot
```

Do not commit local TypeScript path shims.

## Validation

```bash
yarn check
bash -n bin/metamask-recipe bin/mm-recipe scripts/inject-mobile-harness.sh scripts/cleanup-mobile-harness.sh
node --check scripts/inject-extension-harness.mjs
node --check scripts/cleanup-extension-harness.mjs
node --check scripts/extension/launch-chrome-detached.cjs
```

For live validation, run platform `prepare`, run a smoke/action-validation recipe,
then validate artifacts:

```bash
node scripts/validate-action-e2e-artifacts.mjs <artifacts-dir> manifests/mobile.action-manifest.json mobile
node scripts/validate-action-e2e-artifacts.mjs <artifacts-dir> manifests/extension.action-manifest.json extension
```
