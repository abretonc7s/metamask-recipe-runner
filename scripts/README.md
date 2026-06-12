# Deprecated forwarding shims

Real code lives in `recipe/`, `orchestration/`, and `library/`. Every script
here forwards to its new home (one deprecation line on stderr, then exec).
Removed once external consumers migrate.
