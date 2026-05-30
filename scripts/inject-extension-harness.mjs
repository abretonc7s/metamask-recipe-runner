#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';

const target = path.resolve(process.argv[2] ?? process.cwd());
const outputDir = path.join(target, '.agent/recipe-harness/extension');
await mkdir(outputDir, { recursive: true });

const runnerRoot = path.resolve(import.meta.dirname, '..');
const runnerRef = spawnSync('git', ['-C', runnerRoot, 'rev-parse', 'HEAD'], {
  encoding: 'utf8',
});

const provenance = {
  schemaVersion: 1,
  kind: 'metamask-extension-recipe-harness-injection',
  installedAt: new Date().toISOString(),
  target,
  runner: {
    source: runnerRoot,
    git_ref: runnerRef.status === 0 ? runnerRef.stdout.trim() : null,
  },
  harness: {
    marker: '.agent/recipe-harness/extension/provenance.json',
    runtime: 'chrome-extension-cdp',
  },
};

await writeFile(path.join(outputDir, 'provenance.json'), `${JSON.stringify(provenance, null, 2)}\n`);
console.log(JSON.stringify({ status: 'pass', outputDir, provenance }, null, 2));
