import {
  getCoreController,
  redactOrder,
  runAdapter,
  selectedItems,
} from './_controller.mjs';

export async function readOrders(input) {
  const { controller, accountAddress, network } = await getCoreController(input);
  const orders = await controller.getOpenOrders({
    standalone: true,
    userAddress: accountAddress,
  });
  const matching = selectedItems(input, orders);
  return {
    action: input.action,
    source: 'perps-controller-standalone',
    network,
    account: accountAddress,
    count: orders.length,
    matchingCount: matching.length,
    orders: matching.map(redactOrder),
    proofPath: 'perps-controller-getOpenOrders',
  };
}

runAdapter(readOrders);
