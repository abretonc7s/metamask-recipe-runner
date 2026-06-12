import { runAdapter } from '../platform/cdp.mjs';
import { readPositions } from './perps.mjs';
runAdapter(readPositions);
