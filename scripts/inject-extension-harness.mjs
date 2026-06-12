#!/usr/bin/env node
console.error('deprecated: scripts/inject-extension-harness.mjs moved to orchestration/extension/inject.mjs');
await import('../orchestration/extension/inject.mjs');
