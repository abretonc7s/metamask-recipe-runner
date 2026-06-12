# Runtime File Conventions

This runner uses a small set of file extensions on purpose. The goal is to keep
MetaMask-specific logic easy to run from either a source checkout or a published
package without requiring target app builds to transpile runner code.

## Extension rules

- `src/**/*.ts` — typed runner core: CLI parsing, manifests, adapter binding,
  runtime decisions, and shared helper logic.
- `library/actions/**/*.mjs` and `scripts/**/*.mjs` — standalone ESM modules that
  Node executes directly with no build step. Use these for action adapters and
  small injected/runtime helpers.
- `*.cjs` — compatibility islands only. Keep these quarantined for helper code
  that intentionally needs CommonJS semantics, such as portable `require()`
  execution from shell scripts or bridge code shared with older runtime contexts.
- `*.sh` — thin OS/device orchestration wrappers for tools such as `simctl`,
  `adb`, Chrome launch, tmux, and filesystem setup. Do not put recipe graph
  execution or MetaMask domain semantics in shell.
- Plain source `*.js` is not allowed. With `"type": "module"`, `.js` would be
  ESM, but it is visually ambiguous in this runner. Use `.mjs` for direct Node
  scripts or `.ts` for typed core code.

## Design intent

The mix is intentional only when the boundary is clear:

1. TypeScript owns maintainable product/runner decisions.
2. ESM scripts own no-build runtime adapters and injected helpers.
3. CommonJS stays isolated where the runtime context makes ESM brittle.
4. Shell stays at the edge for host/device commands.

If a file crosses those boundaries, move the logic inward: shell should call a
Node module, standalone `.mjs` should become typed `src/**/*.ts` when it grows
shared domain logic, and new compatibility needs should be documented before
adding another `.cjs` file.
