import { runAdapter } from '../platform/bridge.mjs';
import { readOrders } from './perps.mjs';

runAdapter(readOrders);
