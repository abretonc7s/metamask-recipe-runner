import type { RecipeActionManifestDocument } from '@farmslot/protocol';
import type { ActionAdapter, RecipeRunner } from '@farmslot/recipe-harness';

import { createMetaMaskAdapters, createMetaMaskUiTransport } from './adapters.ts';
import { loadMetaMaskExtensionActionManifest, loadMetaMaskMobileActionManifest } from './manifest.ts';
import { importFarmslotHarness } from './paths.ts';
import type { CreateMetaMaskRunnerOptions, MetaMaskRecipeAdapter } from './types.ts';

export async function createMetaMaskMobileRunner(
  options: CreateMetaMaskRunnerOptions = {},
): Promise<RecipeRunner> {
  return createMetaMaskRunner(
    'mobile',
    options.actionManifest ?? loadMetaMaskMobileActionManifest(),
  );
}

export async function createMetaMaskExtensionRunner(
  options: CreateMetaMaskRunnerOptions = {},
): Promise<RecipeRunner> {
  return createMetaMaskRunner(
    'extension',
    options.actionManifest ?? loadMetaMaskExtensionActionManifest(),
  );
}

export async function createMetaMaskRunner(
  adapter: MetaMaskRecipeAdapter,
  actionManifest: RecipeActionManifestDocument,
): Promise<RecipeRunner> {
  const {
    createRecipeRunner,
    createStandardCoreAdapters,
    createStandardUiAdapters,
    createCdpWebUiTransport,
    createReactNativeCdpBridgeUiTransport,
  } = await importFarmslotHarness();
  const actions = [
    ...actionManifest.supported_official_actions,
    ...(actionManifest.custom_actions ?? []).map((entry: { name: string }) => entry.name),
  ];
  const declaredActions = new Set(actions);
  const core = createStandardCoreAdapters({ actions });
  const projectOwnedOfficialActions = new Set(['app.status']);
  const ui = createStandardUiAdapters({
    actions: actions.filter((action) => !projectOwnedOfficialActions.has(action)),
    transport: createMetaMaskUiTransport(adapter, {
      createCdpWebUiTransport,
      createReactNativeCdpBridgeUiTransport,
    }),
  });
  const existing = new Set([...core, ...ui].map((entry) => entry.action));
  const custom: ActionAdapter[] = createMetaMaskAdapters(adapter).filter(
    (entry) => declaredActions.has(entry.action) && !existing.has(entry.action),
  );
  const autoHudDisabled = process.env.METAMASK_RECIPE_AUTO_HUD === '0' || process.env.METAMASK_RECIPE_AUTO_HUD === 'false';
  return createRecipeRunner({
    actionManifest,
    adapters: [...core, ...ui, ...custom],
    logger: console,
    hud: autoHudDisabled
      ? false
      : {
          enabled: true,
          display: {
            layout: 'docked-bottom',
            position: 'bottom',
            showTitle: false,
            showDebug: false,
            maxDetailLines: 2,
          },
        },
  });
}
