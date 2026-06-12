import { runAdapter, withExtensionPage } from '../platform/cdp.mjs';

runAdapter((input) => withExtensionPage(input, async (page) => {
  const state = await page.evaluate(`(() => {
    const hooks = globalThis.stateHooks;
    const store = hooks && hooks.store;
    const root = store && typeof store.getState === 'function' ? store.getState() : {};
    const metamask = root.metamask || {};
    const internal = metamask.internalAccounts || {};
    const accounts = internal.accounts || {};
    const selectedId = internal.selectedAccount || null;
    const selected = selectedId && accounts[selectedId] ? accounts[selectedId] : null;
    const metadata = selected && selected.metadata ? selected.metadata : {};
    return {
      href: String(globalThis.location && globalThis.location.href || ''),
      selectedAccount: selected ? {
        id: selectedId,
        address: selected.address || null,
        name: metadata.name || null,
        type: selected.type || null
      } : null,
      completedOnboarding: Boolean(metamask.completedOnboarding),
      selectedNetworkClientId: metamask.selectedNetworkClientId || null
    };
  })()`);
  return { action: input.action, source: 'extension-stateHooks-store', state, redacted: true, proofPath: 'extension-wallet-state' };
}));
