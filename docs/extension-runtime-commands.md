# Extension runtime commands

The runner is the source of truth for MetaMask Extension harness injection,
readiness decisions, extension-id resolution, and live CDP health checks.

## Prepare

```bash
metamask-recipe extension prepare --target <repo> [--cdp-port <port>] [--runtime-dir temp/recipe/runtime]
```

Installs the Extension harness under `temp/recipe/harness/extension/`. With
`--cdp-port`, it also runs a live health probe.

## Runtime status

```bash
metamask-recipe extension runtime-status --target <repo> [--cdp-port <port>] [--json]
```

Writes a structured status payload to stdout and
`temp/recipe/runtime/runtime-status.json`. Hosts should poll this JSON instead
of parsing logs. The payload includes fixture presence and the resolved fixture
path so hosts can surface missing setup before launching Chrome.

## Launch runtime

```bash
metamask-recipe runtime-launch --adapter extension --target <repo> --cdp-port <port> [--json]
metamask-recipe runtime-launch --adapter extension --target <repo> --cdp-port <port> --start-watch [--json]
```

Launches Chrome with the installed harness helper, seeds the wallet fixture, and
runs live smoke verification. `--start-watch` is the clean-build path: it clears
the webpack cache, starts the harness-owned watcher, waits for a clean compile,
then launches and verifies the runtime.

## Decide readiness

```bash
metamask-recipe extension decision --target <repo> [--cdp-port <port>] [--json]
# equivalent typed form:
metamask-recipe runtime-decision --adapter extension --target <repo> [--cdp-port <port>] [--json]
```

Returns the cheapest next action: `install`, `build`, `relaunch`, or `ready`.
Hosts should branch on `.decision` and execute the returned `actions[]`.

## Ensure ready

```bash
metamask-recipe extension ready --target <repo> --cdp-port <port> [--json]
# equivalent typed form:
metamask-recipe ensure-ready --adapter extension --target <repo> --cdp-port <port> [--json]
```

Converges the live browser to one healthy `home.html` tab and verifies with
`runtime-health`.

## Health

```bash
metamask-recipe extension status --target <repo> --cdp-port <port> [--json]
# equivalent typed form:
metamask-recipe runtime-health --adapter extension --target <repo> --cdp-port <port> [--json]
```

Read-only liveness probe for the running extension.

## Extension id

```bash
metamask-recipe resolve-extension --adapter extension --target <repo> [--cdp-port <port>] [--json]
```

Resolves the deterministic unpacked extension id from `dist/chrome/manifest.json`
and optionally verifies it against CDP.
