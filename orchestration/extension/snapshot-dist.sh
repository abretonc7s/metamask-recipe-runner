#!/usr/bin/env bash
# snapshot-dist.sh — runtime-dist snapshot with git-id freshness guard
# (formerly: the dist wait/rsync/guard parts of the prepare_parts
# mega-string in scripts/extension/live.sh)
#
# Purpose:
#   Snapshots dist/chrome into a per-run runtime-dist so Chrome's loaded
#   extension can't be ripped out mid-rebuild, then verifies the snapshot's
#   "from git id:" matches the source dist (catches mid-rebuild copies).
#
# Inputs (flags):
#   --dist <dir>           source dist (required, e.g. <repo>/dist/chrome)
#   --runtime-dist <dir>   snapshot destination (required, recreated)
#   --wait-iterations <n>  manifest wait loop length, 2s each (default 180)
#   --summary <file>       optional standard summary.json
#
# Outputs:
#   <runtime-dist>/ snapshot (excludes _metadata); optional --summary file
#   {feature,status,inputs,outputs,generatedAt}.
#   Exit 0 — snapshot fresh; 1 — manifest never appeared, rsync failed, or
#   git-id mismatch (mid-rebuild); 2 — bad args.
#
# Never touches: the source dist (read-only); anything outside
# --runtime-dist and --summary.
set -euo pipefail

DIST=""
RUNTIME_DIST=""
WAIT_ITERATIONS=180
SUMMARY=""
require_value() { [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dist) require_value "$@"; DIST="$2"; shift 2 ;;
    --runtime-dist) require_value "$@"; RUNTIME_DIST="$2"; shift 2 ;;
    --wait-iterations) require_value "$@"; WAIT_ITERATIONS="$2"; shift 2 ;;
    --summary) require_value "$@"; SUMMARY="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: snapshot-dist.sh --dist <dir> --runtime-dist <dir> [--wait-iterations <n>] [--summary <file>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$DIST" ] || { echo "Missing --dist" >&2; exit 2; }
[ -n "$RUNTIME_DIST" ] || { echo "Missing --runtime-dist" >&2; exit 2; }
case "$WAIT_ITERATIONS" in ''|*[!0-9]*) echo "Invalid --wait-iterations (must be numeric): $WAIT_ITERATIONS" >&2; exit 2 ;; esac

status=fail
finish() {
  if [ -n "$SUMMARY" ]; then
    mkdir -p "$(dirname "$SUMMARY")"
    STATUS_FOR_SUMMARY="$status" DIST_FOR_SUMMARY="$DIST" RUNTIME_DIST_FOR_SUMMARY="$RUNTIME_DIST" SUMMARY_PATH="$SUMMARY" node <<'NODE' || true
const fs = require('fs');
fs.writeFileSync(process.env.SUMMARY_PATH, `${JSON.stringify({
  feature: 'extension/snapshot-dist',
  status: process.env.STATUS_FOR_SUMMARY,
  inputs: { dist: process.env.DIST_FOR_SUMMARY },
  outputs: { runtimeDist: process.env.RUNTIME_DIST_FOR_SUMMARY },
  generatedAt: new Date().toISOString(),
}, null, 2)}\n`);
NODE
  fi
}
trap finish EXIT

for i in $(seq 1 "$WAIT_ITERATIONS"); do
  [ -f "$DIST/manifest.json" ] && break
  sleep 2
done
test -f "$DIST/manifest.json" || { echo "snapshot-dist: no manifest at $DIST/manifest.json" >&2; exit 1; }

rm -rf "$RUNTIME_DIST" && mkdir -p "$RUNTIME_DIST" \
  && rsync -a --delete --exclude _metadata "$DIST/" "$RUNTIME_DIST/" || exit 1

# Freshness guard: the loaded runtime-dist must match dist/chrome's git id. A
# mismatch means the rsync caught a mid-rebuild dist; abort rather than load
# an inconsistent bundle (the "Element type is invalid: undefined" class of crash).
node -e 'const fs=require("fs");const id=p=>{try{return (JSON.parse(fs.readFileSync(p,"utf8")).description||"").match(/from git id: *([0-9a-f]+)/i)?.[1]||""}catch{return""}};const [distManifest,runtimeManifest]=process.argv.slice(-2);const d=id(distManifest),r=id(runtimeManifest);if(d&&d!==r){console.error("runtime-dist git id "+r+" != dist "+d+" (mid-rebuild?); aborting");process.exit(1)}' "$DIST/manifest.json" "$RUNTIME_DIST/manifest.json" || exit 1
status=pass
