import {
  getCoreControllerWithSigner,
  isDirectRun,
  redactOrder,
  runAdapter,
  selectedItems,
  symbolForItem,
} from './_controller.mjs';

// core Cancel selected live Perps open orders on HyperLiquid testnet by driving
// the headless PerpsController.cancelOrders() through the full signing/provider
// path (Slice 2). Mirrors close_positions.mjs: read open orders → cancel the
// selected subset via the controller → verify the selected orders are gone.
//
// cancelOrders() resolves the concrete orders to cancel via the ACTIVE provider's
// getOpenOrders() (PerpsController wires getOpenOrders: () => this.getOpenOrders()
// into the cancel context) and then batch-cancels by symbol. We pass the selected
// symbols; with mode=all (no explicit market) we cancel every open order.

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForOrdersAbsent(controller, accountAddress, symbols, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let orders = [];
  for (;;) {
    orders = await controller.getOpenOrders({
      standalone: true,
      userAddress: accountAddress,
    });
    const remaining = orders.filter((order) => symbols.includes(symbolForItem(order)));
    if (remaining.length === 0) return orders;
    if (Date.now() >= deadline) return orders;
    await sleep(1000);
  }
}

export async function closeOrders(input) {
  const { controller, accountAddress, network } = await getCoreControllerWithSigner(input);
  const timeoutMs = Number(input.node?.timeout_ms ?? 30000);

  const orders = await controller.getOpenOrders({
    standalone: true,
    userAddress: accountAddress,
  });
  const matching = selectedItems(input, orders);
  const symbols = Array.from(new Set(matching.map(symbolForItem)));

  if (symbols.length === 0) {
    return {
      action: input.action,
      source: 'perps-controller-cancelOrders',
      network,
      account: accountAddress,
      canceled: false,
      matchingCount: 0,
      symbols,
      reason: 'no matching open orders',
      proofPath: 'perps-controller-cancelOrders',
    };
  }

  // Cancel by the selected symbols. cancelOrders() filters the active provider's
  // open orders to these symbols and batch-cancels them on the exchange.
  const result = await controller.cancelOrders({ symbols });
  if (!result || result.success !== true) {
    throw new Error(
      `core cancelOrders failed for ${JSON.stringify(symbols)}: ${JSON.stringify(result)}`,
    );
  }

  const after = await waitForOrdersAbsent(controller, accountAddress, symbols, timeoutMs);
  const stillOpen = after.filter((order) => symbols.includes(symbolForItem(order)));
  if (stillOpen.length > 0) {
    throw new Error(
      `Expected selected orders to cancel, but ${stillOpen.length} remain: ${JSON.stringify(result)}`,
    );
  }

  return {
    action: input.action,
    source: 'perps-controller-cancelOrders',
    network,
    account: accountAddress,
    canceled: true,
    matchingCount: matching.length,
    successCount: result.successCount,
    failureCount: result.failureCount,
    symbols,
    results: result.results,
    orders: stillOpen.map(redactOrder),
    proofPath: 'perps-controller-cancelOrders',
  };
}

if (isDirectRun(import.meta.url)) runAdapter(closeOrders);
