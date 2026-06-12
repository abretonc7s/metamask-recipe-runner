import { runAdapter } from '../platform/bridge.mjs';
import { assertPositions, placeOrder } from './perps.mjs';
runAdapter(async (input) => {
  const order = await placeOrder(input);
  const assertion = await assertPositions(input, true);
  return { ...assertion, submitted: order.submitted === true, order };
});
