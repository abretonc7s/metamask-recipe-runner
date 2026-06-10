# Package Boundaries

This package intentionally stays as **one npm package** with a clear internal
split. Splitting into two packages now would make users choose between packages
before the runtime API is stable. Instead, keep one install surface and separate
responsibilities inside the repo.

## Internal split

| Area | Owns | Does not own |
|---|---|---|
| Recipe layer | Action manifests, reusable recipes, typed runner binding, Mobile/Extension live adapters, proof semantics. | Starting Metro/Chrome, simulator boot, native builds, git cleanup. |
| Runtime lifecycle layer | Harness install/cleanup, Metro/dev-client launch, bundle prewarm, Chrome/CDP launch, fixture/profile setup, readiness gates. | Recipe graph execution, action vocabulary decisions, task-specific proof logic. |

## Stable command contract

Keep the public package simple:

```bash
metamask-recipe mobile prepare ...      # runtime lifecycle, then readiness proof
metamask-recipe extension prepare ...   # runtime lifecycle, then readiness proof
metamask-recipe run <recipe.json> ...   # recipe execution only
```

Wrappers such as skills or slot farms should call those commands. They should not
copy adapter scripts or reimplement Metro/Chrome launch behavior.

## Why not two packages yet?

A future split may be useful, for example:

- `@metamask/recipe-runner` for manifests/adapters/proof execution;
- `@metamask/recipe-runtime` for Mobile/Extension sandbox launch.

Do that only after the runtime CLI is stable and all wrappers call it. Until
then, two packages would likely increase confusion and version skew.

## Change discipline

1. Prefer moving behavior into the runner before changing farms/skills.
2. Keep compatibility wrappers when renaming files or commands.
3. Validate both paths after runtime changes:
   - direct runner/skill path;
   - Farmslot/Command Center prepare path.
4. Do not move files just for tidiness if callers still depend on old paths.
