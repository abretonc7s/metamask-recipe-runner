import { constants, access, cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { closeSync, openSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';

import {
  importRecipeHarnessRuntimeBrowserExtension,
  importRecipeHarnessRuntimeCdp,
  extensionIdPath,
  recipeHarnessPath,
  walletFixturePath,
} from '../../../src/paths.ts';

// Resolve the Farmslot harness through normal package dependencies by default.
// Local Farmslot source is only a dev override handled by src/paths.ts.
const {
  CdpSession,
  CdpWebPage,
  dataTestId,
  jsonGet,
  retryJsonGet,
  sleep,
} = await importRecipeHarnessRuntimeCdp();
const { extensionIdFromTarget } = await importRecipeHarnessRuntimeBrowserExtension();

export { dataTestId };

async function canAccess(file) {
  try {
    await access(file, constants.F_OK);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

function cdpPort(input) {
  const raw = input.node?.cdp_port ?? process.env.CDP_PORT ?? process.env.RECIPE_CDP_PORT;
  const port = Number(raw);
  if (!Number.isInteger(port) || port <= 0) {
    throw new Error('Extension live adapter requires node.cdp_port, CDP_PORT, or RECIPE_CDP_PORT.');
  }
  return port;
}

function extensionTarget(targets, extensionId = null) {
  return (Array.isArray(targets) ? targets : []).find((target) => {
    if (target?.type !== 'page') return false;
    if (!String(target?.url ?? '').startsWith('chrome-extension://')) return false;
    if (!String(target.url).includes('/home.html')) return false;
    if (extensionId && extensionIdFromTarget(target) !== extensionId) return false;
    return Boolean(target.webSocketDebuggerUrl);
  }) ?? null;
}


function resolveRelativeArtifactPath(artifactsDir, relPath) {
  const relative = relPath || 'screenshots/extension-page.png';
  if (path.isAbsolute(relative) || relative.split(/[\/]+/).includes('..')) {
    throw new Error(`Refusing Extension screenshot artifact path outside artifacts dir: ${relative}`);
  }
  const normalized = path.normalize(relative);
  const absolute = path.resolve(artifactsDir, normalized);
  const artifactsRoot = path.resolve(artifactsDir);
  if (absolute !== artifactsRoot && !absolute.startsWith(`${artifactsRoot}${path.sep}`)) {
    throw new Error(`Refusing Extension screenshot artifact path outside artifacts dir: ${relative}`);
  }
  return { relative: normalized, absolute };
}

function captureHelperPath() {
  return process.env.CAPTURE_HELPER_PATH || 'capture-helper';
}

function parsePositivePid(value) {
  const pid = Number(String(value ?? '').trim());
  return Number.isInteger(pid) && pid > 0 ? pid : null;
}

async function readPidFile(file) {
  if (!(await canAccess(file))) return null;
  return parsePositivePid(await readFile(file, 'utf8'));
}

async function captureHelperBrowserPid(context, port) {
  const explicit = parsePositivePid(process.env.METAMASK_RECIPE_EXTENSION_BROWSER_PID);
  if (explicit) return explicit;

  const lsof = await runProcess('lsof', ['-nP', `-iTCP:${port}`, '-sTCP:LISTEN', '-t'], {
    cwd: context.projectRoot,
    env: process.env,
    timeoutMs: 5000,
  });
  if (lsof.exitCode === 0) {
    const pid = parsePositivePid(lsof.stdout.split(/\s+/u).find(Boolean));
    if (pid) return pid;
  }

  const runtimeJson = path.join(context.artifactsDir, 'extension-runtime/runtime.json');
  if (await canAccess(runtimeJson)) {
    const runtime = JSON.parse(await readFile(runtimeJson, 'utf8'));
    const pid = parsePositivePid(runtime?.pid);
    if (pid) return pid;
  }

  const recipeRuntime = path.join(context.projectRoot, 'temp/recipe/runtime');
  for (const name of ['chromium.pid', 'browser.pid']) {
    const pid = await readPidFile(path.join(recipeRuntime, name));
    if (pid) return pid;
  }

  throw new Error(
    `Extension ui.screenshot requires a live browser PID for capture-helper snapshot, but none could be resolved from CDP port ${port}, extension-runtime/runtime.json, or temp/recipe/runtime/*.pid.`,
  );
}

async function captureHelperSnapshot(page, context, relPath, metadata) {
  if (process.platform !== 'darwin') {
    throw new Error('Extension ui.screenshot uses capture-helper snapshot and is currently supported only on macOS.');
  }
  const { relative, absolute } = resolveRelativeArtifactPath(context.artifactsDir, relPath);
  await mkdir(path.dirname(absolute), { recursive: true });

  await page.session.call('Page.bringToFront');
  const pid = await captureHelperBrowserPid(context, page.port);
  const result = await runProcess(captureHelperPath(), ['snapshot', '--pid', String(pid), '--output', absolute], {
    cwd: context.projectRoot,
    env: process.env,
    timeoutMs: Number(metadata?.timeoutMs ?? 30000),
  });
  if (result.exitCode !== 0) {
    throw new Error(
      `capture-helper snapshot failed for Extension ui.screenshot (pid ${pid}): ${result.stderr || result.stdout}`,
    );
  }
  const details = parseJsonObject(result.stdout);
  return {
    path: relative,
    type: 'screenshot',
    nodeId: context.nodeId,
    label: metadata?.label ?? `${context.nodeId} screenshot`,
    category: metadata?.category ?? 'evidence',
    mimeType: 'image/png',
    metadata: {
      provider: 'capture-helper',
      mode: 'snapshot',
      pid,
      ...(details ? { captureHelper: details } : {}),
    },
  };
}

function autolaunchEnabled(input) {
  return input.node?.launch_existing_dist === true ||
    input.node?.autolaunch === true ||
    process.env.METAMASK_RECIPE_EXTENSION_AUTOLAUNCH === '1' ||
    process.env.METAMASK_RECIPE_EXTENSION_LAUNCH_EXISTING_DIST === '1';
}

function projectRequire(projectRoot) {
  return createRequire(path.join(projectRoot, 'package.json'));
}

function resolveChromeBinary(projectRoot) {
  if (process.env.RECIPE_HARNESS_CHROME_BIN) return process.env.RECIPE_HARNESS_CHROME_BIN;
  const requireFromProject = projectRequire(projectRoot);
  for (const packageName of ['@playwright/test', 'playwright']) {
    try {
      const { chromium } = requireFromProject(packageName);
      const executable = chromium.executablePath();
      if (executable) return executable;
    } catch (error) {
      if (error?.code === 'MODULE_NOT_FOUND') continue;
      throw error;
    }
  }
  throw new Error('Extension autolaunch requires RECIPE_HARNESS_CHROME_BIN or Playwright installed in the target checkout.');
}

async function execNodeScript(script, args, options) {
  const result = await runProcess(process.execPath, [script, ...args], options);
  if (result.exitCode !== 0) {
    throw new Error(`Command failed: node ${script} ${args.join(' ')}\n${result.stderr || result.stdout}`);
  }
  return result;
}

function runProcess(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let timer = null;
    let stdout = '';
    let stderr = '';
    if (options.timeoutMs) {
      timer = setTimeout(() => {
        child.kill('SIGTERM');
        reject(new Error(`Command timed out after ${options.timeoutMs}ms: ${command} ${args.join(' ')}`));
      }, options.timeoutMs);
    }
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', (error) => {
      if (timer) clearTimeout(timer);
      reject(error);
    });
    child.on('close', (exitCode) => {
      if (timer) clearTimeout(timer);
      resolve({ exitCode, stdout, stderr });
    });
  });
}

function parseJsonObject(value) {
  const trimmed = String(value ?? '').trim();
  if (!trimmed) return null;
  try {
    const parsed = JSON.parse(trimmed);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch (error) {
    throw new Error(`capture-helper snapshot returned non-JSON output: ${trimmed}`);
  }
}

async function findWalletFixture(projectRoot) {
  const candidates = [
    walletFixturePath(projectRoot),
  ];
  for (const candidate of candidates) {
    if (await canAccess(candidate)) return candidate;
  }
  return null;
}

async function launchExistingDistRuntime(input, port) {
  const projectRoot = input.context.projectRoot;
  const artifactsDir = input.context.artifactsDir;
  const distDir = path.resolve(projectRoot, input.node?.dist_dir || process.env.METAMASK_RECIPE_EXTENSION_DIST_DIR || 'dist/chrome');
  const distManifest = path.join(distDir, 'manifest.json');
  if (!(await canAccess(distManifest))) {
    throw new Error(`Extension autolaunch requires an existing built dist with manifest.json: ${distManifest}`);
  }

  const runtimeRoot = path.join(artifactsDir, 'extension-runtime');
  const runtimeDist = path.join(runtimeRoot, 'runtime-dist');
  const profileDir = path.resolve(process.env.METAMASK_RECIPE_EXTENSION_PROFILE_DIR || path.join(runtimeRoot, 'chrome-profile'));
  const logsDir = path.join(runtimeRoot, 'logs');
  await mkdir(logsDir, { recursive: true });
  await rm(runtimeDist, { recursive: true, force: true });
  await mkdir(runtimeDist, { recursive: true });
  await cp(distDir, runtimeDist, { recursive: true, force: true, filter: (source) => !source.endsWith(`${path.sep}_metadata`) });
  await mkdir(profileDir, { recursive: true });

  const fixtureScript = recipeHarnessPath(projectRoot, 'extension/scripts/wallet-fixture-state.cjs');
  const fixture = await findWalletFixture(projectRoot);
  const extensionIdFile = extensionIdPath(projectRoot);
  const fixtureState = path.join(runtimeRoot, 'fixture-state.json');
  let fixtureSeeded = false;
  if (fixture && await canAccess(fixtureScript)) {
    await execNodeScript(fixtureScript, ['generate', '--target', projectRoot, '--fixture', fixture, '--out', fixtureState], { cwd: projectRoot });
    await execNodeScript(fixtureScript, ['prefill-profile', '--target', projectRoot, '--state', fixtureState, '--profile', profileDir, '--extension-dir', runtimeDist, '--extension-id-file', extensionIdFile], { cwd: projectRoot });
    fixtureSeeded = true;
  }

  const chrome = resolveChromeBinary(projectRoot);
  const stdoutFd = openSync(path.join(logsDir, 'chrome.log'), 'a');
  const stderrFd = openSync(path.join(logsDir, 'chrome.log'), 'a');
  let child;
  try {
    child = spawn(chrome, [
      `--user-data-dir=${profileDir}`,
      '--remote-debugging-address=127.0.0.1',
      `--remote-debugging-port=${port}`,
      '--no-first-run',
      '--disable-first-run-ui',
      '--disable-default-apps',
      '--disable-popup-blocking',
      '--disable-extensions-file-access-check',
      '--disable-extensions-content-verification',
      '--disable-features=ExtensionContentVerification,DisableLoadExtensionCommandLineSwitch',
      `--disable-extensions-except=${runtimeDist}`,
      `--load-extension=${runtimeDist}`,
      'chrome://extensions/',
    ], {
      cwd: projectRoot,
      detached: true,
      env: {
        ...process.env,
        BUNDLED_DEBUGPY_PATH: undefined,
        PYTHONHOME: undefined,
        PYTHONPATH: undefined,
        DYLD_LIBRARY_PATH: undefined,
        DYLD_FALLBACK_LIBRARY_PATH: undefined,
        DYLD_INSERT_LIBRARIES: undefined,
      },
      stdio: ['ignore', stdoutFd, stderrFd],
    });
  } finally {
    closeSync(stdoutFd);
    closeSync(stderrFd);
  }
  child.unref();
  await writeFile(path.join(logsDir, 'chrome.pid'), `${child.pid}\n`);
  await retryJsonGet(`http://127.0.0.1:${port}/json/version`, 45000);

  let fixtureValidation = null;
  if (fixtureSeeded) {
    fixtureValidation = path.join(logsDir, 'fixture-account-parity.json');
    await execNodeScript(
      fixtureScript,
      [
        'seed-cdp',
        '--target',
        projectRoot,
        '--fixture',
        fixture,
        '--state',
        fixtureState,
        '--cdp-port',
        String(port),
        '--extension-dir',
        runtimeDist,
        '--extension-id-file',
        extensionIdFile,
        '--out',
        fixtureValidation,
      ],
      { cwd: projectRoot },
    );
  }

  await writeFile(path.join(runtimeRoot, 'runtime.json'), `${JSON.stringify({
    port,
    pid: child.pid,
    projectRoot,
    distDir,
    runtimeDist,
    profileDir,
    fixtureSeeded,
    fixtureValidation,
    launchedAt: new Date().toISOString(),
  }, null, 2)}\n`);
  return { launched: true, pid: child.pid, runtimeRoot, fixtureSeeded };
}

async function extensionIdFromFile(projectRoot) {
  const extensionIdFile = extensionIdPath(projectRoot);
  if (!(await canAccess(extensionIdFile))) return null;
  const id = (await readFile(extensionIdFile, 'utf8')).trim();
  return /^[a-z]{32}$/u.test(id) ? id : null;
}

function extensionIdFromAnyTarget(targets) {
  for (const target of Array.isArray(targets) ? targets : []) {
    try {
      return extensionIdFromTarget(target);
    } catch (error) {
      if (String(error?.message ?? '').startsWith('Could not derive extension ID')) continue;
      throw error;
    }
  }
  return null;
}

async function openExtensionHomePage(port, extensionId) {
  const url = `chrome-extension://${extensionId}/home.html`;
  const endpoint = `http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`;
  let response = await fetch(endpoint, { method: 'PUT' });
  if (response.status === 405 || response.status === 404) {
    response = await fetch(endpoint);
  }
  if (!response.ok) {
    throw new Error(`Failed to open extension home page ${url}: HTTP ${response.status}`);
  }
  return response.json();
}

async function ensureExtensionTarget(input, port) {
  let launch = null;
  try {
    const targets = await jsonGet(`http://127.0.0.1:${port}/json/list`);
    const expectedExtensionId = await extensionIdFromFile(input.context.projectRoot);
    const target =
      (expectedExtensionId ? extensionTarget(Array.isArray(targets) ? targets : [], expectedExtensionId) : null) ??
      extensionTarget(Array.isArray(targets) ? targets : []);
    if (target?.webSocketDebuggerUrl) return { target, launch };
  } catch (error) {
    if (!autolaunchEnabled(input)) throw error;
  }
  if (!autolaunchEnabled(input)) {
    throw new Error(`No extension page target found on CDP port ${port}. Launch the extension runtime first, or set METAMASK_RECIPE_EXTENSION_AUTOLAUNCH=1 to launch an existing dist/chrome.`);
  }
  launch = await launchExistingDistRuntime(input, port);
  let targets = await retryJsonGet(`http://127.0.0.1:${port}/json/list`, 45000);
  const expectedExtensionId = await extensionIdFromFile(input.context.projectRoot);
  let target = expectedExtensionId ? extensionTarget(Array.isArray(targets) ? targets : [], expectedExtensionId) : null;
  if (!target?.webSocketDebuggerUrl) {
    const extensionId =
      expectedExtensionId ??
      extensionIdFromAnyTarget(Array.isArray(targets) ? targets : []);
    if (!extensionId) {
      throw new Error(`Autolaunch started Chrome on CDP port ${port}, but no extension ID could be derived from CDP targets or the recipe runtime extension.id.`);
    }
    await openExtensionHomePage(port, extensionId);
    targets = await retryJsonGet(`http://127.0.0.1:${port}/json/list`, 15000);
    target = extensionTarget(Array.isArray(targets) ? targets : [], extensionId);
  }
  if (!target?.webSocketDebuggerUrl) {
    throw new Error(`Autolaunch started Chrome on CDP port ${port}, but no extension page target was found.`);
  }
  return { target, launch };
}

export async function loadInput() {
  const inputPath = process.argv[2] || process.env.METAMASK_RECIPE_ADAPTER_INPUT;
  if (!inputPath) throw new Error('Missing live adapter input path.');
  return JSON.parse(await readFile(inputPath, 'utf8'));
}

export async function writeOutput(input, output) {
  await writeFile(input.outputPath, `${JSON.stringify(output, null, 2)}\n`);
}

export async function withExtensionPage(input, callback) {
  const port = cdpPort(input);
  const { target, launch } = await ensureExtensionTarget(input, port);
  const session = await CdpSession.connect(target.webSocketDebuggerUrl);
  try {
    const extensionId = extensionIdFromTarget(target);
    const origin = `chrome-extension://${extensionId}`;
    const page = new ExtensionPage(session, origin, target, port);
    await session.call('Runtime.enable');
    await session.call('Page.enable');
    const result = await callback(page);
    return { ...result, cdpPort: port, targetUrl: target.url, runtimeLaunch: launch };
  } finally {
    session.close();
  }
}

export class ExtensionPage extends CdpWebPage {
  constructor(session, origin, target, port) {
    super(session);
    this.origin = origin;
    this.target = target;
    this.port = port;
  }

  async navigateHash(hash) {
    const normalizedHash = String(hash || '').startsWith('#') ? hash : `#${hash || '/'}`;
    const href = `${this.origin}/home.html${normalizedHash}`;
    return this.navigate(href);
  }

  async readPositions() {
    return this.evaluate(`(async () => {
      const request = globalThis.stateHooks?.submitRequestToBackground;
      const manager = globalThis.stateHooks?.getPerpsStreamManager?.();
      const cached = manager?.positions?.cache;
      if (typeof request === 'function') {
        const result = await Promise.race([
          request('perpsGetPositions', []).then((positions) => ({ ok: true, positions })),
          new Promise((resolve) => setTimeout(() => resolve({ ok: false, timeout: true }), 5000)),
        ]);
        if (result.ok && Array.isArray(result.positions)) {
          return { available: true, source: 'background-perpsGetPositions', positions: result.positions };
        }
      }
      return {
        available: Array.isArray(cached),
        source: 'perps-stream-manager-cache',
        initialized: Boolean(manager?.isInitialized?.()),
        connected: Boolean(manager?.positions?.isConnected),
        positions: Array.isArray(cached) ? cached : [],
      };
    })()`);
  }

  async screenshot(contextOrInput, relPath, metadata = {}) {
    if (contextOrInput?.context) {
      const options = {
        label: contextOrInput.node?.description || `${contextOrInput.action} screenshot`,
        category: 'evidence',
        timeoutMs: contextOrInput.node?.timeout_ms,
        ...metadata,
      };
      if (contextOrInput.node?.screenshot_mode === 'dom_raster' || process.env.METAMASK_RECIPE_EXTENSION_SCREENSHOT_MODE === 'dom-raster') {
        throw new Error('Extension ui.screenshot no longer supports DOM raster screenshots. Use capture-helper snapshot evidence.');
      }
      return captureHelperSnapshot(this, contextOrInput.context, relPath, options);
    }
    if (process.env.METAMASK_RECIPE_EXTENSION_SCREENSHOT_MODE === 'dom-raster') {
      throw new Error('Extension screenshots no longer support DOM raster mode. Use capture-helper snapshot evidence.');
    }
    return captureHelperSnapshot(this, contextOrInput, relPath, metadata);
  }
}

export function marketSymbol(input) {
  return normalizeMarketSymbol(input.node?.market ?? input.node?.symbol ?? 'BTC');
}

export function normalizeMarketSymbol(rawSymbol) {
  const raw = String(rawSymbol);
  if (raw.includes(':')) {
    const [source, ...symbolParts] = raw.split(':');
    return `${source.toLowerCase()}:${symbolParts.join(':').toUpperCase()}`;
  }
  return raw.toUpperCase();
}

export async function runAdapter(callback) {
  const input = await loadInput();
  const output = await callback(input);
  await writeOutput(input, output);
}
