#!/usr/bin/env bash

_harness_path_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
for _hp in "$_harness_path_dir/lib/harness-path.sh" "$_harness_path_dir/../../orchestration/lib/harness-path.sh" "$_harness_path_dir/../lib/harness-path.sh" "$_harness_path_dir/../../../scripts/lib/harness-path.sh"; do
  [ -f "$_hp" ] && { . "$_hp"; break; }
done
unset _hp _harness_path_dir
if ! command -v harness_root >/dev/null 2>&1; then
  echo "metamask-recipe: shared lib scripts/lib/harness-path.sh not found; reinstall the runner." >&2
  exit 1
fi
