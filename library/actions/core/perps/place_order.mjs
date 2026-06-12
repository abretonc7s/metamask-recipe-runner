import {
  configuredSymbols,
  currentMarketPrice,
  getCoreControllerWithSigner,
  isDirectRun,
  redactOrder,
  redactPosition,
  runAdapter,
  selectedItems,
} from './_controller.mjs';

// core Place a real Perps order on HyperLiquid testnet by driving the headless
// PerpsController.placeOrder() through the full signing/provider path (Slice 2).
// Mirrors the extension adapter's input vocabulary and notional→size math:
//   size = (usdAmount * leverage) / currentPrice
// The HyperLiquidProvider recalculates size from usdAmount internally; we still
// pass a derived size for the controller's own validation, plus currentPrice/
// priceAtCalculation so the provider's slippage guard has a fresh anchor.
//
// LIMIT orders (orderType=limit) place a RESTING order on the book instead of
// filling: the provider sends tif=Gtc and uses the provided `price` verbatim
// (calculateOrderPriceAndSize / buildOrdersArray in core's orderCalculations.ts).
// The limit price is derived from the live mid by `offset_pct` (e.g. -30 places a
// BUY 30% below mid that will NOT fill), or supplied absolutely via `limit_price`.
// For a limit order we size from the LIMIT price (not mid) and omit usdAmount so
// the controller uses our explicit size verbatim — that guarantees the
// on-exchange notional (size * limitPrice) clears HyperLiquid's ~$10 minimum even
// though the limit sits far from mid. After placing we verify the resting open
// order exists (not a filled position).

function resolveSymbol(input) {
  const symbols = configuredSymbols(input, []);
  if (symbols.length !== 1) {
    throw new Error(
      `metamask.perps.place_order requires exactly one market; got ${JSON.stringify(symbols)}.`,
    );
  }
  return symbols[0];
}

function resolveOrderType(input) {
  const raw = String(
    input.node?.order_type ?? input.node?.orderType ?? 'market',
  ).toLowerCase();
  if (raw !== 'market' && raw !== 'limit') {
    throw new Error(`metamask.perps.place_order received unsupported order_type: ${raw}.`);
  }
  return raw;
}

/**
 * Resolve the resting limit price for a limit order.
 * Precedence: explicit absolute `limit_price` → `offset_pct` from mid.
 * A BUY uses a negative offset (below mid) to rest; a SELL a positive offset.
 * Defaults to a -30% (buy) / +30% (sell) offset so the order will not fill.
 *
 * @param input - Adapter input (node.limit_price / node.offset_pct).
 * @param isBuy - Order direction.
 * @param mid - Current mid price.
 */
function resolveLimitPrice(input, isBuy, mid) {
  const absolute = input.node?.limit_price ?? input.node?.limitPrice ?? input.node?.price;
  if (absolute !== undefined && absolute !== null && String(absolute).length > 0) {
    const numeric = Number(absolute);
    if (!Number.isFinite(numeric) || numeric <= 0) {
      throw new Error(`metamask.perps.place_order received invalid limit_price: ${absolute}.`);
    }
    return numeric;
  }
  const rawOffset = input.node?.offset_pct ?? input.node?.offsetPct;
  // Default far-from-mid offset so the resting order does not fill.
  const offsetPct = rawOffset === undefined || rawOffset === null ? (isBuy ? -30 : 30) : Number(rawOffset);
  if (!Number.isFinite(offsetPct)) {
    throw new Error(`metamask.perps.place_order received invalid offset_pct: ${rawOffset}.`);
  }
  const price = mid * (1 + offsetPct / 100);
  if (!Number.isFinite(price) || price <= 0) {
    throw new Error(`metamask.perps.place_order computed a non-positive limit price (${price}).`);
  }
  return price;
}

export async function placeOrder(input) {
  const { controller, accountAddress, network } = await getCoreControllerWithSigner(input);
  const symbol = resolveSymbol(input);
  const side = String(input.node?.side ?? 'long').toLowerCase();
  const isBuy = side !== 'short';
  const orderType = resolveOrderType(input);
  const usdAmount = String(input.node?.amount ?? input.node?.notional ?? '11');
  const leverage = Number(input.node?.leverage ?? 3);
  const maxSlippageBps = Number(
    input.node?.max_slippage_bps ?? input.node?.maxSlippageBps ?? 300,
  );

  const usdNumeric = Number(usdAmount);
  if (!Number.isFinite(usdNumeric) || usdNumeric <= 0) {
    throw new Error(`metamask.perps.place_order received invalid notional: ${usdAmount}.`);
  }
  if (!Number.isFinite(leverage) || leverage <= 0) {
    throw new Error(`metamask.perps.place_order received invalid leverage: ${leverage}.`);
  }

  const currentPrice = await currentMarketPrice(controller, symbol);

  let orderParams;
  let limitPrice = null;
  if (orderType === 'limit') {
    limitPrice = resolveLimitPrice(input, isBuy, currentPrice);
    // Size from the LIMIT price so size * limitPrice clears HL's ~$10 minimum;
    // omit usdAmount so the controller does NOT recompute size from mid.
    const size = ((usdNumeric * leverage) / limitPrice).toString();
    orderParams = {
      symbol,
      isBuy,
      size,
      orderType: 'limit',
      price: String(limitPrice),
      timeInForce: 'GTC',
      leverage,
      currentPrice,
      priceAtCalculation: currentPrice,
      maxSlippageBps,
    };
  } else {
    const size = ((usdNumeric * leverage) / currentPrice).toString();
    orderParams = {
      symbol,
      isBuy,
      size,
      orderType: 'market',
      leverage,
      usdAmount,
      currentPrice,
      priceAtCalculation: currentPrice,
      maxSlippageBps,
    };
  }

  const result = await controller.placeOrder(orderParams);
  if (!result || result.success !== true) {
    throw new Error(
      `core placeOrder failed for ${symbol} (${orderType}): ${result?.error ?? 'unknown error'} (currentPrice=${currentPrice}${limitPrice ? `, limitPrice=${limitPrice}` : ''}).`,
    );
  }

  // For limit orders, confirm a RESTING open order exists (not a filled position);
  // for market orders, confirm the position opened. Both read the real
  // provider/exchange state (not the submit ack) before reporting success.
  let openOrders = [];
  let positions = [];
  if (orderType === 'limit') {
    openOrders = await controller.getOpenOrders({
      standalone: true,
      userAddress: accountAddress,
    });
  } else {
    positions = await controller.getPositions({
      standalone: true,
      userAddress: accountAddress,
    });
  }
  const matchingOrders = selectedItems(input, openOrders);
  const matchingPositions = selectedItems(input, positions);

  if (orderType === 'limit' && matchingOrders.length === 0) {
    throw new Error(
      `core placeOrder (limit) for ${symbol} reported success but no resting open order is visible (orderId=${result.orderId ?? 'null'}, limitPrice=${limitPrice}).`,
    );
  }

  return {
    action: input.action,
    source: 'perps-controller-placeOrder',
    network,
    account: accountAddress,
    market: symbol,
    side,
    orderType,
    notional: usdAmount,
    leverage,
    size: orderParams.size,
    currentPrice,
    limitPrice,
    submitted: true,
    orderId: result.orderId ?? null,
    filledSize: result.filledSize ?? null,
    averagePrice: result.averagePrice ?? null,
    matchingCount: orderType === 'limit' ? matchingOrders.length : matchingPositions.length,
    orders: matchingOrders.map(redactOrder),
    positions: matchingPositions.map(redactPosition),
    order: result,
    proofPath: 'perps-controller-placeOrder',
  };
}

if (isDirectRun(import.meta.url)) runAdapter(placeOrder);
