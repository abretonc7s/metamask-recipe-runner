import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import type { FarmslotHarnessModule, FarmslotProtocolModule, MetaMaskRecipeAdapter } from './types.ts';

export const runnerDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const farmslotRoot = resolveFarmslotRoot();

function resolveFarmslotRoot() {
  const candidates = [
    process.env.FARMSLOT_ROOT,
    readConfiguredFarmslotRoot(),
    findFarmslotRoot(runnerDir),
    findFarmslotRoot(process.cwd()),
  ].filter(Boolean);
  const root = candidates[0];
  if (!root) {
    throw new Error(
      'MetaMask recipe runner requires Farmslot. Set FARMSLOT_ROOT or install through /recipe-harness so runner/.farmslot-root is configured.',
    );
  }
  return path.resolve(root);
}

function readConfiguredFarmslotRoot() {
  const configPath = path.join(runnerDir, '.farmslot-root');
  if (!fs.existsSync(configPath)) return undefined;
  const value = fs.readFileSync(configPath, 'utf8').trim();
  return value || undefined;
}

function findFarmslotRoot(start) {
  let dir = path.resolve(start);
  while (dir !== path.dirname(dir)) {
    if (
      fs.existsSync(path.join(dir, 'packages/recipe-harness/package.json')) &&
      fs.existsSync(path.join(dir, 'packages/protocol/package.json'))
    ) {
      return dir;
    }
    const sibling = path.join(dir, 'farmslot');
    if (
      fs.existsSync(path.join(sibling, 'packages/recipe-harness/package.json')) &&
      fs.existsSync(path.join(sibling, 'packages/protocol/package.json'))
    ) {
      return sibling;
    }
    dir = path.dirname(dir);
  }
  return undefined;
}

export function assertAdapter(adapter: unknown): asserts adapter is MetaMaskRecipeAdapter {
  if (adapter !== 'mobile' && adapter !== 'extension') {
    throw new Error('Adapter must be mobile or extension.');
  }
}

export function manifestPath(adapter: MetaMaskRecipeAdapter) {
  assertAdapter(adapter);
  return path.join(runnerDir, 'manifests', `${adapter}.action-manifest.json`);
}

export function recipePath(name: string) {
  return path.join(runnerDir, 'recipes', name);
}

export function readJson(file: string): unknown {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

// The runner is intentionally usable as a standalone checkout while Farmslot is
// still local source. Import the canonical package names from the resolved
// Farmslot root instead of committing absolute or developer-specific paths.
export async function importFarmslotHarness(): Promise<FarmslotHarnessModule> {
  return import(
    pathToFileURL(path.join(farmslotRoot, 'packages/recipe-harness/src/index.ts')).href
  ) as Promise<FarmslotHarnessModule>;
}

export async function importFarmslotProtocol(): Promise<FarmslotProtocolModule> {
  return import(
    pathToFileURL(path.join(farmslotRoot, 'packages/protocol/src/index.ts')).href
  ) as Promise<FarmslotProtocolModule>;
}
