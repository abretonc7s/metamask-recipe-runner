import { runAdapter } from '../platform/bridge.mjs';
import { assertOrders } from './perps.mjs';

function expectedOpen(input) {
  const state = String(input.node?.state ?? input.node?.orders ?? 'open').toLowerCase();
  if (state === 'open' || state === 'present') return true;
  if (state === 'none' || state === 'closed' || state === 'absent') return false;
  throw new Error(`metamask.perps.assert_orders received unsupported state: ${state}`);
}

runAdapter((input) => assertOrders(input, expectedOpen(input)));
