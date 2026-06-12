#!/usr/bin/env node
console.error('deprecated: scripts/cleanup-extension-harness.mjs moved to orchestration/extension/cleanup-extension-harness.mjs');
await import('../orchestration/extension/cleanup-extension-harness.mjs');
