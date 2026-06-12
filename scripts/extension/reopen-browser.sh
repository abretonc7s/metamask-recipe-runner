#!/bin/bash
echo "deprecated: scripts/extension/reopen-browser.sh moved to orchestration/extension/ensure-browser.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/extension/ensure-browser.sh" "$@"
