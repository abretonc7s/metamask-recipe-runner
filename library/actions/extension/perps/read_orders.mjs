import { runAdapter } from '../platform/cdp.mjs';
import { readOrders } from './perps.mjs';

runAdapter(readOrders);
