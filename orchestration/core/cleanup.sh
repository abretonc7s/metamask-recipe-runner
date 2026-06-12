#!/usr/bin/env bash
# cleanup-core-harness.sh — remove the headless `core` adapter overlay.
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
    -h|--help) echo "Usage: cleanup-core-harness.sh [--target <metamask-core>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "$TARGET" && pwd)"
# shellcheck disable=SC1091
for _hp in "$SCRIPT_DIR/lib/harness-path.sh"; do
  [ -f "$_hp" ] && { . "$_hp"; break; }
done
unset _hp
if ! command -v harness_root >/dev/null 2>&1; then
  echo "metamask-recipe: shared lib scripts/lib/harness-path.sh not found; reinstall the runner." >&2
  exit 1
fi
HARNESS_DIR="$(harness_dir "$TARGET" core)"

rm -rf "$HARNESS_DIR"
echo "Cleaned core recipe harness from $TARGET"
