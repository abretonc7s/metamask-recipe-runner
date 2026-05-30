#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const runnerDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const farmslotRoot = findFarmslotRoot(runnerDir) ?? findFarmslotRoot(process.cwd());
if (!farmslotRoot) {
  throw new Error('Unable to find Farmslot root for TypeScript check. Set FARMSLOT_ROOT or run near the Farmslot checkout.');
}
const tsc = path.join(farmslotRoot, 'node_modules/typescript/bin/tsc');
if (!fs.existsSync(tsc)) throw new Error(`TypeScript compiler not found at ${tsc}`);
const generatedTsconfig = path.join(runnerDir, '.tmp', 'tsconfig.check.json');
fs.mkdirSync(path.dirname(generatedTsconfig), { recursive: true });
fs.writeFileSync(
  generatedTsconfig,
  `${JSON.stringify(
    {
      extends: '../tsconfig.json',
      compilerOptions: {
        baseUrl: '..',
        types: ['node'],
        typeRoots: [path.relative(path.dirname(generatedTsconfig), path.join(farmslotRoot, 'node_modules/@types'))],
        paths: {
          '@farmslot/protocol': [
            path.relative(runnerDir, path.join(farmslotRoot, 'packages/protocol/src/index.ts')),
          ],
          '@farmslot/recipe-harness': [
            path.relative(
              runnerDir,
              path.join(farmslotRoot, 'packages/recipe-harness/src/index.ts'),
            ),
          ],
        },
      },
    },
    null,
    2,
  )}\n`,
);
run(process.execPath, [
  tsc,
  '--noEmit',
  '--project',
  generatedTsconfig,
]);
for (const file of listFiles(runnerDir, (name) => name.endsWith('.mjs'))) {
  run(process.execPath, ['--check', file]);
}

function run(command, args) {
  const result = spawnSync(command, args, { stdio: 'inherit', cwd: runnerDir, env: process.env });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function findFarmslotRoot(start) {
  const candidates = [process.env.FARMSLOT_ROOT, start].filter(Boolean);
  for (const candidate of candidates) {
    let dir = path.resolve(candidate);
    while (dir !== path.dirname(dir)) {
      if (isFarmslotRoot(dir)) return dir;
      const sibling = path.join(dir, 'farmslot');
      if (isFarmslotRoot(sibling)) return sibling;
      dir = path.dirname(dir);
    }
  }
  return null;
}

function isFarmslotRoot(dir) {
  return fs.existsSync(path.join(dir, 'packages/recipe-harness/package.json')) && fs.existsSync(path.join(dir, 'packages/protocol/package.json'));
}

function listFiles(root, predicate) {
  const out = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (entry.name === '.git' || entry.name === 'node_modules') continue;
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) out.push(...listFiles(full, predicate));
    else if (entry.isFile() && predicate(entry.name)) out.push(full);
  }
  return out;
}
