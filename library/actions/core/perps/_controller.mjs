import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { mnemonicToAccount, privateKeyToAccount } from 'viem/accounts';

// Importing a runner .ts source signals the live-adapter contract to execute
// this adapter under the bundled tsx (see commandFor/importsSourceTypescript in
// src/live-adapter-contract.ts). The core adapter dynamic-imports the perps
// controller TypeScript at runtime, so it MUST run under tsx, not plain node.
import { walletFixturePath } from '../../../../runner/src/paths.ts';

// Shared headless instantiation for the MetaMask `core` adapter.
//
// Slice 1: read-only. We instantiate @metamask/perps-controller against a
// resolved MetaMask/core checkout (context.projectRoot) and drive its standalone
// read path, which talks to HyperLiquid testnet over HTTP — no CDP, no bridge,
// no UI, no signer. The controller's standalone read methods
// (getPositions/getOpenOrders/getAccountState with { standalone: true,
// userAddress }) create their own InfoClient and never touch the messenger, so
// reads need ZERO external action handlers. Signing/account-resolution through
// the messenger is Slice 2.

function controllerEntry(projectRoot) {
  return pathToFileURL(path.join(projectRoot, 'packages/perps-controller/src/index.ts')).href;
}

function messengerEntry(projectRoot) {
  return pathToFileURL(path.join(projectRoot, 'packages/messenger/src/index.ts')).href;
}

// Faithful no-op implementation of PerpsPlatformDependencies. The read path only
// touches debugLogger/logger; the rest exist so the controller constructor and
// its services can be created without throwing. Mirrors the shape declared in
// packages/perps-controller/src/types/index.ts (PerpsPlatformDependencies).
//
// debugLogger/logger route to stderr so the LAST controller operation before a
// hang/exit is visible in the live-adapter run log. The write path lazily opens
// a persistent auto-reconnecting HyperLiquid WebSocket (HyperLiquidClientService
// .initialize → wsTransport.ready()); these logs proved the order returns over
// HTTP while that open socket kept the event loop alive — see disconnectAndExit.
function buildInfrastructure(stubbed) {
  const noop = () => undefined;
  return {
    logger: {
      error: (error, meta) =>
        process.stderr.write(
          `[core/perps][controller.error] ${error?.message ?? error}${
            meta ? ` ${JSON.stringify(meta)}` : ''
          }\n`,
        ),
    },
    debugLogger: {
      log: (message, meta) =>
        process.stderr.write(
          `[core/perps][controller] ${message}${meta ? ` ${JSON.stringify(meta)}` : ''}\n`,
        ),
    },
    metrics: { trackEvent: noop, isEnabled: () => false, trackPerpsEvent: noop },
    performance: { now: () => Date.now() },
    tracer: { trace: noop, endTrace: noop, setMeasurement: noop, addBreadcrumb: noop },
    streamManager: { pauseChannel: noop, resumeChannel: noop, clearAllChannels: noop },
    featureFlags: {
      validateVersionGated: () => {
        stubbed.add('featureFlags.validateVersionGated');
        return undefined;
      },
    },
    marketDataFormatters: {
      formatVolume: (value) => `$${value}`,
      formatPerpsFiat: (value) => `$${value}`,
      formatPercentage: (value) => `${value}%`,
      priceRangesUniversal: [],
    },
    cacheInvalidator: { invalidate: noop, invalidateAll: noop },
    diskCache: {
      getItem: async () => null,
      getItemSync: () => null,
      setItem: async () => undefined,
      removeItem: async () => undefined,
    },
    rewards: { getPerpsDiscountForAccount: async () => null },
  };
}

// --- Account resolution from wallet-fixture.json ---
//
// The core adapter resolves the signing account from the same wallet-fixture.json
// that mobile/extension adapters use (recipeRuntimePath/wallet-fixture.json).
// The fixture has the standard { accounts: [{ type, value, name }] } shape from
// wallet-fixture.json.sample. The recipe node selects an account by name via
// `account_name` (default "dev1"). The viem account derived from the fixture
// entry is the authoritative source for both the address AND the signing key —
// no separate MM_TEST_ACCOUNT_ADDRESS env var needed.
//
// Env-var fallback: if no fixture is present (e.g. direct CLI invocation),
// MM_TEST_ACCOUNT_SRP / MM_TEST_ACCOUNT_PRIVATE_KEY + MM_TEST_ACCOUNT_ADDRESS
// are still accepted for backward compatibility.

/**
 * Load wallet-fixture.json and return the named account entry.
 * Returns null if the fixture file does not exist.
 *
 * @param projectRoot - Absolute path to the project root.
 * @param accountName - The `name` field to match in fixture.accounts.
 */
async function loadFixtureAccount(projectRoot, accountName) {
  const fixturePath = walletFixturePath(projectRoot);
  let raw;
  try {
    raw = await readFile(fixturePath, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
  const fixture = JSON.parse(raw);
  if (!Array.isArray(fixture.accounts) || fixture.accounts.length === 0) {
    throw new Error(`wallet-fixture.json at ${fixturePath} has no accounts array.`);
  }
  const entry = fixture.accounts.find((a) => a?.name === accountName);
  if (!entry) {
    const names = fixture.accounts.map((a) => a?.name).filter(Boolean).join(', ');
    throw new Error(
      `wallet-fixture.json has no account named "${accountName}". Available: ${names}.`,
    );
  }
  if (typeof entry.value !== 'string' || entry.value.trim().length === 0) {
    throw new Error(`wallet-fixture.json account "${accountName}" has no value.`);
  }
  if (entry.type !== 'mnemonic' && entry.type !== 'privateKey') {
    throw new Error(
      `wallet-fixture.json account "${accountName}" type must be mnemonic or privateKey, got "${entry.type}".`,
    );
  }
  return entry;
}

/**
 * Derive a viem account from a wallet-fixture account entry.
 * Mnemonics use BIP-44 account index 0 (MetaMask default derivation).
 * Private keys are accepted with or without a 0x prefix.
 */
function viemAccountFromFixtureEntry(entry) {
  if (entry.type === 'mnemonic') {
    return mnemonicToAccount(entry.value.trim(), { addressIndex: 0 });
  }
  // privateKey
  const raw = entry.value.trim();
  const normalized = raw.startsWith('0x') ? raw : `0x${raw}`;
  if (!/^0x[0-9a-fA-F]{64}$/u.test(normalized)) {
    throw new Error(
      `wallet-fixture.json privateKey account "${entry.name}" is not a 32-byte hex key.`,
    );
  }
  return privateKeyToAccount(normalized);
}

// Env-var fallback constants (used only when wallet-fixture.json is absent).
const SIGNER_PRIVATE_KEY_ENV = 'MM_TEST_ACCOUNT_PRIVATE_KEY';
const SIGNER_MNEMONIC_ENV = 'MM_TEST_ACCOUNT_SRP';

function signerFromEnv() {
  const pk = process.env[SIGNER_PRIVATE_KEY_ENV]?.trim();
  if (pk && pk.length > 0) {
    const normalized = pk.startsWith('0x') ? pk : `0x${pk}`;
    if (!/^0x[0-9a-fA-F]{64}$/u.test(normalized)) {
      throw new Error(`${SIGNER_PRIVATE_KEY_ENV} is not a 32-byte hex private key.`);
    }
    return privateKeyToAccount(normalized);
  }
  const mnemonic = process.env[SIGNER_MNEMONIC_ENV]?.trim();
  if (mnemonic && mnemonic.split(/\s+/u).length >= 12) {
    return mnemonicToAccount(mnemonic, { addressIndex: 0 });
  }
  return null;
}

/**
 * Resolve the account name to use for signing.
 * Precedence: node.account_name → node.account (if not an address) → "dev1".
 */
function resolveAccountName(input) {
  const explicit = input.node?.account_name;
  if (typeof explicit === 'string' && explicit.trim().length > 0) return explicit.trim();
  // node.account can be either a name ("dev1") or an address ("0x...").
  // If it looks like an address, ignore it here — the address will be derived
  // from the fixture signer instead.
  const nodeAccount = input.node?.account;
  if (
    typeof nodeAccount === 'string' &&
    nodeAccount.trim().length > 0 &&
    !/^0x[0-9a-fA-F]{40}$/u.test(nodeAccount.trim())
  ) {
    return nodeAccount.trim();
  }
  return 'dev1';
}

/**
 * Resolve the viem signer and EVM address for writes.
 * Primary: wallet-fixture.json account selected by name.
 * Fallback: MM_TEST_ACCOUNT_PRIVATE_KEY / MM_TEST_ACCOUNT_SRP env vars
 *           (requires MM_TEST_ACCOUNT_ADDRESS for address verification).
 *
 * @param input - Adapter input (context.projectRoot, node.account_name).
 * @returns { account: ViemAccount, address: string }
 */
async function resolveSignerFromFixture(input) {
  const projectRoot = input.context?.projectRoot;
  const accountName = resolveAccountName(input);

  // Primary: fixture
  if (projectRoot) {
    const entry = await loadFixtureAccount(projectRoot, accountName);
    if (entry) {
      const account = viemAccountFromFixtureEntry(entry);
      return { account, address: account.address };
    }
  }

  // Fallback: env vars (no fixture present — direct CLI use)
  const account = signerFromEnv();
  if (!account) {
    throw new Error(
      `core perps writes require a wallet-fixture.json with account "${accountName}", ` +
      `or env vars ${SIGNER_PRIVATE_KEY_ENV} / ${SIGNER_MNEMONIC_ENV} + MM_TEST_ACCOUNT_ADDRESS.`,
    );
  }
  const envAddress = String(process.env.MM_TEST_ACCOUNT_ADDRESS ?? '').trim();
  if (!/^0x[0-9a-fA-F]{40}$/u.test(envAddress)) {
    throw new Error(
      `Env-var fallback requires MM_TEST_ACCOUNT_ADDRESS (a 0x EVM address) to verify the signer.`,
    );
  }
  if (account.address.toLowerCase() !== envAddress.toLowerCase()) {
    throw new Error(
      `Env-var signer derives ${account.address} but MM_TEST_ACCOUNT_ADDRESS is ${envAddress}; signatures would be invalid.`,
    );
  }
  return { account, address: envAddress };
}

/**
 * Resolve the account address for reads (no signing required).
 * Primary: wallet-fixture.json account selected by name (address derived from key).
 * Fallback: node.account / node.address / MM_TEST_ACCOUNT_ADDRESS env var.
 */
async function requireAccountAddress(input) {
  const projectRoot = input.context?.projectRoot;
  const accountName = resolveAccountName(input);

  if (projectRoot) {
    // No try/catch: loadFixtureAccount returns null when no fixture is present
    // (the only recoverable case) and THROWS on a malformed / missing-named /
    // empty / bad-type fixture. Those must fail loudly — swallowing them would
    // let a read silently run against a different address than the writes use.
    const entry = await loadFixtureAccount(projectRoot, accountName);
    if (entry) {
      const account = viemAccountFromFixtureEntry(entry);
      return account.address;
    }
  }

  // Fallback: explicit address from node or env
  const fromNode = input.node?.account ?? input.node?.address ?? input.node?.userAddress;
  const address = String(fromNode ?? process.env.MM_TEST_ACCOUNT_ADDRESS ?? '').trim();
  if (!/^0x[0-9a-fA-F]{40}$/u.test(address)) {
    throw new Error(
      `core perps reads require a wallet-fixture.json with account "${accountName}", ` +
      `or a 0x EVM address via node.account / MM_TEST_ACCOUNT_ADDRESS.`,
    );
  }
  return address;
}

let cached = null;

/**
 * Resolve the requested network. Default testnet; mainnet only when a node
 * explicitly sets network: "mainnet". Mainnet reads are safe; mainnet mutations
 * use REAL funds and must be explicitly requested — mirrors the extension/mobile
 * "mainnet is read-only unless explicitly requested" contract.
 */
export function resolveNetwork(input) {
  const raw = String(input.node?.network ?? 'testnet').toLowerCase();
  if (raw !== 'testnet' && raw !== 'mainnet') {
    throw new Error(
      `core perps network must be "testnet" or "mainnet", got "${input.node?.network}".`,
    );
  }
  return raw;
}

/**
 * Instantiate the PerpsController headlessly against the resolved core checkout.
 * Returns the controller plus the resolved read account address. Cached per
 * process so repeated reads in one adapter invocation reuse one controller.
 */
export async function getCoreController(input) {
  const projectRoot = input.context?.projectRoot;
  if (!projectRoot) throw new Error('core adapter requires context.projectRoot.');
  const accountAddress = await requireAccountAddress(input);
  const network = resolveNetwork(input);

  if (cached && cached.projectRoot === projectRoot && cached.network === network) {
    return { ...cached, accountAddress };
  }

  const [{ PerpsController }, { Messenger, MOCK_ANY_NAMESPACE }] = await Promise.all([
    import(controllerEntry(projectRoot)),
    import(messengerEntry(projectRoot)),
  ]);

  const stubbed = new Set();
  const infrastructure = buildInfrastructure(stubbed);

  // Root + child messenger pair, mirroring the real app wiring (and the core
  // repo's own test harness in
  // packages/perps-controller/tests/defer-eligibility.test.ts): a permissive
  // root messenger (MOCK_ANY_NAMESPACE) owns the external action handlers
  // (Accounts/Keyring/...), and the PerpsController-namespaced child receives
  // them via rootMessenger.delegate(). Slice 1 reads use the standalone path and
  // need no external handlers; Slice 2 writes register the signer handlers on
  // the root and delegate them into this child (see getCoreControllerWithSigner).
  const rootMessenger = new Messenger({ namespace: MOCK_ANY_NAMESPACE });
  const messenger = new Messenger({
    namespace: 'PerpsController',
    parent: rootMessenger,
  });

  // Default testnet. Mainnet only on explicit node.network: "mainnet" — mainnet
  // reads are safe; mainnet mutations use real funds (gated in getCoreControllerWithSigner).
  const isTestnet = network === 'testnet';
  const controller = new PerpsController({
    messenger,
    state: { isTestnet },
    infrastructure,
  });

  if (controller.state.isTestnet !== isTestnet) {
    throw new Error(`core perps controller did not initialize in ${network} mode.`);
  }

  const stubbedHandlers = Array.from(stubbed);
  if (stubbedHandlers.length > 0) {
    // Surface any stubbed dependency the read path leaned on, per the brief.
    process.stderr.write(
      `[core/perps] stubbed platform dependencies used during read: ${stubbedHandlers.join(', ')}\n`,
    );
  }

  // If a controller from a different network/checkout is cached in this process,
  // disconnect it (close its HL WebSocket) before replacing — a superseded
  // controller would otherwise leak its socket and keep the event loop alive.
  if (cached?.controller && typeof cached.controller.disconnect === 'function') {
    try {
      await cached.controller.disconnect();
    } catch (error) {
      process.stderr.write(
        `[core/perps] failed to disconnect superseded controller: ${fmtError(error)}\n`,
      );
    }
  }
  cached = { controller, messenger, rootMessenger, projectRoot, network };
  return { ...cached, accountAddress };
}

// --- Slice 2: default viem signer + write path ---
//
// WRITES go through the full provider path, not the standalone read path. The
// HyperLiquidProvider lazily builds the ExchangeClient by calling
// HyperLiquidWalletService.createWalletAdapter() (packages/perps-controller/
// src/services/HyperLiquidWalletService.ts), which in turn drives THREE external
// messenger actions that the real wallet resolves to KeyringController /
// AccountsController:
//   1. AccountsController:getSelectedAccount   — resolve the signing EVM account
//   2. KeyringController:getState              — assert the keyring is unlocked
//   3. KeyringController:signTypedMessage      — sign the EIP-712 typed data the
//                                                HL SDK constructs
// Headless, we register those three handlers on a permissive root messenger and
// delegate them into the PerpsController messenger, backed by a viem account
// resolved from wallet-fixture.json (see resolveSignerFromFixture). The HL SDK
// builds the typed data — we sign EXACTLY the {domain, types, primaryType,
// message} it passes; we never hand-roll the payload.

// The EXACT external actions the HyperLiquid write path drives through the
// messenger (HyperLiquidWalletService.createWalletAdapter / isKeyringUnlocked /
// getSelectedEvmAccountFromMessenger). These get registered on the root and
// delegated into the PerpsController child messenger.
const SIGNER_ACTIONS = [
  'AccountsController:getSelectedAccount',
  'KeyringController:getState',
  'KeyringController:signTypedMessage',
];

/**
 * Register the signer-backed external handlers on the root messenger and
 * delegate them into the PerpsController child, mirroring the real app's
 * rootMessenger.delegate(...) wiring. Idempotent per root messenger.
 *
 * @param rootMessenger - The permissive (MOCK_ANY_NAMESPACE) root messenger.
 * @param childMessenger - The PerpsController-namespaced messenger.
 * @param account - The viem signer account.
 * @param address - The selected EVM account address (0x).
 */
function registerSignerHandlers(rootMessenger, childMessenger, account, address) {
  if (rootMessenger.__coreSignerRegistered) return;

  // AccountsController:getSelectedAccount — getSelectedEvmAccountFromMessenger()
  // calls this first and uses it when the returned object looks like an account
  // with an EVM `type`. Minimal InternalAccount shape: address + EVM type, plus
  // metadata.keyring.type so isSelectedHardwareWallet() sees a software (non-
  // hardware) keyring and allows user signing.
  rootMessenger.registerActionHandler(
    'AccountsController:getSelectedAccount',
    () => ({
      id: 'core-headless-signer',
      address,
      type: 'eip155:eoa',
      metadata: { keyring: { type: 'HD Key Tree' } },
    }),
  );

  // KeyringController:getState — isKeyringUnlocked() reads `.isUnlocked`. The
  // headless keyring is always unlocked (we hold the private key).
  rootMessenger.registerActionHandler('KeyringController:getState', () => ({
    isUnlocked: true,
  }));

  // KeyringController:signTypedMessage — the heart of Slice 2. The wallet
  // adapter calls this with ({ from, data: typedData }, version='V4'). `data`
  // is the EXACT { domain, types, primaryType, message } the HL SDK built. We
  // sign it verbatim with viem and return the hex signature the SDK expects.
  rootMessenger.registerActionHandler(
    'KeyringController:signTypedMessage',
    async (msgParams) => {
      const typedData =
        typeof msgParams?.data === 'string'
          ? JSON.parse(msgParams.data)
          : msgParams?.data;
      if (!typedData || typeof typedData !== 'object') {
        throw new Error(
          'KeyringController:signTypedMessage received no typed data to sign.',
        );
      }
      const { domain, types, primaryType, message } = typedData;
      // Strip the EIP712Domain entry if present: viem derives the domain types
      // from `domain` itself and rejects a duplicate EIP712Domain in `types`.
      const signableTypes = { ...types };
      delete signableTypes.EIP712Domain;
      return account.signTypedData({
        domain,
        types: signableTypes,
        primaryType,
        message,
      });
    },
  );

  // Deliver the handlers to the PerpsController messenger so its internal
  // this.messenger.call('AccountsController:getSelectedAccount' | 'Keyring...')
  // resolves them.
  rootMessenger.delegate({ actions: SIGNER_ACTIONS, messenger: childMessenger });

  rootMessenger.__coreSignerRegistered = true;
}

/**
 * Instantiate the PerpsController with the default viem signer wired in and the
 * active HyperLiquid testnet provider initialized, ready for writes
 * (placeOrder/closePosition). Builds on getCoreController (Slice 1 setup) and
 * additionally:
 *   - registers the account + signTypedData messenger handlers, and
 *   - calls controller.init() so getActiveProvider() (which placeOrder requires)
 *     returns the active HyperLiquidProvider. The provider lazily initializes its
 *     ExchangeClient(wallet) on the first write, awaiting that path internally.
 *
 * @param input - The adapter input (context.projectRoot, account, env).
 * @returns { controller, projectRoot, network, accountAddress, signerAddress }.
 */
export async function getCoreControllerWithSigner(input) {
  const base = await getCoreController(input);
  const { controller, messenger: childMessenger, rootMessenger, accountAddress } = base;
  if (!rootMessenger || !childMessenger) {
    throw new Error('core perps controller exposes no messenger pair for signing.');
  }

  // Default testnet. A mutation on mainnet uses REAL funds, so it is gated TWICE:
  // the recipe node must explicitly set network: "mainnet" (resolveNetwork), AND a
  // human must opt in via CORE_PERPS_ALLOW_MAINNET_WRITES=1 — so a copy-pasted recipe
  // alone cannot move real money on a dev/CI box.
  if (base.network === 'mainnet') {
    if (process.env.CORE_PERPS_ALLOW_MAINNET_WRITES !== '1') {
      throw new Error(
        'core perps refuses a MAINNET write: set CORE_PERPS_ALLOW_MAINNET_WRITES=1 to confirm signing with REAL funds.',
      );
    }
    process.stderr.write(
      '[core/perps] WARNING: signing a MAINNET perps action with REAL funds (network=mainnet + CORE_PERPS_ALLOW_MAINNET_WRITES=1)\n',
    );
  }

  const { account, address: signerAddress } = await resolveSignerFromFixture(input);
  registerSignerHandlers(rootMessenger, childMessenger, account, signerAddress);

  // Bring up the active provider. placeOrder/closePosition call
  // getActiveProvider(), which throws CLIENT_NOT_INITIALIZED until init()
  // assigns the active HyperLiquidProvider. init() is idempotent (promise
  // cached), so repeated write adapters in one run reuse the same provider.
  await controller.init();

  const wantTestnet = base.network === 'testnet';
  if (controller.state.isTestnet !== wantTestnet) {
    throw new Error(`core perps controller is not in ${base.network} mode; refusing to sign.`);
  }

  return { ...base, signerAddress };
}

/**
 * Resolve the current numeric market price for a symbol via the controller's
 * standalone market-data path (same HTTP read used by Slice 1 — no signing, no
 * provider init required). Used to convert a USD notional into a coin size for
 * placeOrder, mirroring the extension: size = (usdAmount * leverage) / price.
 *
 * @param controller - The instantiated PerpsController.
 * @param symbol - Normalized market symbol (e.g. 'BTC').
 * @returns The current price as a positive number.
 */
export async function currentMarketPrice(controller, symbol) {
  const markets = await controller.getMarketDataWithPrices({ standalone: true });
  const target = normalizeMarketSymbol(symbol);
  const market = (Array.isArray(markets) ? markets : []).find(
    (item) => normalizeMarketSymbol(item?.symbol ?? '') === target,
  );
  if (!market) {
    throw new Error(`No market data found for ${target} on testnet.`);
  }
  // PerpsMarketData.price is a formatted string like '$103,245.00'.
  const numeric = Number(String(market.price ?? '').replace(/[$,\s]/gu, ''));
  if (!Number.isFinite(numeric) || numeric <= 0) {
    throw new Error(
      `Unable to parse a positive current price for ${target} (got ${JSON.stringify(market.price)}).`,
    );
  }
  return numeric;
}

// --- Selection vocabulary (mirrors the extension perps adapter contract) ---

export function normalizeMarketSymbol(rawSymbol) {
  const raw = String(rawSymbol);
  if (raw.includes(':')) {
    const [source, ...symbolParts] = raw.split(':');
    return `${source.toLowerCase()}:${symbolParts.join(':').toUpperCase()}`;
  }
  return raw.toUpperCase();
}

export function symbolForItem(item) {
  return normalizeMarketSymbol(item?.symbol ?? item?.coin ?? '');
}

// Normalize an item's side to the long/short vocabulary the selector uses.
// Positions report side as long/short already; OPEN ORDERS report it as buy/sell
// (a resting BUY = long direction, a resting SELL = short). Mapping both onto
// long/short lets the shared `side` selector filter positions and orders alike —
// without this, requesting side:"long" silently drops every order (whose side is
// "buy"), which is the bug this normalization fixes.
function normalizeSide(rawSide) {
  const side = String(rawSide ?? '').toLowerCase();
  if (side === 'buy' || side === 'b') return 'long';
  if (side === 'sell' || side === 'a' || side === 's') return 'short';
  return side;
}

function sideForItem(item) {
  return normalizeSide(item?.side ?? item?.direction ?? '');
}

function uniqueSymbols(symbols) {
  return Array.from(new Set(symbols.filter(Boolean)));
}

export function configuredSymbols(input, items) {
  const selector =
    input.node?.selector && typeof input.node.selector === 'object' ? input.node.selector : {};
  const mode = String(input.node?.mode ?? selector.mode ?? 'matching').toLowerCase();
  if (mode === 'all') return uniqueSymbols(items.map(symbolForItem).filter(Boolean));
  const explicit = input.node?.markets ?? input.node?.symbols ?? selector.markets ?? selector.symbols;
  if (Array.isArray(explicit) && explicit.length > 0) {
    return uniqueSymbols(explicit.map(normalizeMarketSymbol));
  }
  if (typeof explicit === 'string' && explicit.length > 0) {
    return uniqueSymbols(
      explicit
        .split(',')
        .map((part) => normalizeMarketSymbol(part.trim()))
        .filter(Boolean),
    );
  }
  const single = input.node?.market ?? input.node?.symbol;
  return single ? [normalizeMarketSymbol(single)] : [];
}

/**
 * Filter live items to the recipe-selected subset using the same market/side
 * vocabulary as the extension perps adapter. With no selector and no
 * mode=all, returns every item (read defaults to showing all live state).
 */
export function selectedItems(input, items) {
  const requested = configuredSymbols(input, items);
  const selector =
    input.node?.selector && typeof input.node.selector === 'object' ? input.node.selector : {};
  const requestedSide = input.node?.side ?? selector.side;
  const side = requestedSide ? normalizeSide(requestedSide) : undefined;
  const symbols = requested.length > 0 ? new Set(requested) : null;
  return items.filter((item) => {
    if (symbols && !symbols.has(symbolForItem(item))) return false;
    if (side && sideForItem(item) && sideForItem(item) !== side) return false;
    return true;
  });
}

export function redactPosition(position) {
  return {
    coin: position.coin ?? position.symbol ?? null,
    size: position.size ?? position.szi ?? null,
    side: position.side ?? null,
    entryPrice: position.entryPrice ?? position.entryPx ?? null,
  };
}

export function redactOrder(order) {
  return {
    coin: order.coin ?? order.symbol ?? null,
    side: order.side ?? null,
    size: order.size ?? order.sz ?? order.szi ?? null,
    price: order.price ?? order.limitPx ?? order.px ?? null,
    type: order.orderType ?? order.type ?? null,
  };
}

// --- Adapter IO (mirrors the live-adapter contract in src/live-adapter-contract.ts) ---

async function loadInput() {
  const inputPath = process.argv[2] || process.env.METAMASK_RECIPE_ADAPTER_INPUT;
  if (!inputPath) throw new Error('Missing live adapter input path.');
  return JSON.parse(await readFile(inputPath, 'utf8'));
}

async function writeOutput(input, output) {
  await writeFile(input.outputPath, `${JSON.stringify(output, null, 2)}\n`);
}

// Format an error for stderr without truncating stack traces.
const fmtError = (e) => e?.stack ?? e?.message ?? String(e);

/**
 * Tear the cached controller down so the process can drain and exit naturally.
 *
 * ROOT CAUSE this fixes: the WRITE path (placeOrder/closePosition) runs
 * controller.init() → first write → HyperLiquidProvider.#ensureClientsInitialized
 * → HyperLiquidClientService.initialize(), which creates a persistent,
 * auto-reconnecting WebSocketTransport (reconnect config) and awaits
 * wsTransport.ready(). Orders themselves go over the HTTP ExchangeClient and
 * RETURN normally, but that open WebSocket keeps the Node event loop alive, so
 * the adapter process never exits. The runner only resolves on the child's
 * `close` event (src/live-adapter-contract.ts runProcess), so it waits out
 * live_adapter_timeout_ms, SIGTERMs the child, and reports `fail` even though
 * the trade filled and the output was computed. READ adapters use the
 * standalone HTTP-only InfoClient (utils/standaloneInfoClient) — no WebSocket —
 * so they never hang.
 *
 * controller.disconnect() closes the WebSocket transport and clears
 * subscriptions (PerpsController.disconnect → HyperLiquidClientService teardown
 * → wsTransport.close()). Once the socket is closed the event loop drains and
 * Node exits naturally. We await it best-effort: a teardown failure must not
 * mask a successful trade whose output is already written, but per the
 * no-swallowed-exceptions rule we log the reason to stderr, then set
 * process.exitCode and fall through — the process will drain and exit on its own.
 *
 * @param exitCode - Exit code to set before returning (0 = success).
 */
async function disconnectController(exitCode) {
  process.exitCode = exitCode;
  const controller = cached?.controller;
  if (controller && typeof controller.disconnect === 'function') {
    try {
      await controller.disconnect();
    } catch (error) {
      // Best-effort teardown: output already written; surface, don't swallow.
      process.stderr.write(
        `[core/perps] controller.disconnect() failed during teardown: ${fmtError(error)}\n`,
      );
    }
  }
}

export async function runAdapter(callback) {
  const input = await loadInput();
  let exitCode = 0;
  try {
    await writeOutput(input, await callback(input));
  } catch (error) {
    exitCode = 1;
    // Surface the failure; still tear down so a half-open WebSocket from a
    // failed write doesn't leave the process wedged open.
    process.stderr.write(`[core/perps] adapter failed: ${fmtError(error)}\n`);
  } finally {
    await disconnectController(exitCode);
  }
}

/**
 * True when the given module is the process entry point (tsx <file> <input>).
 * Write adapters import each other (ensure → place/close → assert), so each
 * top-level runAdapter() must be gated on this to avoid firing on import.
 *
 * @param importMetaUrl - The importing module's import.meta.url.
 * @returns Whether this module was invoked directly by the harness.
 */
export function isDirectRun(importMetaUrl) {
  const entry = process.argv[1];
  if (!entry) return false;
  return importMetaUrl === pathToFileURL(entry).href;
}
