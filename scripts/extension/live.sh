#!/usr/bin/env bash
echo "deprecated: scripts/extension/live.sh moved to orchestration/extension/live.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/extension/live.sh" "$@"
