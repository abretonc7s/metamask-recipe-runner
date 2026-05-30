import { runAdapter } from '../platform/cdp.mjs';
import { assertPositions } from './perps.mjs';

function expectedOpen(input) {
  const state = String(input.node?.state ?? input.node?.position ?? 'open').toLowerCase();
  if (state === 'open' || state === 'present') return true;
  if (state === 'none' || state === 'closed' || state === 'absent') return false;
  throw new Error(`metamask.perps.assert_positions received unsupported state: ${state}`);
}

runAdapter((input) => assertPositions(input, expectedOpen(input)));
