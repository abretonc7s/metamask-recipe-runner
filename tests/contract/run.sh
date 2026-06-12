#!/bin/bash
# run.sh — contract test runner
#
# Purpose:
#   Discovers and runs every tests/contract/*.test.sh in sequence.
#   One test file per feature; a failing test fails the whole run.
#
# Inputs:
#   $1 (optional) — glob filter, e.g. `bash tests/contract/run.sh mobile-launch`
#
# Outputs:
#   Per-test PASS/FAIL lines on stdout; summary line at the end.
#   Exit 0 — all tests passed; exit 1 — at least one failure or no tests matched.
#
# Never touches: anything outside $TMPDIR test sandboxes.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

pass=0
fail=0
failed_names=()

for test_file in "$HERE"/*.test.sh; do
  [ -e "$test_file" ] || continue
  name="$(basename "$test_file" .test.sh)"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
    continue
  fi
  out="$(bash "$test_file" 2>&1)"
  code=$?
  if [ "$code" -eq 0 ]; then
    echo "PASS ${name}"
    pass=$((pass + 1))
  else
    echo "FAIL ${name} (exit ${code})"
    echo "$out" | sed 's/^/  | /'
    fail=$((fail + 1))
    failed_names+=("$name")
  fi
done

total=$((pass + fail))
if [ "$total" -eq 0 ]; then
  echo "no contract tests matched" >&2
  exit 1
fi
echo "contract: ${pass}/${total} passed"
if [ "$fail" -gt 0 ]; then
  echo "failed: ${failed_names[*]}" >&2
  exit 1
fi
