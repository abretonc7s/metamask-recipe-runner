import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function loadInput() {
  const inputPath = process.argv[2] || process.env.METAMASK_RECIPE_ADAPTER_INPUT;
  if (!inputPath) throw new Error('Missing live adapter input path.');
  return JSON.parse(await readFile(inputPath, 'utf8'));
}

export async function writeOutput(input, output) {
  await writeFile(input.outputPath, `${JSON.stringify(output, null, 2)}\n`);
}

export async function runAdapter(callback) {
  const input = await loadInput();
  const output = await callback(input);
  await writeOutput(input, output);
}

function bridgeScript(input) {
  if (process.env.METAMASK_RECIPE_MOBILE_BRIDGE_SCRIPT) {
    return process.env.METAMASK_RECIPE_MOBILE_BRIDGE_SCRIPT;
  }
  return path.join(runtimeDir(), 'cdp-bridge.cjs');
}

function runtimeDir() {
  return fileURLToPath(new URL('../bridge-runtime', import.meta.url));
}

export function bridgeEnv(input) {
  /** @type {NodeJS.ProcessEnv} */
  const env = {
    ...process.env,
    CDP_TIMEOUT: String(input.node?.cdp_timeout_ms ?? process.env.CDP_TIMEOUT ?? '10000'),
  };
  const target = resolveMobileTarget(input);
  const watcherPort = target.watcherPort;
  const simulator = target.iosSimulator;
  const androidDevice = target.androidDevice;
  const adbSerial = target.adbSerial;
  if (watcherPort !== undefined && watcherPort !== null && String(watcherPort) !== '') env.WATCHER_PORT = String(watcherPort);
  if (simulator !== undefined && simulator !== null && String(simulator) !== '') env.IOS_SIMULATOR = String(simulator);
  if (androidDevice !== undefined && androidDevice !== null && String(androidDevice) !== '') env.ANDROID_DEVICE = String(androidDevice);
  if (adbSerial !== undefined && adbSerial !== null && String(adbSerial) !== '') {
    env.ADB_SERIAL = String(adbSerial);
    env.ANDROID_SERIAL = String(adbSerial);
  }
  return env;
}

function resolveMobileTarget(input) {
  const watcherPort = input.node?.watcher_port ?? input.node?.metro_port ?? input.node?.cdp_port ?? process.env.WATCHER_PORT ?? process.env.CDP_PORT ?? process.env.RECIPE_CDP_PORT;
  const iosSimulator = input.node?.simulator ?? input.node?.ios_simulator ?? process.env.IOS_SIMULATOR;
  const androidDevice = input.node?.android_device ?? process.env.ANDROID_DEVICE;
  const adbSerial = input.node?.adb_serial ?? process.env.ADB_SERIAL ?? process.env.ANDROID_SERIAL ?? androidDevice;
  return { watcherPort, iosSimulator, androidDevice, adbSerial };
}

export async function bridgeCommand(input, args) {
  const script = bridgeScript(input);
  const result = await new Promise((resolve, reject) => {
    const timeoutMs = Number(input.node?.bridge_timeout_ms ?? input.node?.cdp_timeout_ms ?? process.env.CDP_TIMEOUT ?? 30000);
    const child = spawn(process.execPath, [script, ...args], {
      cwd: input.context.projectRoot,
      env: { ...bridgeEnv(input), APP_ROOT: input.context.projectRoot },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    const timer = Number.isFinite(timeoutMs) && timeoutMs > 0
      ? setTimeout(() => {
        if (settled) return;
        settled = true;
        child.kill('SIGTERM');
        setTimeout(() => {
          if (!child.killed) child.kill('SIGKILL');
        }, 1000);
        resolve({ exitCode: null, stdout, stderr, timedOut: true, timeoutMs });
      }, timeoutMs)
      : null;
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', (error) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      reject(error);
    });
    child.on('close', (exitCode) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      resolve({ exitCode, stdout, stderr, timedOut: false, timeoutMs });
    });
  });
  if (result.timedOut) {
    const command = ['node', path.relative(input.context.projectRoot, script), ...redactBridgeArgs(args)].join(' ');
    throw new Error(`Mobile CDP bridge command timed out after ${result.timeoutMs}ms: ${command}`);
  }
  if (result.exitCode !== 0) {
    const command = ['node', path.relative(input.context.projectRoot, script), ...redactBridgeArgs(args)].join(' ');
    throw new Error(`Mobile CDP bridge command failed: ${command}\n${redactBridgeOutput(result.stderr || result.stdout, sensitiveBridgeArgs(args))}`);
  }
  try {
    const parsed = JSON.parse(result.stdout);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed) && parsed.ok === false) {
      throw new Error(
        `Mobile CDP bridge command reported failure for ${redactBridgeArgs(args).join(' ')}: ${redactBridgeOutput(JSON.stringify(parsed), sensitiveBridgeArgs(args))}`,
      );
    }
    return parsed;
  } catch (error) {
    if (String(error?.message ?? '').startsWith('Mobile CDP bridge command reported failure')) {
      throw error;
    }
    throw new Error(`Mobile CDP bridge returned non-JSON output for ${args[0]}: ${error.message}\n${result.stdout}`);
  }
}

function redactBridgeArgs(args) {
  const command = String(args[0] ?? '');
  if (command === 'unlock' && args.length > 1) return [command, '<redacted-password>', ...args.slice(2)];
  return args.map((arg) => String(arg));
}

function redactBridgeOutput(output, args) {
  let redacted = String(output ?? '');
  for (const arg of args) {
    const value = String(arg ?? '');
    if (value.length < 6) continue;
    redacted = redacted.split(value).join('<redacted>');
  }
  return redacted;
}

function sensitiveBridgeArgs(args) {
  const command = String(args[0] ?? '');
  if (command === 'unlock' && args.length > 1) return [args[1]];
  return [];
}

function parseMaybeJson(value) {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    // The bridge can legitimately return plain strings for eval results; keep
    // the original value when it is not a JSON-encoded payload.
    return value;
  }
}

export async function evalAsync(input, expression) {
  const deadline = Date.now() + Number(input.node?.controller_ready_timeout_ms ?? 30000);
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      return parseMaybeJson(await bridgeCommand(input, ['eval-async', expression]));
    } catch (error) {
      lastError = error;
      if (!String(error?.message ?? error).includes('CLIENT_NOT_INITIALIZED')) throw error;
      await sleep(500);
    }
  }
  throw lastError ?? new Error('Timed out waiting for Mobile async evaluation.');
}

export async function evalSync(input, expression) {
  return parseMaybeJson(await bridgeCommand(input, ['eval', expression]));
}

export async function navigate(input, route, params = {}) {
  const navigation = await bridgeCommand(input, ['navigate', route, JSON.stringify(params)]);
  const verifiedRoute = navigation && typeof navigation === 'object' && navigation.navigated
    ? String(navigation.navigated)
    : String(route);
  const currentRoute = await waitForRoute(input, verifiedRoute, Number(input.node?.navigation_timeout_ms ?? 15000));
  return { ...navigation, currentRoute, verifiedRoute };
}

function routeName(route) {
  return route && typeof route === 'object' ? String(route.name ?? '') : '';
}

export async function waitForRoute(input, expectedRoute, timeoutMs = 15000) {
  const expected = String(expectedRoute);
  const deadline = Date.now() + timeoutMs;
  let lastRoute = null;
  while (Date.now() < deadline) {
    lastRoute = await bridgeCommand(input, ['get-route']);
    if (routeName(lastRoute) === expected) return lastRoute;
    await sleep(250);
  }
  throw new Error(`Timed out waiting for Mobile route ${expected}; last route was ${JSON.stringify(lastRoute)}`);
}

export async function simulatorScreenshot(input, relPath) {
  const targetInfo = resolveMobileTarget(input);
  const androidTarget = targetInfo.androidDevice;
  const adbSerial = targetInfo.adbSerial;
  const platform = String(input.node?.platform ?? process.env.PLATFORM ?? '').toLowerCase();
  if (androidTarget || adbSerial || platform === 'android') {
    return androidScreenshot(input, relPath, adbSerial);
  }
  const target = targetInfo.iosSimulator;
  if (!target) {
    throw new Error('iOS screenshot requires node.simulator, node.ios_simulator, or IOS_SIMULATOR so the proof is tied to the same device as the bridge commands.');
  }
  const { relative, absolute } = resolveArtifactPath(input.context.artifactsDir, relPath || `screenshots/${input.context.nodeId}.png`);
  await mkdir(path.dirname(absolute), { recursive: true });
  const result = await new Promise((resolve, reject) => {
    const child = spawn('xcrun', ['simctl', 'io', String(target), 'screenshot', absolute], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (exitCode) => resolve({ exitCode, stdout, stderr }));
  });
  if (result.exitCode !== 0) {
    throw new Error(`simctl screenshot failed for ${target}: ${result.stderr || result.stdout}`);
  }
  return {
    path: relative,
    type: 'screenshot',
    nodeId: input.context.nodeId,
    label: input.node?.description || `${input.action} screenshot`,
    category: 'evidence',
  };
}

async function androidScreenshot(input, relPath, androidDevice) {
  const { relative, absolute } = resolveArtifactPath(input.context.artifactsDir, relPath || `screenshots/${input.context.nodeId}.png`);
  await mkdir(path.dirname(absolute), { recursive: true });
  const args = [];
  if (androidDevice) args.push('-s', String(androidDevice));
  args.push('exec-out', 'screencap', '-p');
  const result = await new Promise((resolve, reject) => {
    const child = spawn('adb', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    const stdout = [];
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout.push(Buffer.from(chunk)); });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (exitCode) => resolve({ exitCode, stdout: Buffer.concat(stdout), stderr }));
  });
  if (result.exitCode !== 0) {
    throw new Error(`adb screenshot failed${androidDevice ? ` for ${androidDevice}` : ''}: ${result.stderr}`);
  }
  await writeFile(absolute, result.stdout);
  return {
    path: relative,
    type: 'screenshot',
    nodeId: input.context.nodeId,
    label: input.node?.description || `${input.action} screenshot`,
    category: 'evidence',
  };
}

function resolveArtifactPath(artifactsDir, relativePath) {
  const raw = String(relativePath);
  if (path.isAbsolute(raw) || /^[A-Za-z]:/.test(raw)) {
    throw new Error(`Artifact path must be relative: ${raw}`);
  }
  const normalized = path.normalize(raw);
  if (normalized === '..' || normalized.startsWith(`..${path.sep}`)) {
    throw new Error(`Artifact path must not escape artifacts directory: ${raw}`);
  }
  return {
    relative: normalized.split(path.sep).join('/'),
    absolute: path.join(artifactsDir, normalized),
  };
}
