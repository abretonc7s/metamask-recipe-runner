# Dev tooling

Repo development tooling only (no runtime code, no shims):

- `check.mjs` — type-check + syntax + committed-recipe validation (`yarn check`)
- `link-local-farmslot.mjs` — co-develop against a local farmslot protocol checkout
- `validate-action-e2e-artifacts.mjs` — validate recorded action e2e artifacts

Runtime code lives in `recipe/`, `orchestration/`, and `library/`.
