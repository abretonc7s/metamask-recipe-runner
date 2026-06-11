import { isDirectRun, resolveNetwork, runAdapter } from './_controller.mjs';
import { ensureOrders } from './ensure_orders.mjs';
import { ensurePositions } from './ensure_positions.mjs';

// core Headless composite that converges the POSITION and ORDER baselines for the
// selected market(s) on HyperLiquid testnet before the proof window. Mirrors the
// extension perps-domain-dispatcher start_state semantics but SKIPS every
// navigation/page/HUD step — headless core has no UI surface.
//
// Params (extension schema, testnet-default): profile, market(s)/symbol(s),
// positions{state,...}, orders{state,...}, network. The UI-only `page`/`hud`
// fields are accepted by the schema but intentionally ignored here.
//
// A baseline block converges to its `state` by composing the ensure_* helpers; a
// block set to `false` (or omitted) skips that domain. Position convergence runs
// first (closing a position also clears its TP/SL orders), then order
// convergence, so the final order baseline is authoritative.

const BASELINE_KEYS = [
  'market',
  'symbol',
  'markets',
  'symbols',
  'selector',
  'mode',
  'side',
  'network',
  'account',
  'account_name',
  'timeout_ms',
];

/**
 * Build an ensure_* input from the composite node plus a domain baseline block.
 * Selection/account/network fields flow from the top-level node; per-domain
 * fields (state, notional, leverage, offset_pct, ...) come from the block.
 *
 * @param input - The composite adapter input.
 * @param action - The target ensure action name (for trace fidelity).
 * @param baseline - The domain baseline object (positions/orders).
 */
function ensureInput(input, action, baseline) {
  const inherited = {};
  for (const key of BASELINE_KEYS) {
    if (input.node?.[key] !== undefined) inherited[key] = input.node[key];
  }
  return {
    ...input,
    action,
    node: { ...inherited, ...baseline, action },
  };
}

/**
 * Normalize a baseline block. `false` or absent → skip; an object → use as-is.
 * Anything else is a recipe error.
 */
function normalizeBaseline(value, label) {
  if (value === undefined || value === null || value === false) return null;
  if (typeof value === 'object' && !Array.isArray(value)) return value;
  throw new Error(`metamask.perps.start_state ${label} must be an object or false, got ${JSON.stringify(value)}.`);
}

export async function startState(input) {
  const network = resolveNetwork(input);
  const positionsBaseline = normalizeBaseline(input.node?.positions, 'positions');
  const ordersBaseline = normalizeBaseline(input.node?.orders, 'orders');

  const result = {
    action: input.action,
    source: 'perps-controller-composite',
    network,
    profile: input.node?.profile ?? null,
    converged: { positions: null, orders: null },
    proofPath: 'perps-controller-start_state',
  };

  if (positionsBaseline) {
    result.converged.positions = await ensurePositions(
      ensureInput(input, 'metamask.perps.ensure_positions', positionsBaseline),
    );
  }
  if (ordersBaseline) {
    result.converged.orders = await ensureOrders(
      ensureInput(input, 'metamask.perps.ensure_orders', ordersBaseline),
    );
  }

  return result;
}

if (isDirectRun(import.meta.url)) runAdapter(startState);
