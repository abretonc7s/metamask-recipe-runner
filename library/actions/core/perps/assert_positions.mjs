import {
  getCoreController,
  isDirectRun,
  redactPosition,
  runAdapter,
  selectedItems,
} from './_controller.mjs';

// core Assert selected live Perps positions are present or absent. Pure read
// over the controller's standalone path (no signer / provider init needed) —
// throws on mismatch so the recipe fails loudly.

export function expectedOpen(input) {
  const state = String(input.node?.state ?? input.node?.position ?? 'open').toLowerCase();
  if (state === 'open' || state === 'present') return true;
  if (state === 'none' || state === 'closed' || state === 'absent') return false;
  throw new Error(`metamask.perps.assert_positions received unsupported state: ${state}`);
}

export async function assertPositions(input, expectOpen = expectedOpen(input)) {
  const { controller, accountAddress, network } = await getCoreController(input);
  const positions = await controller.getPositions({
    standalone: true,
    userAddress: accountAddress,
  });
  const matching = selectedItems(input, positions);
  const hasPosition = matching.length > 0;

  if (expectOpen && !hasPosition) {
    throw new Error(
      `Expected selected Perps position(s), but none matched ${JSON.stringify(input.node)}.`,
    );
  }
  if (!expectOpen && hasPosition) {
    throw new Error(
      `Expected no selected Perps positions, but ${matching.length} matched ${JSON.stringify(input.node)}.`,
    );
  }

  return {
    action: input.action,
    source: 'perps-controller-standalone',
    network,
    account: accountAddress,
    expectedOpen: expectOpen,
    matchingCount: matching.length,
    positions: matching.map(redactPosition),
    proofPath: 'perps-controller-getPositions',
  };
}

if (isDirectRun(import.meta.url)) runAdapter((input) => assertPositions(input));
