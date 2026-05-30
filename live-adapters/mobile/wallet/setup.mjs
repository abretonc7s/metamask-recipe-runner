import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { bridgeCommand, runAdapter } from '../platform/bridge.mjs';

async function fixtureProfile(projectRoot) {
  const candidates = [
    path.join(projectRoot, '.agent/wallet-fixture.json'),
    path.join(projectRoot, 'temp/runtime/wallet-fixture.json'),
    path.join(projectRoot, 'scripts/perps/agentic/wallet-fixture.json'),
  ];
  for (const candidate of candidates) {
    try {
      const fixture = JSON.parse(await readFile(candidate, 'utf8'));
      if (typeof fixture.password !== 'string' || fixture.password.length === 0) {
        throw new Error(
          `Mobile wallet fixture ${path.relative(projectRoot, candidate)} is missing password.`,
        );
      }
      if (!Array.isArray(fixture.accounts) || fixture.accounts.length === 0) {
        throw new Error(
          `Mobile wallet fixture ${path.relative(projectRoot, candidate)} must define at least one account.`,
        );
      }
      return {
        path: path.relative(projectRoot, candidate),
        password: fixture.password,
        accounts: fixture.accounts.length,
        hasPassword: true,
      };
    } catch (error) {
      if (error?.code === 'ENOENT') continue;
      throw error;
    }
  }
  throw new Error('No wallet fixture found for Mobile setup.');
}

function selectedStatus(status, input) {
  if (!Array.isArray(status)) {
    return status && typeof status === 'object' ? status : null;
  }
  const preferredDevices = [
    input.node?.ios_simulator,
    input.node?.simulator,
    input.node?.android_device,
    input.node?.adb_serial,
    process.env.IOS_SIMULATOR,
    process.env.ANDROID_DEVICE,
    process.env.ADB_SERIAL,
  ].filter((value) => typeof value === 'string' && value.length > 0);
  for (const preferredDevice of preferredDevices) {
    const match = status.find((entry) => entry?.deviceName === preferredDevice);
    if (match) return match;
  }
  return (
    status.find((entry) => entry?.account) ??
    status.find((entry) => entry && typeof entry === 'object') ??
    null
  );
}

function hasSelectedAccount(status, input) {
  return Boolean(selectedStatus(status, input)?.account);
}

async function verifiedStatus(input, password) {
  const before = await bridgeCommand(input, ['status']);
  if (hasSelectedAccount(before, input)) return { status: before, unlockedDuringSetup: false };

  await bridgeCommand(input, ['unlock', String(password)]);
  const after = await bridgeCommand(input, ['status']);
  if (!hasSelectedAccount(after, input)) {
    throw new Error(
      `Mobile wallet setup did not expose a selected account after unlock; status=${JSON.stringify(after)}`,
    );
  }
  return { status: after, unlockedDuringSetup: true };
}

runAdapter(async (input) => {
  const fixture = await fixtureProfile(input.context.projectRoot);
  const runtime = await verifiedStatus(input, fixture.password);
  return {
    action: input.action,
    setup: 'preseeded-mobile-fixture-verified',
    fixture: {
      path: fixture.path,
      accounts: fixture.accounts,
      hasPassword: fixture.hasPassword,
    },
    runtimeState: selectedStatus(runtime.status, input),
    unlockedDuringSetup: runtime.unlockedDuringSetup,
    proofPath: 'mobile-fixture-profile',
  };
});
