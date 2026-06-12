#!/usr/bin/env bash
echo "deprecated: scripts/extension/launch.sh moved to orchestration/extension/launch.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/extension/launch.sh" "$@"
