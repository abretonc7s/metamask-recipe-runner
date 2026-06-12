#!/usr/bin/env bash
echo "deprecated: scripts/cleanup-core-harness.sh moved to orchestration/core/cleanup.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/orchestration/core/cleanup.sh" "$@"
