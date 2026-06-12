#!/usr/bin/env node
// launch-browser.cjs — per-instance isolated detached Chrome spawn
// (formerly: scripts/extension/launch-chrome-detached.cjs)
//
// Purpose:
//   Spawns a detached Chrome bound to 127.0.0.1:<cdp-port> with its own
//   profile and the runtime dist loaded as an unpacked extension.
//
// Inputs (flags, all required):
//   --cdp-port <port> --chrome-bin <path> --profile <dir>
//   --extension-dir <dist> --chrome-log <file> --chrome-pid <file>
//   Env is sanitized for the child (DYLD_*, PYTHON*, BUNDLED_DEBUGPY_PATH).
//
// Outputs:
//   <chrome-pid> pid file; <chrome-log> append-log.
//   Exit 0 — spawned; non-zero — invalid/missing args, missing chrome binary,
//   or missing dist manifest (thrown error message on stderr).
//
// Never touches: the extension dist (read-only), anything outside the
// profile/log/pid paths it was given.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');

if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log(
    'Usage: launch-browser.cjs --cdp-port <port> --chrome-bin <path> --profile <dir> --extension-dir <dist> --chrome-log <file> --chrome-pid <file>',
  );
  process.exit(0);
}

const args = parseArgs(process.argv.slice(2));
const cdpPort = Number(args['cdp-port']);
if (!Number.isInteger(cdpPort) || cdpPort <= 0) {
  throw new Error(`Invalid --cdp-port: ${args['cdp-port'] || ''}`);
}
for (const key of ['chrome-bin', 'profile', 'extension-dir', 'chrome-log', 'chrome-pid']) {
  if (!args[key]) throw new Error(`Missing --${key}`);
}
if (!fs.existsSync(args['chrome-bin'])) throw new Error(`Chrome binary not found: ${args['chrome-bin']}`);
if (!fs.existsSync(path.join(args['extension-dir'], 'manifest.json'))) {
  throw new Error(`Extension dist manifest not found: ${path.join(args['extension-dir'], 'manifest.json')}`);
}

fs.mkdirSync(args.profile, { recursive: true });
fs.mkdirSync(path.dirname(args['chrome-log']), { recursive: true });
fs.mkdirSync(path.dirname(args['chrome-pid']), { recursive: true });

const logFd = fs.openSync(args['chrome-log'], 'a');
let child;
try {
  child = spawn(args['chrome-bin'], [
    `--user-data-dir=${args.profile}`,
    '--remote-debugging-address=127.0.0.1',
    `--remote-debugging-port=${cdpPort}`,
    '--no-first-run',
    '--disable-first-run-ui',
    '--disable-default-apps',
    '--disable-popup-blocking',
    '--disable-extensions-file-access-check',
    '--disable-extensions-content-verification',
    '--disable-features=ExtensionContentVerification,DisableLoadExtensionCommandLineSwitch',
    `--disable-extensions-except=${args['extension-dir']}`,
    `--load-extension=${args['extension-dir']}`,
    'chrome://extensions/',
  ], {
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
    stdio: ['ignore', logFd, logFd],
  });
} finally {
  fs.closeSync(logFd);
}
child.unref();
fs.writeFileSync(args['chrome-pid'], `${child.pid}\n`);

function parseArgs(argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) throw new Error(`Unknown positional argument: ${arg}`);
    if (i + 1 >= argv.length) throw new Error(`Missing value for ${arg}`);
    parsed[arg.slice(2)] = argv[i + 1];
    i += 1;
  }
  return parsed;
}
