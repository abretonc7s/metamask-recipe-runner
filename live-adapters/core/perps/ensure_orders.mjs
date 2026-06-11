import { getCoreController, isDirectRun, runAdapter, selectedItems } from './_controller.mjs';
import { assertOrders } from './assert_orders.mjs';
import { closeOrders } from './close_orders.mjs';
import { placeOrder } from './place_order.mjs';

// core Higher-level wrapper that reads selected open orders, converges them to the
// requested `state` (open/none) by canceling or placing, then asserts the final
// order state. Mirrors ensure_positions.mjs.

export async function ensureOrders(input) {
  const state = String(input.node?.state ?? input.node?.order ?? 'none').toLowerCase();

  if (state === 'none' || state === 'closed' || state === 'absent') {
    const close = await closeOrders(input);
    const assertion = await assertOrders(input, false);
    return { ...assertion, ensured: 'none', close };
  }

  if (state === 'open' || state === 'present') {
    // Only place a resting order when no matching open order already exists
    // (idempotent ensure). Placing to reach state=open requires a limit order
    // (orderType=limit + price/offset_pct) so it rests on the book instead of
    // filling — see place_order.mjs.
    const { controller, accountAddress } = await getCoreController(input);
    const orders = await controller.getOpenOrders({
      standalone: true,
      userAddress: accountAddress,
    });
    let order = null;
    if (selectedItems(input, orders).length === 0) {
      order = await placeOrder({ ...input, node: { ...input.node, order_type: 'limit' } });
    }
    const assertion = await assertOrders(input, true);
    return { ...assertion, ensured: 'open', order };
  }

  throw new Error(`metamask.perps.ensure_orders received unsupported state: ${state}`);
}

if (isDirectRun(import.meta.url)) runAdapter(ensureOrders);
