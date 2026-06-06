#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const runnerDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const protocolRoot = resolveProtocolRoot();

linkPackage('@farmslot/protocol', path.join(protocolRoot, 'packages/protocol'));
linkPackage('@farmslot/recipe-harness', path.join(protocolRoot, 'packages/recipe-harness'));

const nodeTypes = path.join(protocolRoot, 'node_modules/@types/node');
if (fs.existsSync(nodeTypes)) {
  linkPackage('@types/node', nodeTypes);
}

console.log(`Dev-linked local protocol/runtime packages from ${protocolRoot}`);

function resolveProtocolRoot() {
  const candidates = [
    process.env.FARMSLOT_ROOT,
    path.resolve(runnerDir, '../../farmslot'),
    path.resolve(runnerDir, '../farmslot'),
    path.resolve(process.cwd(), '../farmslot'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (isProtocolRoot(candidate)) return candidate;
  }
  throw new Error(
    'Unable to find local protocol/runtime root. Set FARMSLOT_ROOT=/path/to/protocol-checkout and rerun npm run dev:link-farmslot.',
  );
}

function isProtocolRoot(candidate) {
  return (
    fs.existsSync(path.join(candidate, 'packages/protocol/package.json')) &&
    fs.existsSync(path.join(candidate, 'packages/recipe-harness/package.json'))
  );
}

function linkPackage(name, target) {
  if (!fs.existsSync(target)) throw new Error(`Cannot link missing package target: ${target}`);
  const destination = path.join(runnerDir, 'node_modules', ...name.split('/'));
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.rmSync(destination, { recursive: true, force: true });
  fs.symlinkSync(target, destination, 'dir');
  console.log(`${name} -> ${target}`);
}
