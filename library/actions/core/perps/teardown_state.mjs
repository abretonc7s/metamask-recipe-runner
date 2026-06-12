import { isDirectRun, resolveNetwork, runAdapter } from './_controller.mjs';
import { ensureOrders } from './ensure_orders.mjs';
import { ensurePositions } from './ensure_positions.mjs';

// core Headless composite that restores the POSITION and ORDER baselines for the
// selected market(s) on HyperLiquid testnet after the proof window. Mirrors the
// extension perps-domain-dispatcher teardown_state semantics but SKIPS every
// navigation/page/HUD step — headless core has no UI surface.
//
// Params (extension schema, testnet-default): profile, market(s)/symbol(s),
// positions{state,...}, orders{state,...}, network. The UI-only `page`/`hud`
// fields are accepted by the schema but intentionally ignored here.
//
// Teardown defaults BOTH domains to state=none (leave the shared dev account
// FLAT) when a baseline block is omitted; pass a block explicitly to override, or
// `false` to skip a domain. Orders are canceled FIRST, then positions are closed,
// so resting orders never re-arm against a position mid-teardown.

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
 * Normalize a teardown baseline block.
 * - `false` → skip the domain.
 * - object → use as-is.
 * - undefined/null → default to { state: 'none' } (restore to flat).
 */
function normalizeBaseline(value, label) {
  if (value === false) return null;
  if (value === undefined || value === null) return { state: 'none' };
  if (typeof value === 'object' && !Array.isArray(value)) return value;
  throw new Error(`metamask.perps.teardown_state ${label} must be an object or false, got ${JSON.stringify(value)}.`);
}

export async function teardownState(input) {
  const network = resolveNetwork(input);
  const ordersBaseline = normalizeBaseline(input.node?.orders, 'orders');
  const positionsBaseline = normalizeBaseline(input.node?.positions, 'positions');

  const result = {
    action: input.action,
    source: 'perps-controller-composite',
    network,
    profile: input.node?.profile ?? null,
    converged: { orders: null, positions: null },
    proofPath: 'perps-controller-teardown_state',
  };

  if (ordersBaseline) {
    result.converged.orders = await ensureOrders(
      ensureInput(input, 'metamask.perps.ensure_orders', ordersBaseline),
    );
  }
  if (positionsBaseline) {
    result.converged.positions = await ensurePositions(
      ensureInput(input, 'metamask.perps.ensure_positions', positionsBaseline),
    );
  }

  return result;
}

if (isDirectRun(import.meta.url)) runAdapter(teardownState);
