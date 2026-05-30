import { runAdapter } from '../platform/bridge.mjs';
import { assertPositions, closePositions } from './perps.mjs';

runAdapter(async (input) => {
  const close = await closePositions(input);
  const assertion = await assertPositions(input, false);
  return { ...assertion, close };
});
