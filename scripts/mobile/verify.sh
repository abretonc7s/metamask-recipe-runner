#!/usr/bin/env bash
echo "deprecated: scripts/mobile/verify.sh moved to recipe/mobile/verify.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/recipe/mobile/verify.sh" "$@"
