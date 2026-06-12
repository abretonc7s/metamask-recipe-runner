import { bridgeCommand, evalAsync, runAdapter } from '../platform/bridge.mjs';

runAdapter(async (input) => {
  const requestedAddress = input.node?.address ? String(input.node.address).toLowerCase() : null;
  const requestedId = input.node?.id ? String(input.node.id) : null;
  const requestedName = input.node?.name ? String(input.node.name) : null;
  if (!requestedAddress && !requestedId && !requestedName) {
    throw new Error('metamask.wallet.select_account mobile live adapter requires node.address, node.id, or node.name.');
  }
  const accounts = await bridgeCommand(input, ['list-accounts']);
  if (!Array.isArray(accounts)) {
    throw new Error(`metamask.wallet.select_account expected list-accounts to return an array, got ${typeof accounts}.`);
  }
  const match = accounts.find((account) => {
    const address = String(account?.address ?? '').toLowerCase();
    const id = String(account?.id ?? '');
    const name = String(account?.name ?? '');
    return (requestedAddress && address === requestedAddress) ||
      (requestedId && id === requestedId) ||
      (requestedName && name === requestedName);
  });
  if (!match?.address) {
    throw new Error(`Requested mobile account was not found in list-accounts: ${JSON.stringify({ address: requestedAddress, id: requestedId, name: requestedName })}`);
  }
  const result = await bridgeCommand(input, ['switch-account', String(match.address)]);
  const perps = await evalAsync(
    input,
    `(async function(){
      var controller = Engine.context.PerpsController;
      if (!controller) return JSON.stringify({ skipped: true, reason: 'PerpsController unavailable' });
      if (typeof controller.disconnect === 'function') await controller.disconnect();
      if (typeof controller.init === 'function') await controller.init();
      var positions = typeof controller.getPositions === 'function' ? await controller.getPositions() : [];
      var account = typeof controller.getAccountState === 'function' ? await controller.getAccountState() : null;
      return JSON.stringify({ reinitialized: true, positions: positions.length, withdrawableBalance: account && account.withdrawableBalance });
    })()`,
  );
  return {
    action: input.action,
    selected: {
      address: result.address,
      id: result.id,
      name: result.name,
    },
    perps,
    proofPath: 'agentic-account-selection',
  };
});
