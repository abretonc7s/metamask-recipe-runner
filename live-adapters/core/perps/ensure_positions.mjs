import { getCoreController, isDirectRun, runAdapter, selectedItems } from './_controller.mjs';
import { assertPositions } from './assert_positions.mjs';
import { closePositions } from './close_positions.mjs';
import { placeOrder } from './place_order.mjs';

// core Higher-level wrapper that reads selected positions, converges them to the
// requested `state` (open/none) by placing or closing, then asserts the final
// state. Mirrors the extension ensure_positions semantics.

export async function ensurePositions(input) {
  const state = String(input.node?.state ?? input.node?.position ?? 'none').toLowerCase();

  if (state === 'none' || state === 'closed' || state === 'absent') {
    const close = await closePositions(input);
    const assertion = await assertPositions(input, false);
    return { ...assertion, ensured: 'none', close };
  }

  if (state === 'open' || state === 'present') {
    // Only place when no matching position already exists (idempotent ensure).
    const { controller, accountAddress } = await getCoreController(input);
    const positions = await controller.getPositions({
      standalone: true,
      userAddress: accountAddress,
    });
    let order = null;
    if (selectedItems(input, positions).length === 0) {
      order = await placeOrder(input);
    }
    const assertion = await assertPositions(input, true);
    return { ...assertion, ensured: 'open', order };
  }

  throw new Error(`metamask.perps.ensure_positions received unsupported state: ${state}`);
}

if (isDirectRun(import.meta.url)) runAdapter(ensurePositions);
