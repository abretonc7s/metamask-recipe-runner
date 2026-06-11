import type { RecipeActionManifestDocument, RecipeValidationResult } from '@farmslot/protocol';

export type MetaMaskRecipeAdapter = 'mobile' | 'extension' | 'core';

export interface CreateMetaMaskRunnerOptions {
  actionManifest?: RecipeActionManifestDocument;
}

export type RecipeHarnessModule = typeof import('@farmslot/recipe-harness');
export type RecipeHarnessBrowserExtensionModule = typeof import('@farmslot/recipe-harness/runtime/browser-extension');
export type RecipeHarnessCdpModule = typeof import('@farmslot/recipe-harness/runtime/cdp');
export type RecipeHarnessReactNativeBridgeModule = typeof import('@farmslot/recipe-harness/runtime/react-native-bridge');
export type RecipeProtocolModule = typeof import('@farmslot/protocol');

export interface MetaMaskDoctorReport {
  schemaVersion: 1;
  protocolVersion: 'v1';
  runner_protocol_version: 1;
  status: 'pass' | 'fail';
  checks: Array<{ id: string; status: 'pass' | 'fail'; message: string }>;
  adapter: MetaMaskRecipeAdapter;
  target: string;
  compatibilityMode:
    | 'bridge present'
    | 'injected bridge present'
    | 'bridge injectable'
    | 'product-local harness present'
    | 'runner bridge with injected app bridge'
    | 'runner bridge with app bridge'
    | 'runner bridge available; app bridge not installed'
    | 'headless controller (no bridge)'
    | 'unsupported/no bridge';
  runner: {
    name: '@metamask/recipe-runner';
    runnerDir: string;
    actionManifestPath: string;
    harnessPackage: '@farmslot/recipe-harness';
  };
  shape: Record<string, unknown>;
  fixture: Record<string, unknown>;
  manifestValidation: RecipeValidationResult['summary'] | Record<string, unknown>;
}
