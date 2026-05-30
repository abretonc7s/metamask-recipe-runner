import { bridgeCommand, runAdapter } from '../platform/bridge.mjs';

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

runAdapter(async (input) => {
  const status = selectedStatus(await bridgeCommand(input, ['status']), input);
  const output = {
    action: input.action,
    source: 'mobile-agentic-status',
    account: status?.account ?? null,
    route: status?.route ?? null,
    deviceName: status?.deviceName ?? null,
    platform: status?.platform ?? 'mobile',
    redacted: true,
    proofPath: 'agentic-wallet-status',
  };
  return output;
});
