import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const defaultsPath = path.join(path.dirname(fileURLToPath(import.meta.url)), 'path-defaults.json');
const defaults = JSON.parse(fs.readFileSync(defaultsPath, 'utf8'));

export const DEFAULT_RECIPE_HARNESS_ROOT = defaults.recipeHarnessRoot;
export const DEFAULT_RECIPE_RUNTIME_DIR = defaults.recipeRuntimeDir;

export function validateRelativeRecipePath(name, value) {
  if (!value || path.isAbsolute(value)) throw new Error(`${name} must be a non-empty relative path: ${value}`);
  if (!/^[A-Za-z0-9._/-]+$/u.test(value)) throw new Error(`${name} contains unsupported characters: ${value}`);
  for (const part of value.split('/')) {
    if (!part || part === '.' || part === '..') throw new Error(`${name} contains unsafe path component: ${value}`);
  }
  return value;
}

export function recipeHarnessRoot(env = process.env) {
  return validateRelativeRecipePath('RECIPE_HARNESS_ROOT', env.RECIPE_HARNESS_ROOT || DEFAULT_RECIPE_HARNESS_ROOT);
}

export function recipeRuntimeDir(env = process.env) {
  return validateRelativeRecipePath('RECIPE_RUNTIME_DIR', env.RECIPE_RUNTIME_DIR || DEFAULT_RECIPE_RUNTIME_DIR);
}
