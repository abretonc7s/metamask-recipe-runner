#!/usr/bin/env bash
# cleanup.sh — remove the headless `core` adapter overlay.
# (formerly: scripts/cleanup-core-harness.sh)
#
# Inputs: --target <metamask-core> (default $PWD); env RECIPE_HARNESS_ROOT.
# Outputs: removes <harness>/core. Exit 0 — cleaned (idempotent); 2 — bad args.
# Never touches: product files (core install patches nothing).
#
# Core injects nothing into the product checkout, so cleanup only removes the
# ignored overlay directory temp/recipe/harness/core. There are no backups to
# restore and no patched product files. Idempotent: a missing overlay is a
# success, not an error.
set -euo pipefail

TARGET="$PWD"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    -h|--help) echo "Usage: cleanup.sh (core) [--target <metamask-core>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "$TARGET" && pwd)"
# shellcheck disable=SC1091
for _hp in "$SCRIPT_DIR/../lib/harness-path.sh"; do
  [ -f "$_hp" ] && { . "$_hp"; break; }
done
unset _hp
if ! command -v harness_root >/dev/null 2>&1; then
  echo "metamask-recipe: shared lib orchestration/lib/harness-path.sh not found; reinstall the runner." >&2
  exit 1
fi
HARNESS_DIR="$(harness_dir "$TARGET" core)"

rm -rf "$HARNESS_DIR"
echo "Cleaned core recipe harness from $TARGET"
