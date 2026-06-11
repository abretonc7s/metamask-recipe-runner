import {
  getCoreController,
  isDirectRun,
  redactOrder,
  runAdapter,
  selectedItems,
} from './_controller.mjs';

// core Assert selected live Perps open orders are present or absent. Pure read
// over the controller's standalone getOpenOrders path (no signer / provider init
// needed) — throws on mismatch so the recipe fails loudly. Mirrors
// assert_positions.mjs.

export function expectedOpen(input) {
  const state = String(input.node?.state ?? input.node?.order ?? 'open').toLowerCase();
  if (state === 'open' || state === 'present') return true;
  if (state === 'none' || state === 'closed' || state === 'absent') return false;
  throw new Error(`metamask.perps.assert_orders received unsupported state: ${state}`);
}

export async function assertOrders(input, expectOpen = expectedOpen(input)) {
  const { controller, accountAddress, network } = await getCoreController(input);
  const orders = await controller.getOpenOrders({
    standalone: true,
    userAddress: accountAddress,
  });
  const matching = selectedItems(input, orders);
  const hasOrder = matching.length > 0;

  if (expectOpen && !hasOrder) {
    throw new Error(
      `Expected selected Perps open order(s), but none matched ${JSON.stringify(input.node)}.`,
    );
  }
  if (!expectOpen && hasOrder) {
    throw new Error(
      `Expected no selected Perps open orders, but ${matching.length} matched ${JSON.stringify(input.node)}.`,
    );
  }

  return {
    action: input.action,
    source: 'perps-controller-standalone',
    network,
    account: accountAddress,
    expectedOpen: expectOpen,
    matchingCount: matching.length,
    orders: matching.map(redactOrder),
    proofPath: 'perps-controller-getOpenOrders',
  };
}

if (isDirectRun(import.meta.url)) runAdapter((input) => assertOrders(input));
