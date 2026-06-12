#!/usr/bin/env bash
echo "deprecated: scripts/cleanup-mobile-harness.sh moved to orchestration/mobile/cleanup-mobile-harness.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/orchestration/mobile/cleanup-mobile-harness.sh" "$@"
