import { runAdapter, withExtensionPage } from '../platform/cdp.mjs';

runAdapter((input) => withExtensionPage(input, async (page) => {
  const state = await page.evaluate(`(() => {
    const passwordInput = Boolean(document.querySelector('input[type="password"]'));
    const hooks = globalThis.stateHooks;
    const store = hooks && hooks.store;
    const root = store && typeof store.getState === 'function' ? store.getState() : {};
    const metamask = root.metamask || {};
    const internal = metamask.internalAccounts || {};
    const accounts = internal.accounts || {};
    const selectedId = internal.selectedAccount || null;
    const selected = selectedId && accounts[selectedId] ? accounts[selectedId] : null;
    return {
      href: String(globalThis.location && globalThis.location.href || ''),
      passwordInput,
      completedOnboarding: Boolean(metamask.completedOnboarding),
      selectedAccount: selected ? {
        id: selectedId,
        address: selected.address || null,
      } : null,
    };
  })()`);
  const seededProfilePresent = Boolean(state?.passwordInput || (state?.completedOnboarding && state?.selectedAccount?.address));
  if (!seededProfilePresent) {
    throw new Error(`Extension fixture profile is not ready; expected a locked password screen or completed onboarding with a selected account, got ${JSON.stringify(state)}`);
  }
  return {
    action: input.action,
    setup: 'preseeded-profile-verified',
    targetUrl: page.target.url,
    runtimeState: state,
    proofPath: 'extension-fixture-profile',
  };
}));
