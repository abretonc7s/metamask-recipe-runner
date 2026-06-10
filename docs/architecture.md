# MetaMask Recipe Runner Architecture

This repo is the MetaMask-specific adapter layer for Recipe Protocol v1. It is
not the protocol engine, not a skills repo, not a slot farm, and not product
code. Its job is to publish reviewable MetaMask capabilities and run them
against a local Mobile or Extension checkout without committing harness runtime
into that checkout.

The core model is standalone: install or check out this runner, point it at a
MetaMask checkout, and run `metamask-recipe`. Farm/slot orchestration is only a
way to scale the same loop across many checkouts, machines, ports, and agents;
it is not required to understand or use the runner.

## One-minute model

```text
human CLI / optional skill wrapper
        │ resolve + invoke
        ▼
metamask-recipe-runner
        │ MetaMask action manifests, live adapters, harness install, runtime probes
        ▼
Recipe harness package
        │ generic graph execution, official ui.* transports, traces, artifacts
        ▼
Recipe protocol package
        │ Recipe v1 schema, manifest contract, artifact contract
        ▼
MetaMask app under test
        │ local debug runtime only; product source should not own runner logic
        ▼
summary.json · trace.json · artifact-manifest.json · screenshots/logs
```

Dependency direction is one-way. Wrappers call the runner; the runner calls the
shared harness/protocol packages; product apps are only driven at runtime.

## The two subsystems

This repo has two intentionally different kinds of code. Keeping them separate
is the main way to understand the repository.

| Subsystem | Question it answers | Primary files | Should contain | Should not contain |
|---|---|---|---|---|
| Recipe capability/execution | “What can a MetaMask recipe do, and how does a node execute?” | `manifests/`, `recipes/`, `src/runner.ts`, `src/adapters.ts`, `src/live-adapter-contract.ts`, `live-adapters/` | action manifests, domain actions, UI transport binding, adapter outputs, proof semantics | Metro startup, Chrome process flags, simulator boot, git-exclude/rsync cleanup |
| Runtime lifecycle / sandbox helpers | “How do I give an agent an isolated app session that is ready to inspect or run recipes?” | `bin/mm-recipe`, `bin/mme-recipe`, `scripts/inject-*`, `scripts/mobile/`, `scripts/extension/`, `scripts/lib/` | install/sync harness, start/reuse Metro or Chrome, prewarm bundles, open Extension full-screen or popup-style, prepare dedicated profiles/fixtures, check build/runtime health, cleanup local files | new recipe schema, graph traversal, MetaMask business semantics, task-specific proof logic |

When reviewing a change, first decide which subsystem it touches. Recipe changes
should be validated against manifests and action artifacts. Runtime lifecycle changes should be validated by install/launch/live/verify
behavior on a real checkout. Some commands cross the boundary, but they should
do so by delegating: sandbox helpers get the runtime ready, then
`metamask-recipe run` executes the recipe.

## Ownership boundaries

| Layer | Owns | Must not own |
|---|---|---|
| Human CLI / optional wrapper | Target selection, runner invocation, evidence handoff | Copied adapter scripts, recipe graph execution, product runtime logic |
| This runner | MetaMask action manifests, `metamask.*` adapters, Mobile/Extension harness install, runtime health/decision commands | Shared Recipe v1 schema, generic `ui.*` semantics, task-specific acceptance criteria |
| `Recipe harness package` | Recipe graph execution, standard core/ui adapters, trace/summary/artifact writing | MetaMask wallet/Perps behavior |
| `Recipe protocol package` | Recipe/manifest/artifact schemas | Runtime control or product-specific actions |
| Product checkout | App code and debug hooks exposed by the app | Harness scripts, runner copy, skills, private workflow logic |

Rule of thumb: if code describes **what MetaMask can do**, it belongs here. If it
describes **how Recipe v1 works**, it belongs in the shared protocol/runtime packages. If it
describes **how an agent should work**, it belongs in skills.

## Key files and directories

| Path | Responsibility |
|---|---|
| `bin/metamask-recipe` | Public binary. Dispatches to typed CLI and platform convenience commands. |
| `bin/mm-recipe` | Mobile convenience/runtime UX: start/reuse Metro, prewarm bundle, launch app, query bridge, setup wallet, screenshot. |
| `bin/mme-recipe` | Extension convenience/runtime UX: install, health, decision, ready, watch/refresh/reopen, run recipes. |
| `src/cli.ts` | Typed command handlers: manifests, actions, doctor, runtime health/decision/launch, `run`, self-test. |
| `src/runner.ts` | Creates the Recipe runner by combining shared core/ui adapters with MetaMask live adapters. Enables the Recipe HUD metadata. |
| `src/adapters.ts` | MetaMask adapter binding and `ui.*` transport selection for Mobile vs Extension. Refuses static placeholders for live-only proof actions. |
| `src/live-adapter-contract.ts` | Script adapter contract and lookup rules for `live-adapters/<platform>/<domain>/*.mjs`. |
| `manifests/*.action-manifest.json` | Reviewable capability contract. A recipe may only call declared actions. |
| `live-adapters/mobile/` | Mobile action implementations. Talks to the runner bridge and app-exposed `globalThis.__AGENTIC__` hooks. |
| `live-adapters/extension/` | Extension action implementations. Talks to Chrome/extension pages over CDP. |
| `scripts/inject-mobile-harness.sh` | Installs/syncs the Mobile runtime overlay under the configured harness root and protects cleanup/git-exclude behavior. |
| `scripts/inject-extension-harness.mjs` | Installs/syncs Extension runtime helpers under the configured harness root. |
| `scripts/mobile/` | Runner-owned Mobile launch/live/verify helpers copied into installed harnesses. |
| `scripts/extension/` | Runner-owned Extension launch/live/verify/readiness/browser helpers copied into installed harnesses. |
| `scripts/lib/path-defaults.json` | Single source for default `recipeHarnessRoot` and `recipeRuntimeDir`. |
| `scripts/lib/harness-path.sh`, `scripts/lib/recipe-paths.mjs`, `src/paths.ts` | Shell, standalone Node, and TypeScript accessors for those defaults plus validation. |
| `recipes/` | Reusable smoke/action-validation recipes only. Task-specific proof recipes stay task-local. |
| `docs/` | Runner architecture, contracts, and operational conventions. |

## Runtime paths and installed harnesses

Defaults are centralized in `scripts/lib/path-defaults.json`:

```json
{
  "recipeHarnessRoot": "temp/recipe/harness",
  "recipeRuntimeDir": "temp/recipe/runtime"
}
```

All shell, standalone Node, and TypeScript code must read these through the
shared helpers instead of hardcoding defaults. Environment overrides are allowed
through `RECIPE_HARNESS_ROOT` and `RECIPE_RUNTIME_DIR`, but they must stay safe
relative paths.

Install commands write a small runtime package into the target checkout:

```text
<target>/<recipeHarnessRoot>/<adapter>/
  manifest.json              installed source/revision/cleanup metadata
  action-manifest.json        snapshot of the adapter manifest
  runner/bin/metamask-recipe  delegate back to the resolved runner source
  runner/recipes/             reusable recipe snapshot
  scripts/                    adapter runtime helpers copied from this repo
```

The installed harness exists so a running slot has stable helper paths even when
called from skills, orchestration hooks, or a human shell. The source of truth remains
this runner.

## Recipe execution vs sandbox lifecycle

`metamask-recipe run <recipe.json> --adapter ...` is the recipe path. It creates
a shared Recipe runner (`src/runner.ts`), validates the recipe against the
manifest, executes nodes, and writes artifacts. If a bug is about action fields,
trace output, adapter semantics, or whether a recipe proves a claim, start in
`manifests/`, `src/`, `live-adapters/`, and `recipes/`.

`prepare`, `launch`, `live`, `verify`, `status`, `decision`, and `ready` are
sandbox lifecycle paths. They give the agent a reproducible local app session:
Mobile with Metro/dev-client/simulator and the bridge online; Extension with an
isolated browser profile, unpacked extension loaded, and a known home/popup-style
UI target. If a bug is about Metro, bundle prewarm, simulator launch, Chrome CDP,
Extension full-screen vs popup presentation, build freshness, wallet fixture
placement, git-exclude, or cleanup, start in `bin/mm-recipe`, `bin/mme-recipe`,
`scripts/mobile/`, `scripts/extension/`, and `scripts/inject-*`.

Do not put recipe graph traversal into shell scripts. Shell scripts may prepare
or inspect the sandboxed runtime, then delegate graph execution to
`metamask-recipe run`.

## HUD vs bridge vs product hooks

These names are easy to mix up; they are different concerns.

| Term | What it is | Why it exists |
|---|---|---|
| Recipe HUD | A visual overlay driven by Recipe runner metadata (`intent`, current node, status). | Makes screenshots/videos explain what the recipe is doing without exposing secrets. |
| Mobile bridge | Runner-side CDP/Hermes bridge process under `live-adapters/mobile/bridge-runtime/`. | Lets the runner call app-exposed commands, read state, press UI targets, and capture status from React Native. |
| `globalThis.__AGENTIC__` | Development-only in-app command surface exposed by the Mobile overlay/patch. | Gives the bridge a stable API for route/status/wallet/UI operations when the app lacks a built-in automation API. |
| Extension CDP hooks | Chrome DevTools Protocol access to extension pages/background state hooks. | Lets the runner inspect/drive the unpacked Extension without patching product source. |

The HUD does not control the app. The bridge/CDP control the app. The HUD only
renders proof context.

## Mobile runtime shape

Mobile has the most moving parts because React Native does not expose a browser
DOM by default.

```text
mm-recipe / scripts/mobile/*.sh
      │ starts/reuses Metro, prewarms bundle, launches iOS/Android dev client
      ▼
live-adapters/mobile/bridge-runtime/cdp-bridge.cjs
      │ connects to Hermes / RN debug runtime
      ▼
globalThis.__AGENTIC__ inside the app
      │ route/status/wallet/ui commands + optional HUD rendering
      ▼
live-adapters/mobile/{wallet,perps,ui,platform}/*.mjs
```

Ideally the app would expose a product-owned debug automation surface directly,
so the runner would not need to patch or inject Mobile client files at all. The
current injection exists as a compatibility bridge: it lets recipes run against
older Mobile versions, historical PR branches, and eval/replay runs that do not yet include that
client-side automation surface.

The Mobile injection currently may touch development-only product files on older
checkouts to install the `AgenticService`, navigation hook, and HUD mount. That
is the fragile compatibility path, not the desired long-term product contract.
Those product patches are local runtime state: never commit them to MetaMask
Mobile. The runner also installs ignored helper files under
`temp/recipe/harness/mobile`.

Mobile `ensure_*` actions must be idempotent: if the wallet is already unlocked,
`metamask.wallet.ensure_unlocked` should report success or converge cheaply, not
fail because the starting state differed.

## Extension runtime shape

Extension does not need an in-product source patch. The runner works through an
unpacked `dist/chrome` build and Chrome CDP.

```text
mme-recipe / scripts/extension/*.sh
      │ checks dist freshness, build health, fixture/profile state
      ▼
Chrome for Testing with --load-extension=<runtime-dist>
      │ CDP target discovery + deterministic extension id
      ▼
live-adapters/extension/{wallet,perps,ui,platform}/*.mjs
      │ extension page/background hooks and UI events
```

`runtime-launch --start-watch` is the clean-build path. Without `--start-watch`,
verify can prove the existing runtime is reachable but may fail `dist-freshness`
if `dist/chrome` does not match `HEAD`. That failure is intentional: it prevents
silently proving stale product code.

## Why there are shell scripts

The shell scripts are large because sandbox setup crosses OS/device boundaries:
`simctl`, `adb`, Metro, Watchman, Chrome process flags, isolated browser
profiles, git exclude files, symlink safety checks, and cleanup all live outside
Node's typed domain logic. Their purpose is to give an agent a reliable app
session, not to define recipe semantics.

Allowed in shell:

- parsing CLI flags for lifecycle commands;
- calling OS/device tools;
- copying/removing installed harness files;
- starting/stopping/reusing local dev servers;
- writing small runtime summaries from command results.

Not allowed in shell:

- Recipe v1 graph execution;
- MetaMask domain semantics that can live in `src/**/*.ts` or `live-adapters/**/*.mjs`;
- duplicated action manifest logic;
- product-specific business decisions beyond runtime boot/health checks.

When a shell helper starts accumulating domain behavior, move that behavior into
TypeScript or a focused `.mjs` adapter and keep shell as the launcher.

## Adding or changing capabilities

1. Add/adjust the shared capability in both Mobile and Extension manifests when
   the concept exists on both platforms.
2. Implement durable behavior under `live-adapters/<platform>/<domain>/`.
3. Keep parameterized actions instead of multiplying action names.
4. Ensure every `ensure_*` action proves a postcondition.
5. Use official `ui.*` actions and screenshot claims for visible acceptance
   criteria; do not add task-specific `metamask.*` actions for exact copy,
   styling, ticket IDs, or one-off selectors.
6. Update smoke/action-validation recipes only when the capability is reusable.

## Standalone use first; farm later

This runner should make sense without any slot farm:

1. choose a local MetaMask Mobile or Extension checkout;
2. run `metamask-recipe <platform> prepare --target <checkout> ...`;
3. run `metamask-recipe <platform> status` or `runtime-health`;
4. run `metamask-recipe <platform> run <recipe.json> --artifacts-dir <dir>`.

Skills are optional workflow wrappers around that same CLI. A wrapper may resolve
the runner source and package evidence, but it should dispatch `install`,
`launch`, `live`, `verify`, and `cleanup` to this repo or to the installed
harness helper. It should not carry Mobile or Extension adapter scripts.

Farm/slot orchestration belongs one layer outside this runner. It can scale the
standalone loop by choosing checkouts, machines, ports, simulators, and agents,
but it should not change the runner contract or copy runner implementation.
