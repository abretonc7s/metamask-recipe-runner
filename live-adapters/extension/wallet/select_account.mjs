import { runAdapter, withExtensionPage } from '../platform/cdp.mjs';

function normalize(value) {
  return String(value ?? '').toLowerCase();
}

runAdapter((input) => withExtensionPage(input, async (page) => {
  const requestedAddress = normalize(input.node?.address);
  const requestedId = input.node?.id ? String(input.node.id) : null;
  const requestedName = input.node?.name ? String(input.node.name) : null;
  if (!requestedAddress && !requestedId && !requestedName) {
    throw new Error('metamask.wallet.select_account extension live adapter requires node.address, node.id, or node.name.');
  }
  const selected = await page.evaluate(`(async () => {
    const hooks = globalThis.stateHooks;
    const store = hooks && hooks.store;
    const request = hooks && hooks.submitRequestToBackground;
    if (!store || typeof store.getState !== 'function') throw new Error('stateHooks.store.getState is unavailable.');
    if (typeof request !== 'function') throw new Error('stateHooks.submitRequestToBackground is unavailable.');
    const state = store.getState() || {};
    const internal = state.metamask?.internalAccounts || {};
    const accounts = internal.accounts || {};
    const requestedAddress = ${JSON.stringify(requestedAddress)};
    const requestedId = ${JSON.stringify(requestedId)};
    const requestedName = ${JSON.stringify(requestedName)};
    const entries = Object.entries(accounts);
    const match = entries.find(([id, account]) => {
      const metadata = account?.metadata || {};
      return (requestedId && id === requestedId) ||
        (requestedAddress && String(account?.address || '').toLowerCase() === requestedAddress) ||
        (requestedName && metadata.name === requestedName);
    });
    if (!match) throw new Error('Requested account was not found in internalAccounts.');
    const [id, account] = match;
    await request('setSelectedInternalAccount', [id]);
    const after = store.getState()?.metamask?.internalAccounts || {};
    const selectedId = after.selectedAccount;
    const selected = after.accounts?.[selectedId];
    if (selectedId !== id) throw new Error('Expected selected account ' + id + ', got ' + selectedId);
    return {
      id: selectedId,
      address: selected?.address || null,
      name: selected?.metadata?.name || null,
      type: selected?.type || null
    };
  })()`, { awaitPromise: true });
  return { action: input.action, selected, proofPath: 'extension-account-selection' };
}));
