import { runAdapter } from '../platform/bridge.mjs';
import { assertOrders, closeOrders } from './perps.mjs';

runAdapter(async (input) => {
  const close = await closeOrders(input);
  const assertion = await assertOrders(input, false);
  return { ...assertion, close };
});
