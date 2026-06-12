# Changelog

## Unreleased

## 0.1.3 - 2026-06-13

- Add the headless `core` adapter for MetaMask core e2e (HyperLiquid perps testnet, gated mainnet support): `core` action manifest, live adapter, core recipes, and recipe-harness install/cleanup scripts. Mainnet writes require both `node.network: "mainnet"` and `CORE_PERPS_ALLOW_MAINNET_WRITES=1`.
- Improve handling of stale Metro listeners and session management.
- Clarify runner/runtime boundaries and centralize runtime helpers in the runner.
- Note: the 0.1.2 npm artifact was packed before the core adapter landed and lacks `manifests/core.action-manifest.json`; 0.1.3 republishes current main.

## 0.1.2 - 2026-06-10

- Declare `ui.key_press` for Mobile and Extension recipe manifests so trusted keyboard input recipes validate against the runner action manifest.

## 0.1.1 - 2026-06-06

- Harden harness setup so fallback installs are more reliable when the local skill installer is unavailable.
- Configure npm scope/cache settings for reproducible package installs and publishes.
- Prepare pilot npm distribution as `@deeeed/metamask-recipe-runner`; intended to migrate to org ownership if ADR-58 is accepted.
- Add `mm-recipe` and `mme-recipe` human-friendly wrappers for Mobile and Extension recipe control.
- Keep `metamask-recipe` as the single package bin; `mm-recipe` and `mme-recipe` are repo/local convenience wrappers.
- Improve Extension Perps order placement by resolving market price from background market data, stream cache, or visible UI before submitting.
