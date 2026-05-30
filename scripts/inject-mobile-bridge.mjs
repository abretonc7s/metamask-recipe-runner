#!/usr/bin/env node
import { chmod, mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';

const target = path.resolve(process.argv[2] ?? process.cwd());
const productBridge = path.join(target, 'scripts/perps/agentic/cdp-bridge.js');
if (!existsSync(productBridge)) {
  throw new Error(`MetaMask Mobile product bridge is missing: ${productBridge}`);
}

const outputDir = path.join(target, '.agent/recipe-harness/mobile');
await mkdir(outputDir, { recursive: true });

const wrapper = `#!/usr/bin/env node
'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '../../..');
const productBridge = path.join(projectRoot, 'scripts/perps/agentic/cdp-bridge.js');
const result = spawnSync(process.execPath, [productBridge, ...process.argv.slice(2)], {
  cwd: projectRoot,
  env: process.env,
  stdio: 'inherit',
});
if (result.error) {
  throw result.error;
}
process.exit(result.status ?? 1);
`;

await writeFile(path.join(outputDir, 'cdp-bridge.js'), wrapper);
await chmod(path.join(outputDir, 'cdp-bridge.js'), 0o755);

const runnerRef = spawnSync('git', ['-C', path.resolve(import.meta.dirname, '..'), 'rev-parse', 'HEAD'], {
  encoding: 'utf8',
});
const provenance = {
  schemaVersion: 1,
  kind: 'metamask-mobile-recipe-harness-injection',
  installedAt: new Date().toISOString(),
  target,
  runner: {
    source: path.resolve(import.meta.dirname, '..'),
    git_ref: runnerRef.status === 0 ? runnerRef.stdout.trim() : null,
  },
  bridge: {
    wrapper: '.agent/recipe-harness/mobile/cdp-bridge.js',
    delegatesTo: 'scripts/perps/agentic/cdp-bridge.js',
  },
};
await writeFile(path.join(outputDir, 'provenance.json'), `${JSON.stringify(provenance, null, 2)}\n`);

console.log(JSON.stringify({ status: 'pass', outputDir, provenance }, null, 2));
