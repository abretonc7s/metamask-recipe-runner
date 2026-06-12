#!/usr/bin/env bash
echo "deprecated: scripts/mobile/live.sh moved to orchestration/mobile/live.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/mobile/live.sh" "$@"
