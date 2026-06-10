# Changelog

## Unreleased

## 0.1.2 - 2026-06-10

- Declare `ui.key_press` for Mobile and Extension recipe manifests so trusted keyboard input recipes validate against the runner action manifest.

## 0.1.1 - 2026-06-06

- Harden harness setup so fallback installs are more reliable when the local skill installer is unavailable.
- Configure npm scope/cache settings for reproducible package installs and publishes.
- Prepare pilot npm distribution as `@deeeed/metamask-recipe-runner`; intended to migrate to org ownership if ADR-58 is accepted.
- Add `mm-recipe` and `mme-recipe` human-friendly wrappers for Mobile and Extension recipe control.
- Keep `metamask-recipe` as the single package bin; `mm-recipe` and `mme-recipe` are repo/local convenience wrappers.
- Improve Extension Perps order placement by resolving market price from background market data, stream cache, or visible UI before submitting.
