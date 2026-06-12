import {
  getCoreController,
  redactPosition,
  runAdapter,
  selectedItems,
} from './_controller.mjs';

export async function readPositions(input) {
  const { controller, accountAddress, network } = await getCoreController(input);
  const positions = await controller.getPositions({
    standalone: true,
    userAddress: accountAddress,
  });
  const matching = selectedItems(input, positions);
  return {
    action: input.action,
    source: 'perps-controller-standalone',
    network,
    account: accountAddress,
    count: positions.length,
    matchingCount: matching.length,
    positions: matching.map(redactPosition),
    proofPath: 'perps-controller-getPositions',
  };
}

runAdapter(readPositions);
