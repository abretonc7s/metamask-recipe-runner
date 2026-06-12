#!/usr/bin/env node
// doctor.mjs — orchestration feature-surface doctor
//
// Purpose:
//   Verifies orchestration/manifest.json against reality: every entry point
//   exists; every script entry answers --help with exit 0; and every script
//   under orchestration/{mobile,extension,core} is listed (no doc drift).
//
// Inputs (flags): --json (machine-readable report)
// Outputs: per-feature lines (or JSON report) on stdout.
//   Exit 0 — surface healthy; 1 — missing entry, failing --help, or
//   unlisted script; 2 — bad args.
// Never touches: anything (read-only + --help subprocesses).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

let json = false;
for (const arg of process.argv.slice(2)) {
  if (arg === '--json') json = true;
  else if (arg === '-h' || arg === '--help') {
    console.log('Usage: doctor.mjs [--json]');
    process.exit(0);
  } else {
    console.error(`Unknown arg: ${arg}`);
    process.exit(2);
  }
}

const orchestrationDir = path.dirname(fileURLToPath(import.meta.url));
const runnerRoot = path.resolve(orchestrationDir, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(orchestrationDir, 'manifest.json'), 'utf8'));

const results = [];
for (const feature of manifest.features) {
  const entryAbs = path.join(runnerRoot, feature.entry);
  const checks = { exists: fs.existsSync(entryAbs), help: null };
  if (checks.exists && (feature.kind === 'bash' || feature.kind === 'node')) {
    const runner = feature.kind === 'bash' ? 'bash' : process.execPath;
    const run = spawnSync(runner, [entryAbs, '--help'], { encoding: 'utf8', timeout: 30000 });
    checks.help = run.status === 0;
  }
  const ok = checks.exists && (checks.help === null || checks.help === true);
  results.push({ id: feature.id, entry: feature.entry, kind: feature.kind, ...checks, ok });
}

// drift guard: every script in the orchestration trees must be listed
const listed = new Set(manifest.features.map((feature) => feature.entry));
const unlisted = [];
for (const platform of ['mobile', 'extension', 'core', 'lib']) {
  const dir = path.join(orchestrationDir, platform);
  if (!fs.existsSync(dir)) continue;
  for (const entry of fs.readdirSync(dir)) {
    const rel = `orchestration/${platform}/${entry}`;
    if (!/\.(?:sh|mjs|cjs|json)$/u.test(entry)) continue;
    if (!listed.has(rel)) unlisted.push(rel);
  }
}

const failed = results.filter((result) => !result.ok);
const status = failed.length === 0 && unlisted.length === 0 ? 'pass' : 'fail';
if (json) {
  console.log(JSON.stringify({ status, features: results, unlisted }, null, 2));
} else {
  for (const result of results) {
    console.log(`${result.ok ? 'ok  ' : 'FAIL'} ${result.id} (${result.entry})${result.help === false ? ' [--help failed]' : ''}${result.exists ? '' : ' [missing]'}`);
  }
  for (const rel of unlisted) console.log(`FAIL unlisted script not in manifest: ${rel}`);
  console.log(`orchestration surface: ${status} (${results.length - failed.length}/${results.length} features, ${unlisted.length} unlisted)`);
}
process.exit(status === 'pass' ? 0 : 1);
