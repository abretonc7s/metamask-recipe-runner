#!/bin/bash
echo "deprecated: scripts/extension/refresh-build.sh moved to orchestration/extension/refresh-build.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/extension/refresh-build.sh" "$@"
