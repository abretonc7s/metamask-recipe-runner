# Compatibility overlays (historical-commit replay)

NOT dead code. These overlays exist for replay/eval runs against OLD product
commits — e.g. re-running a historical task on a fixed baseline to validate
prompt or harness changes. A "zero current references" scan will always come
up empty here by design: the feature's purpose is non-current checkouts.

- Purpose: make historical product checkouts bootable/bridgeable under the
  current local toolchain so Recipe v1 evals can replay against them.
- When it applies: mobile checkouts predating React Native 0.81 polyfill
  fixes (see mobile/README.md for the per-patch details).
- How it is applied: MANUALLY (no automatic apply logic in this repo).
  The operator or the `/recipe-harness` skill applies the patch reversibly
  before a historical rebuild (`git apply <patch>` in the product checkout,
  `git apply -R` to remove) and records the overlay path in validation
  evidence. `orchestration/mobile/inject.sh` does NOT apply these.

Listed in orchestration/manifest.json (kind: compat-overlay) so the doctor
verifies the surface and this directory is never flagged as unused again.
