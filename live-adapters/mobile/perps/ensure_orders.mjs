import { runAdapter } from '../platform/bridge.mjs';
import { ensureOrders } from './perps.mjs';

runAdapter(ensureOrders);
