#!/usr/bin/env node
// inject.mjs — install the extension harness overlay
// (formerly: scripts/inject-extension-harness.mjs)
//
// Purpose:
//   Installs the runner delegate, action manifests, recipe snapshots and
//   helper scripts into the target's ignored harness dir (overlay only).
//
// Inputs (flags / env):
//   --target <metamask-extension> (default $PWD)
//   --no-git-exclude              skip .git/info/exclude updates
//   env RECIPE_HARNESS_ROOT, METAMASK_RUNNER_DIR,
//   METAMASK_RUNNER_PROTOCOL_ROOT > FARMSLOT_ROOT > <runner>/.farmslot-root
//
// Outputs:
//   <harness>/{manifest.json,action-manifest.json,runner/,scripts/,
//   installed-scripts.sha256,added-git-exclude}; pass JSON on stdout.
//   Exit 0 — installed; 2 — bad args; non-zero — refusal (not an extension
//   checkout, symlink path component) via thrown error.
//
// Never touches: product source files; anything outside the target's
// harness dir and the target's .git/info/exclude.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import process from 'node:process';
import { recipeHarnessRoot } from '../lib/recipe-paths.mjs';

function usage() {
  console.error('Usage: inject-extension-harness.mjs [--target <metamask-extension>] [--no-git-exclude]');
}

let target = process.cwd();
let gitExclude = true;
for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg === '--target') {
    if (i + 1 >= process.argv.length) { usage(); process.exit(2); }
    target = process.argv[++i];
  } else if (arg === '--no-git-exclude') {
    gitExclude = false;
  } else if (arg === '-h' || arg === '--help') {
    usage(); process.exit(0);
  } else {
    console.error(`inject-extension-harness: unknown arg: ${arg}`);
    usage(); process.exit(2);
  }
}

target = path.resolve(target);
const runnerRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const harnessRoot = harnessRootValue();
const harnessRel = `${harnessRoot}/extension`;
const harnessDir = path.join(target, harnessRel);
const runnerDir = process.env.METAMASK_RUNNER_DIR || runnerRoot;
const runnerRevision = gitHead(runnerDir);
const protocolRoot = process.env.METAMASK_RUNNER_PROTOCOL_ROOT || process.env.METAMASK_RUNNER_FARMSLOT_ROOT || process.env.FARMSLOT_ROOT || configuredProtocolRoot(runnerDir);

assertExtensionRoot(target);
for (const rel of [harnessRel, `${harnessRel}/runner`, `${harnessRel}/action-manifest.json`]) {
  refuseSymlinkDestination(target, rel);
}

fs.rmSync(path.join(harnessDir, 'runner'), { recursive: true, force: true });
fs.mkdirSync(path.join(harnessDir, 'runner/bin'), { recursive: true });
fs.mkdirSync(path.join(harnessDir, 'runner/manifests'), { recursive: true });
fs.mkdirSync(path.join(harnessDir, 'runner/recipes'), { recursive: true });
fs.rmSync(path.join(harnessDir, 'scripts'), { recursive: true, force: true });
fs.mkdirSync(path.join(harnessDir, 'scripts/lib'), { recursive: true });

const delegate = [
  '#!/usr/bin/env bash',
  'set -euo pipefail',
  protocolRoot ? `export FARMSLOT_ROOT=\${FARMSLOT_ROOT:-${shellQuote(protocolRoot)}}` : null,
  `exec ${shellQuote(path.join(runnerDir, 'bin/metamask-recipe'))} "$@"`,
].filter(Boolean).join('\n') + '\n';
fs.writeFileSync(path.join(harnessDir, 'runner/bin/metamask-recipe'), delegate, { mode: 0o755 });
if (protocolRoot) fs.writeFileSync(path.join(harnessDir, 'runner/.farmslot-root'), `${protocolRoot}\n`);
fs.writeFileSync(path.join(harnessDir, 'runner/.runner-source'), `${runnerDir}\n`);
copyFile(path.join(runnerDir, 'manifests/mobile.action-manifest.json'), path.join(harnessDir, 'runner/manifests/mobile.action-manifest.json'));
copyFile(path.join(runnerDir, 'manifests/extension.action-manifest.json'), path.join(harnessDir, 'runner/manifests/extension.action-manifest.json'));
copyFile(path.join(runnerDir, 'manifests/extension.action-manifest.json'), path.join(harnessDir, 'action-manifest.json'));
copyDir(path.join(runnerDir, 'recipes'), path.join(harnessDir, 'runner/recipes'));
copyDir(path.join(runnerDir, 'scripts/extension'), path.join(harnessDir, 'scripts'));
// Moved features live in orchestration/; overwrite the forwarding shims so
// the installed copy keeps the real scripts (same installed layout).
copyFile(path.join(runnerDir, 'orchestration/extension/launch-browser.cjs'), path.join(harnessDir, 'scripts/launch-browser.cjs'));
// installed back-compat alias: callers of the pre-rename installed name
copyFile(path.join(runnerDir, 'orchestration/extension/launch-browser.cjs'), path.join(harnessDir, 'scripts/launch-chrome-detached.cjs'));
copyFile(path.join(runnerDir, 'orchestration/extension/launch.sh'), path.join(harnessDir, 'scripts/launch.sh'));
copyFile(path.join(runnerDir, 'orchestration/extension/live.sh'), path.join(harnessDir, 'scripts/live.sh'));
copyFile(path.join(runnerDir, 'orchestration/extension/start-watch.sh'), path.join(harnessDir, 'scripts/start-watch.sh'));
copyFile(path.join(runnerDir, 'orchestration/extension/snapshot-dist.sh'), path.join(harnessDir, 'scripts/snapshot-dist.sh'));
copyFile(path.join(runnerDir, 'orchestration/extension/seed-fixture.sh'), path.join(harnessDir, 'scripts/seed-fixture.sh'));
copyFile(path.join(runnerDir, 'recipe/extension/sidepanel-toggle.sh'), path.join(harnessDir, 'scripts/sidepanel-toggle.sh'));
copyFile(path.join(runnerDir, 'recipe/extension/extension-readiness.mjs'), path.join(harnessDir, 'scripts/extension-readiness.mjs'));
copyFile(path.join(runnerDir, 'recipe/extension/wallet-fixture-state.cjs'), path.join(harnessDir, 'scripts/wallet-fixture-state.cjs'));
copyFile(path.join(runnerDir, 'recipe/extension/verify.sh'), path.join(harnessDir, 'scripts/verify.sh'));
copyFile(path.join(runnerDir, 'orchestration/extension/refresh-build.sh'), path.join(harnessDir, 'scripts/refresh-build.sh'));
copyFile(path.join(runnerDir, 'orchestration/extension/ensure-browser.sh'), path.join(harnessDir, 'scripts/reopen-browser.sh'));
copyFile(path.join(runnerDir, 'orchestration/lib/harness-path.sh'), path.join(harnessDir, 'scripts/lib/harness-path.sh'));
copyFile(path.join(runnerDir, 'orchestration/lib/path-defaults.json'), path.join(harnessDir, 'scripts/lib/path-defaults.json'));
copyFile(path.join(runnerDir, 'orchestration/lib/recipe-paths.mjs'), path.join(harnessDir, 'scripts/lib/recipe-paths.mjs'));
copyFile(path.join(runnerDir, 'orchestration/lib/json-field.sh'), path.join(harnessDir, 'scripts/lib/json-field.sh'));
makeExecutableTree(path.join(harnessDir, 'scripts'));
fs.writeFileSync(path.join(harnessDir, 'installed-scripts.sha256'), `${dirContentHash(path.join(harnessDir, 'scripts'))}\n`);

// cleanup script: orchestration home once moved; legacy scripts/ home until then.
const cleanupScript = [
  path.join(runnerDir, 'orchestration/extension/cleanup.mjs'),
  path.join(runnerDir, 'scripts/cleanup-extension-harness.mjs'),
].find((candidate) => fs.existsSync(candidate)) || path.join(runnerDir, 'scripts/cleanup-extension-harness.mjs');
const cleanupCommand = `RECIPE_HARNESS_ROOT=${harnessRoot} ${shellQuote(cleanupScript)} --target ${shellQuote(target)}`;
const manifest = {
  adapter: 'extension',
  installedAt: new Date().toISOString(),
  source: {
    runnerDir,
    runnerRevision,
    runnerSourceKind: process.env.METAMASK_RUNNER_SOURCE_KIND || 'runner-self',
  },
  target,
  protocolVersion: 'v1',
  actionManifestPath: `${harnessRel}/action-manifest.json`,
  runnerEntrypoint: `${harnessRel}/runner/bin/metamask-recipe`,
  installedPaths: [`${harnessRel}/scripts`, `${harnessRel}/runner`, `${harnessRel}/action-manifest.json`, `${harnessRel}/manifest.json`],
  runtimeHelpers: {
    live: `${harnessRel}/scripts/live.sh`,
    refreshBuild: `${harnessRel}/scripts/refresh-build.sh`,
    reopenBrowser: `${harnessRel}/scripts/reopen-browser.sh`,
    sidepanelToggle: `${harnessRel}/scripts/sidepanel-toggle.sh`,
  },
  patchedFiles: [],
  backupDir: null,
  cleanupCommand,
  productDiffExcludes: [`:(exclude)${harnessRoot}`],
};
fs.writeFileSync(path.join(harnessDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);

if (gitExclude) addGitExclude(target, `${harnessRoot}/`, harnessDir);

console.log(JSON.stringify({ status: 'pass', adapter: 'extension', harnessDir, manifestPath: path.join(harnessDir, 'manifest.json'), runnerEntrypoint: manifest.runnerEntrypoint }, null, 2));

function harnessRootValue() {
  return recipeHarnessRoot();
}

function assertExtensionRoot(dir) {
  const packageJson = path.join(dir, 'package.json');
  if (!fs.existsSync(packageJson)) throw new Error(`Target is not a MetaMask Extension checkout: ${dir}`);
  const text = fs.readFileSync(packageJson, 'utf8');
  if (!text.includes('metamask-extension') && !path.basename(dir).startsWith('metamask-extension')) {
    throw new Error(`Target is not a MetaMask Extension checkout: ${dir}`);
  }
}

function refuseSymlinkDestination(root, rel) {
  let current = root;
  for (const part of rel.split('/').filter(Boolean)) {
    current = path.join(current, part);
    if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) {
      throw new Error(`Refusing extension recipe harness install: ${rel} contains symlink component ${current}`);
    }
  }
}

function copyFile(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function copyDir(src, dest) {
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });
  if (!fs.existsSync(src)) return;
  fs.cpSync(src, dest, { recursive: true });
}

function makeExecutableTree(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      makeExecutableTree(file);
    } else if (/\.(?:sh|js|cjs|mjs)$/u.test(entry.name)) {
      fs.chmodSync(file, 0o755);
    }
  }
}

function dirContentHash(dir) {
  const files = [];
  collectFiles(dir, files);
  const hashes = files.sort().map((file) => {
    const relative = path.relative(dir, file);
    const content = spawnSync('shasum', ['-a', '256', file], { encoding: 'utf8' });
    if (content.status !== 0) throw new Error(`Failed to hash ${file}: ${content.stderr}`);
    return `${content.stdout.trim()}  ${relative}`;
  }).join('\n');
  const result = spawnSync('shasum', ['-a', '256'], { input: hashes, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`Failed to hash extension scripts: ${result.stderr}`);
  return result.stdout.trim().split(/\s+/u)[0];
}

function collectFiles(dir, files) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) collectFiles(file, files);
    else if (entry.isFile()) files.push(file);
  }
}

function gitHead(dir) {
  const result = spawnSync('git', ['-C', dir, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  return result.status === 0 ? result.stdout.trim() : 'unknown';
}

function configuredProtocolRoot(dir) {
  const file = path.join(dir, '.farmslot-root');
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8').trim() : '';
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function addGitExclude(repo, entry, harnessDir) {
  const check = spawnSync('git', ['-C', repo, 'check-ignore', '-q', entry.replace(/\/$/u, '')]);
  if (check.status === 0) return;
  const gitDirResult = spawnSync('git', ['-C', repo, 'rev-parse', '--git-dir'], { encoding: 'utf8' });
  if (gitDirResult.status !== 0) return;
  let gitDir = gitDirResult.stdout.trim();
  if (!path.isAbsolute(gitDir)) gitDir = path.join(repo, gitDir);
  const excludeFile = path.join(gitDir, 'info/exclude');
  fs.mkdirSync(path.dirname(excludeFile), { recursive: true });
  const existing = fs.existsSync(excludeFile) ? fs.readFileSync(excludeFile, 'utf8').split('\n') : [];
  if (!existing.includes(entry)) {
    fs.appendFileSync(excludeFile, `${entry}\n`);
    fs.appendFileSync(path.join(harnessDir, 'added-git-exclude'), `${entry}\n`);
  }
}
