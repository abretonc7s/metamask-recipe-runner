#!/usr/bin/env bash
echo "deprecated: scripts/extension/verify.sh moved to recipe/extension/verify.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/recipe/extension/verify.sh" "$@"
