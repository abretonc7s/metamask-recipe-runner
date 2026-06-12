#!/bin/bash
# Contract test: orchestration/extension/refresh-build.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
ct_init

REFRESH="$CT_REPO_ROOT/orchestration/extension/refresh-build.sh"

# --help exits 0
ct_run 0 timeout 60 bash "$REFRESH" --help
ct_assert_contains "$CT_OUT" "Usage:"

# bad input fails with message (documented exit 1)
ct_run 1 timeout 60 bash "$REFRESH" --bogus
ct_assert_contains "$CT_OUT" "unknown arg"
ct_run 1 timeout 60 bash "$REFRESH"
ct_assert_contains "$CT_OUT" "--repo must point"

# Stub target: dist entries already on disk so the entry-wait loop is
# satisfied up front; stub `yarn` emits the clean marker then idles
# (the script kills it). ASDF_DATA_DIR points at an empty dir so the
# script cannot re-prepend real asdf shims over the stub.
ct_stub_extension_repo "$CT_TMP/repo"
mkdir -p "$CT_TMP/stubbin" "$CT_TMP/noasdf"
cat > "$CT_TMP/stubbin/yarn" <<SH
#!/bin/bash
printf '%s\n' "Finished 'clean'"
sleep 600
SH
chmod +x "$CT_TMP/stubbin/yarn"

ct_run 0 timeout 90 env PATH="$CT_TMP/stubbin:$PATH" ASDF_DATA_DIR="$CT_TMP/noasdf" \
  bash "$REFRESH" --repo "$CT_TMP/repo" --timeout 20 --clean-timeout 20
ct_assert_contains "$CT_OUT" "Build refreshed and frozen"

# build that dies before the clean pass exits 2
cat > "$CT_TMP/stubbin/yarn" <<SH
#!/bin/bash
exit 1
SH
chmod +x "$CT_TMP/stubbin/yarn"
ct_run 2 timeout 90 env PATH="$CT_TMP/stubbin:$PATH" ASDF_DATA_DIR="$CT_TMP/noasdf" \
  bash "$REFRESH" --repo "$CT_TMP/repo" --timeout 5 --clean-timeout 5
ct_assert_contains "$CT_OUT" "exited before clean pass"
