import { runAdapter } from '../platform/bridge.mjs';
import { readPerpsPositions } from './perps.mjs';
runAdapter(readPerpsPositions);
