import {
  currentMarketPrice,
  getCoreControllerWithSigner,
  isDirectRun,
  redactPosition,
  runAdapter,
  selectedItems,
  symbolForItem,
} from './_controller.mjs';

// core Close selected live Perps positions on HyperLiquid testnet by driving the
// headless PerpsController.closePosition() per matching position (full close)
// through the full signing/provider path (Slice 2). Mirrors the extension
// adapter: read → close each matching position with a fresh price → verify the
// selected positions are gone.

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForPositionsAbsent(controller, accountAddress, symbols, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let positions = [];
  for (;;) {
    positions = await controller.getPositions({
      standalone: true,
      userAddress: accountAddress,
    });
    const remaining = positions.filter((position) =>
      symbols.includes(symbolForItem(position)),
    );
    if (remaining.length === 0) return positions;
    if (Date.now() >= deadline) return positions;
    await sleep(1000);
  }
}

export async function closePositions(input) {
  const { controller, accountAddress, network } = await getCoreControllerWithSigner(input);
  const timeoutMs = Number(input.node?.timeout_ms ?? 30000);
  const maxSlippageBps = Number(
    input.node?.max_slippage_bps ?? input.node?.maxSlippageBps ?? 300,
  );

  const positions = await controller.getPositions({
    standalone: true,
    userAddress: accountAddress,
  });
  const matching = selectedItems(input, positions);
  const symbols = Array.from(new Set(matching.map(symbolForItem)));

  if (symbols.length === 0) {
    return {
      action: input.action,
      source: 'perps-controller-closePosition',
      network,
      account: accountAddress,
      closed: false,
      matchingCount: 0,
      symbols,
      reason: 'no matching open positions',
      proofPath: 'perps-controller-closePosition',
    };
  }

  const results = [];
  let successCount = 0;
  for (const position of matching) {
    const symbol = symbolForItem(position);
    const currentPrice = await currentMarketPrice(controller, symbol);
    // Full close: omit size so the provider closes 100% of the position. Pass
    // live position + fresh price so the provider skips a REST refetch and the
    // slippage guard has a current anchor.
    const result = await controller.closePosition({
      symbol,
      orderType: 'market',
      currentPrice,
      priceAtCalculation: currentPrice,
      maxSlippageBps,
      position,
    });
    const success = result?.success === true;
    results.push({ symbol, success, currentPrice, result });
    if (success) successCount += 1;
  }

  // A wholesale close failure must surface even if a read race shows the
  // positions absent — mirrors close_orders, which throws on success !== true.
  if (matching.length > 0 && successCount === 0) {
    throw new Error(
      `All ${matching.length} closePosition call(s) reported failure (successCount=0): ${JSON.stringify(results)}`,
    );
  }

  const after = await waitForPositionsAbsent(controller, accountAddress, symbols, timeoutMs);
  const stillOpen = after.filter((position) => symbols.includes(symbolForItem(position)));
  if (stillOpen.length > 0) {
    throw new Error(
      `Expected selected positions to close, but ${stillOpen.length} remain: ${JSON.stringify(results)}`,
    );
  }

  return {
    action: input.action,
    source: 'perps-controller-closePosition',
    network,
    account: accountAddress,
    closed: true,
    matchingCount: matching.length,
    successCount,
    symbols,
    results,
    positions: stillOpen.map(redactPosition),
    proofPath: 'perps-controller-closePosition',
  };
}

if (isDirectRun(import.meta.url)) runAdapter(closePositions);
