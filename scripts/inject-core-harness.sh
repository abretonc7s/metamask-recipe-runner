#!/usr/bin/env bash
echo "deprecated: scripts/inject-core-harness.sh moved to orchestration/core/inject.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/orchestration/core/inject.sh" "$@"
