import { runAdapter } from '../platform/cdp.mjs';
import { ensurePositions } from './perps.mjs';

runAdapter(ensurePositions);
