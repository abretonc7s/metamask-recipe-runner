#!/usr/bin/env bash
# inject.sh — headless `core` adapter install.
#
# Inputs: --target <metamask-core> (default $PWD); env RECIPE_HARNESS_ROOT,
#   METAMASK_RUNNER_PROTOCOL_ROOT > FARMSLOT_ROOT > <runner>/.farmslot-root.
# Outputs: <harness>/core/{manifest.json,action-manifest.json,runner/}.
#   Exit 0 — installed; 1 — symlink refusal/install failure; 2 — bad args.
# Never touches: product checkout source (overlay metadata only).
#
# Core is a headless adapter: it instantiates @metamask/perps-controller against
# a resolved MetaMask/core checkout and reads/writes HyperLiquid testnet over
# HTTP. There is no app, CDP target, bridge, or UI. Unlike the mobile/extension
# installs this writes NOTHING into the product checkout source: it only creates
# the ignored harness overlay under temp/recipe/harness/core with a delegate
# wrapper, the action manifests, recipe snapshots, and install metadata.
set -euo pipefail

TARGET="$PWD"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    -h|--help) echo "Usage: inject.sh (core) [--target <metamask-core>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
# shellcheck disable=SC1091
for _hp in "$SCRIPT_DIR/../lib/harness-path.sh"; do
  [ -f "$_hp" ] && { . "$_hp"; break; }
done
unset _hp
if ! command -v harness_root >/dev/null 2>&1; then
  echo "metamask-recipe: shared lib orchestration/lib/harness-path.sh not found; reinstall the runner." >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
METAMASK_RUNNER_DIR="$RUNNER_DIR"
METAMASK_RUNNER_SOURCE_KIND="runner-self"
METAMASK_RUNNER_REVISION="$(git -C "$RUNNER_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
METAMASK_RUNNER_PROTOCOL_ROOT="${METAMASK_RUNNER_PROTOCOL_ROOT:-${METAMASK_RUNNER_FARMSLOT_ROOT:-${FARMSLOT_ROOT:-}}}"
if [ -z "$METAMASK_RUNNER_PROTOCOL_ROOT" ] && [ -f "$RUNNER_DIR/.farmslot-root" ]; then
  METAMASK_RUNNER_PROTOCOL_ROOT="$(cat "$RUNNER_DIR/.farmslot-root")"
fi
export METAMASK_RUNNER_DIR METAMASK_RUNNER_SOURCE_KIND METAMASK_RUNNER_REVISION METAMASK_RUNNER_PROTOCOL_ROOT
HARNESS_ROOT="$(harness_root)"
HARNESS_REL="$HARNESS_ROOT/core"
HARNESS_DIR="$(harness_dir "$TARGET" core)"

refuse_symlink_destination() {
  local rel="$1"
  local path_so_far="$TARGET"
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    path_so_far="$path_so_far/$part"
    if [ -L "$path_so_far" ]; then
      echo "Refusing core recipe harness install: $rel contains symlink component $path_so_far." >&2
      return 1
    fi
  done
}

install_v1_runner_assets() {
  # refuse_symlink_destination walks every path component, so the deepest paths
  # also guard their parents ($HARNESS_REL covers the root segments).
  refuse_symlink_destination "$HARNESS_REL"
  refuse_symlink_destination "$HARNESS_REL/runner"
  refuse_symlink_destination "$HARNESS_REL/action-manifest.json"
  mkdir -p "$HARNESS_DIR"
  rm -rf "$HARNESS_DIR/runner"
  mkdir -p "$HARNESS_DIR/runner/bin" "$HARNESS_DIR/runner/manifests" "$HARNESS_DIR/runner/recipes"

  # Install a harness-owned delegate that execs the reviewed external runner
  # source recorded in manifest.json. The delegate keeps the overlay lightweight
  # and never owns the runtime itself. Core is headless: no app, no .js.env, no
  # simulator detection — the delegate only forwards FARMSLOT_ROOT (when set) and
  # execs the real runner. Emit shell-safe lines: %q-quote the interpolated paths
  # so a protocol/runner path containing a space — or $()/backtick/quote — cannot
  # break the generated wrapper or inject at runtime.
  local runner_protocol_root_q runner_exec_q
  runner_protocol_root_q="$(printf '%q' "$METAMASK_RUNNER_PROTOCOL_ROOT")"
  runner_exec_q="$(printf '%q' "$METAMASK_RUNNER_DIR/bin/metamask-recipe")"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    if [ -n "$METAMASK_RUNNER_PROTOCOL_ROOT" ]; then
      printf 'export FARMSLOT_ROOT=${FARMSLOT_ROOT:-%s}\n' "$runner_protocol_root_q"
    fi
    printf 'exec %s "$@"\n' "$runner_exec_q"
  } > "$HARNESS_DIR/runner/bin/metamask-recipe"
  chmod +x "$HARNESS_DIR/runner/bin/metamask-recipe"
  if [ -n "$METAMASK_RUNNER_PROTOCOL_ROOT" ]; then
    printf '%s\n' "$METAMASK_RUNNER_PROTOCOL_ROOT" > "$HARNESS_DIR/runner/.farmslot-root"
  fi
  printf '%s\n' "$METAMASK_RUNNER_DIR" > "$HARNESS_DIR/runner/.runner-source"
  # resolve-runner-source.sh requires mobile + extension manifests to consider a
  # runner valid, so the installed delegate must carry them alongside core's.
  cp "$METAMASK_RUNNER_DIR/library/manifests/core.action-manifest.json" "$HARNESS_DIR/action-manifest.json"
  cp "$METAMASK_RUNNER_DIR/library/manifests/core.action-manifest.json" "$HARNESS_DIR/runner/manifests/core.action-manifest.json"
  cp "$METAMASK_RUNNER_DIR/library/manifests/mobile.action-manifest.json" "$HARNESS_DIR/runner/manifests/mobile.action-manifest.json"
  cp "$METAMASK_RUNNER_DIR/library/manifests/extension.action-manifest.json" "$HARNESS_DIR/runner/manifests/extension.action-manifest.json"
  if [ -d "$METAMASK_RUNNER_DIR/library/recipes" ]; then
    rsync -a --delete "$METAMASK_RUNNER_DIR/library/recipes/" "$HARNESS_DIR/runner/recipes/"
  fi
  if [ ! -x "$HARNESS_DIR/runner/bin/metamask-recipe" ]; then
    echo "Refusing core recipe harness install: failed to make runner executable." >&2
    return 1
  fi
}

install_v1_runner_assets

SOURCE_REV="$(git -C "$RUNNER_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
CLEANUP_COMMAND="RECIPE_HARNESS_ROOT=$HARNESS_ROOT $(printf '%q' "$SCRIPT_DIR/cleanup.sh") --target $(printf '%q' "$TARGET")"
node -e '
  const fs = require("fs");
  const [runnerDir, runnerRevision, runnerSourceKind, target, manifestPath, harnessRel, cleanupCommand] = process.argv.slice(1);
  const m = {
    adapter: "core",
    installedAt: new Date().toISOString(),
    source: {
      runnerDir,
      runnerRevision,
      runnerSourceKind,
    },
    target,
    protocolVersion: "v1",
    actionManifestPath: harnessRel + "/action-manifest.json",
    runnerEntrypoint: harnessRel + "/runner/bin/metamask-recipe",
    runtimeHelpers: {},
    installedPaths: [harnessRel + "/runner"],
    patchedFiles: [],
    cleanupCommand,
  };
  fs.writeFileSync(manifestPath, JSON.stringify(m, null, 2) + "\n");
' "$METAMASK_RUNNER_DIR" "$METAMASK_RUNNER_REVISION" "$METAMASK_RUNNER_SOURCE_KIND" "$TARGET" "$HARNESS_DIR/manifest.json" "$HARNESS_REL" "$CLEANUP_COMMAND"

echo "Installed core recipe harness: $HARNESS_DIR/manifest.json"
