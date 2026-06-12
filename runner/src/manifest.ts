import path from 'node:path';

import type { RecipeActionManifestDocument, RecipeValidationResult } from '@farmslot/protocol';

import { manifestPath, readJson, importRecipeProtocol } from './paths.ts';
import type { MetaMaskRecipeAdapter } from './types.ts';

export function loadMetaMaskMobileActionManifest(): RecipeActionManifestDocument {
  return asActionManifest(readJson(manifestPath('mobile')));
}

export function loadMetaMaskExtensionActionManifest(): RecipeActionManifestDocument {
  return asActionManifest(readJson(manifestPath('extension')));
}

export function loadMetaMaskCoreActionManifest(): RecipeActionManifestDocument {
  return asActionManifest(readJson(manifestPath('core')));
}

export function loadActionManifest(
  adapter: MetaMaskRecipeAdapter,
  overridePath?: string,
): RecipeActionManifestDocument {
  if (overridePath) return asActionManifest(readJson(path.resolve(overridePath)));
  if (adapter === 'mobile') return loadMetaMaskMobileActionManifest();
  if (adapter === 'core') return loadMetaMaskCoreActionManifest();
  return loadMetaMaskExtensionActionManifest();
}

export async function validateManifest(
  manifest: RecipeActionManifestDocument,
): Promise<RecipeValidationResult> {
  const { validateRecipeActionManifestDocument } = await importRecipeProtocol();
  const result = validateRecipeActionManifestDocument(manifest);
  if (result.status === 'invalid') {
    throw new Error(
      `Manifest invalid: ${result.findings
        .map((finding) => `${finding.code} ${finding.path}`)
        .join(', ')}`,
    );
  }
  return result;
}

function asActionManifest(value: unknown): RecipeActionManifestDocument {
  return value as RecipeActionManifestDocument;
}
