#!/usr/bin/env node
console.error('deprecated: scripts/cleanup-extension-harness.mjs moved to orchestration/extension/cleanup.mjs');
await import('../orchestration/extension/cleanup.mjs');
