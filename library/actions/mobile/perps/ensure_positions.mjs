import { runAdapter } from '../platform/bridge.mjs';
import { ensurePositions } from './perps.mjs';

runAdapter(ensurePositions);
