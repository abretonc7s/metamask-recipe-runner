#!/usr/bin/env bash
echo "deprecated: scripts/inject-mobile-harness.sh moved to orchestration/mobile/inject-mobile-harness.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/orchestration/mobile/inject-mobile-harness.sh" "$@"
