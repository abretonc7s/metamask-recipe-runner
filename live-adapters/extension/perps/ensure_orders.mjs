import { runAdapter } from '../platform/cdp.mjs';
import { ensureOrders } from './perps.mjs';

runAdapter(ensureOrders);
