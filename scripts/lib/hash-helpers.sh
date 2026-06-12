echo "deprecated: scripts/lib/hash-helpers.sh moved to orchestration/lib/hash-helpers.sh" >&2
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/orchestration/lib/hash-helpers.sh"
