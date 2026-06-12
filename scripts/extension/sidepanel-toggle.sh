#!/usr/bin/env bash
echo "deprecated: scripts/extension/sidepanel-toggle.sh moved to recipe/extension/sidepanel-toggle.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/recipe/extension/sidepanel-toggle.sh" "$@"
