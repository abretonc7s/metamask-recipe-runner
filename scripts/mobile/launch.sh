#!/usr/bin/env bash
echo "deprecated: scripts/mobile/launch.sh moved to orchestration/mobile/launch.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/mobile/launch.sh" "$@"
