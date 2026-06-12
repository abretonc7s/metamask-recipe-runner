# harness-path.sh — shared, configurable recipe-harness injection root.
# Sourced (not executed) by both adapters and wrappers so every host uses one
# definition. Override RECIPE_HARNESS_ROOT (relative to the target repo);
# defaults to the path in path-defaults.json (under the gitignored temp/, so installs
# need no extra git-exclude).
#
# An empty/unset value falls back to the default; a set value is validated
# (relative, safe charset, no '.'/'..' components) so a hostile/typo'd value
# can't make install/cleanup write or rm -rf outside the target, and is safe to
# embed in shell/JSON without quoting surprises.
# Returns non-zero on an invalid value; callers run under `set -e`.
_recipe_path_defaults_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/path-defaults.json"

_recipe_path_default() {
  local key="$1"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_recipe_path_defaults_file" | head -1
}

harness_root() {
  local root="${RECIPE_HARNESS_ROOT:-$(_recipe_path_default recipeHarnessRoot)}"
  case "$root" in
    ""|/*) echo "RECIPE_HARNESS_ROOT must be a non-empty relative path: '$root'" >&2; return 1 ;;
    *[!A-Za-z0-9._/-]*) echo "RECIPE_HARNESS_ROOT may only contain A-Za-z0-9 and . _ / - : '$root'" >&2; return 1 ;;
  esac
  local IFS=/ part
  for part in $root; do
    case "$part" in
      .|..) echo "RECIPE_HARNESS_ROOT must not contain '.' or '..' path components: '$root'" >&2; return 1 ;;
    esac
  done
  printf '%s' "$root"
}

# harness_dir <target> [adapter] -> absolute install dir for the adapter.
harness_dir() {
  printf '%s/%s/%s' "$1" "$(harness_root)" "${2:-extension}"
}


# recipe_runtime_dir -> relative runtime state dir for recipe-local config/secrets.
# Override RECIPE_RUNTIME_DIR (relative to target repo); default lives in path-defaults.json.
recipe_runtime_dir() {
  local root="${RECIPE_RUNTIME_DIR:-$(_recipe_path_default recipeRuntimeDir)}"
  case "$root" in
    ""|/*) echo "RECIPE_RUNTIME_DIR must be a non-empty relative path: '$root'" >&2; return 1 ;;
    *[!A-Za-z0-9._/-]*) echo "RECIPE_RUNTIME_DIR may only contain A-Za-z0-9 and . _ / - : '$root'" >&2; return 1 ;;
  esac
  local IFS=/ part
  for part in $root; do
    case "$part" in
      .|..) echo "RECIPE_RUNTIME_DIR must not contain '.' or '..' path components: '$root'" >&2; return 1 ;;
    esac
  done
  printf '%s' "$root"
}
