echo "deprecated: scripts/lib/harness-path.sh moved to orchestration/lib/harness-path.sh" >&2
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/lib/harness-path.sh"
