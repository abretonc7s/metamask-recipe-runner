import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import type {
  RecipeHarnessBrowserExtensionModule,
  RecipeHarnessCdpModule,
  RecipeHarnessModule,
  RecipeHarnessReactNativeBridgeModule,
  RecipeProtocolModule,
  MetaMaskRecipeAdapter,
} from './types.ts';

export const runnerDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const pathDefaults = readPathDefaults();
export const DEFAULT_RECIPE_RUNTIME_DIR = pathDefaults.recipeRuntimeDir;
export const DEFAULT_RECIPE_HARNESS_ROOT = pathDefaults.recipeHarnessRoot;

export function recipeRuntimeDir() {
  return validateRelativeRecipePath('RECIPE_RUNTIME_DIR', process.env.RECIPE_RUNTIME_DIR || DEFAULT_RECIPE_RUNTIME_DIR);
}

export function recipeHarnessRoot() {
  return validateRelativeRecipePath('RECIPE_HARNESS_ROOT', process.env.RECIPE_HARNESS_ROOT || DEFAULT_RECIPE_HARNESS_ROOT);
}


function readPathDefaults(): { recipeRuntimeDir: string; recipeHarnessRoot: string } {
  const defaultsPath = path.join(runnerDir, 'orchestration/lib/path-defaults.json');
  const parsed = JSON.parse(fs.readFileSync(defaultsPath, 'utf8')) as Partial<{ recipeRuntimeDir: string; recipeHarnessRoot: string }>;
  return {
    recipeRuntimeDir: validateRelativeRecipePath('recipeRuntimeDir', parsed.recipeRuntimeDir || ''),
    recipeHarnessRoot: validateRelativeRecipePath('recipeHarnessRoot', parsed.recipeHarnessRoot || ''),
  };
}

function validateRelativeRecipePath(name: string, value: string): string {
  if (!value || path.isAbsolute(value)) throw new Error(`${name} must be a non-empty relative path: ${value}`);
  if (!/^[A-Za-z0-9._/-]+$/u.test(value)) throw new Error(`${name} contains unsupported characters: ${value}`);
  for (const part of value.split('/')) {
    if (!part || part === '.' || part === '..') throw new Error(`${name} contains unsafe path component: ${value}`);
  }
  return value;
}

export function recipeRuntimePath(projectRoot: string, ...segments: string[]) {
  return path.join(projectRoot, recipeRuntimeDir(), ...segments);
}

export function recipeHarnessPath(projectRoot: string, ...segments: string[]) {
  return path.join(projectRoot, recipeHarnessRoot(), ...segments);
}

export function walletFixturePath(projectRoot: string) {
  return recipeRuntimePath(projectRoot, 'wallet-fixture.json');
}

export function extensionIdPath(projectRoot: string) {
  return recipeRuntimePath(projectRoot, 'extension.id');
}

export function recipeWatchLogCandidates() {
  return [
    path.join(recipeRuntimeDir(), 'webpack.log'),
    path.join(recipeRuntimeDir(), 'recipe-harness-webpack.log'),
  ];
}

export function resolveLocalProtocolRoot() {
  const candidates = [
    process.env.FARMSLOT_ROOT,
    readConfiguredProtocolRoot(),
    findProtocolRoot(runnerDir),
    findProtocolRoot(process.cwd()),
  ].filter(Boolean);
  const root = candidates[0];
  return root ? path.resolve(root) : undefined;
}

export function resolveRequiredLocalProtocolRoot(reason: string) {
  const root = resolveLocalProtocolRoot();
  if (!root) {
    throw new Error(
      `${reason} requires a local protocol/runtime checkout. Set FARMSLOT_ROOT or create .farmslot-root for this dev-only path.`,
    );
  }
  return root;
}

function readConfiguredProtocolRoot() {
  const configPath = path.join(runnerDir, '.farmslot-root');
  if (!fs.existsSync(configPath)) return undefined;
  const value = fs.readFileSync(configPath, 'utf8').trim();
  return value || undefined;
}

function findProtocolRoot(start) {
  let dir = path.resolve(start);
  while (dir !== path.dirname(dir)) {
    if (isProtocolRoot(dir)) return dir;
    const sibling = path.join(dir, 'farmslot');
    if (isProtocolRoot(sibling)) return sibling;
    dir = path.dirname(dir);
  }
  return undefined;
}

function isProtocolRoot(candidate) {
  return (
    fs.existsSync(path.join(candidate, 'packages/recipe-harness/package.json')) &&
    fs.existsSync(path.join(candidate, 'packages/protocol/package.json'))
  );
}

export function assertAdapter(adapter: unknown): asserts adapter is MetaMaskRecipeAdapter {
  if (adapter !== 'mobile' && adapter !== 'extension' && adapter !== 'core') {
    throw new Error('Adapter must be mobile, extension, or core.');
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

export async function importRecipeHarness(): Promise<RecipeHarnessModule> {
  return importProtocolPackage(
    '@farmslot/recipe-harness',
    'packages/recipe-harness/src/index.ts',
  ) as Promise<RecipeHarnessModule>;
}

export async function importRecipeHarnessRuntimeCdp(): Promise<RecipeHarnessCdpModule> {
  return importProtocolPackage(
    '@farmslot/recipe-harness/runtime/cdp',
    'packages/recipe-harness/src/runtime/cdp.ts',
  ) as Promise<RecipeHarnessCdpModule>;
}

export async function importRecipeHarnessRuntimeBrowserExtension(): Promise<RecipeHarnessBrowserExtensionModule> {
  return importProtocolPackage(
    '@farmslot/recipe-harness/runtime/browser-extension',
    'packages/recipe-harness/src/runtime/browser-extension.ts',
  ) as Promise<RecipeHarnessBrowserExtensionModule>;
}

export async function importRecipeHarnessRuntimeReactNativeBridge(): Promise<RecipeHarnessReactNativeBridgeModule> {
  return importProtocolPackage(
    '@farmslot/recipe-harness/runtime/react-native-bridge',
    'packages/recipe-harness/src/runtime/react-native-bridge.ts',
  ) as Promise<RecipeHarnessReactNativeBridgeModule>;
}

export async function importRecipeProtocol(): Promise<RecipeProtocolModule> {
  return importProtocolPackage(
    '@farmslot/protocol',
    'packages/protocol/src/index.ts',
  ) as Promise<RecipeProtocolModule>;
}

async function importProtocolPackage(packageName: string, localSourceEntry: string) {
  try {
    return await import(packageName);
  } catch (error) {
    if (!isMissingPackageError(error, packageName)) throw error;
  }

  const root = resolveLocalProtocolRoot();
  if (!root) {
    throw new Error(
      `${packageName} is not installed. Install @farmslot/* packages normally, or set FARMSLOT_ROOT/use npm run dev:link-farmslot while co-developing protocol packages locally.`,
    );
  }
  return import(pathToFileURL(path.join(root, localSourceEntry)).href);
}

function isMissingPackageError(error: unknown, packageName: string) {
  if (!(error instanceof Error)) return false;
  const code = (error as NodeJS.ErrnoException).code;
  return code === 'ERR_MODULE_NOT_FOUND' && error.message.includes(packageName);
}
