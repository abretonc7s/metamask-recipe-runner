#!/usr/bin/env node
// cleanup-extension-harness.mjs — remove the extension harness overlay
//
// Purpose:
//   Removes exactly the .git/info/exclude entries the install recorded,
//   then deletes the target's extension harness dir. Overlay-only: no
//   product files are involved.
//
// Inputs (flags / env):
//   --target <metamask-extension> (default $PWD); env RECIPE_HARNESS_ROOT
//
// Outputs:
//   Removes <harness>/extension; confirmation line on stdout.
//   Exit 0 — cleaned (idempotent if nothing installed); 2 — bad args.
//
// Never touches: product files; .git/info/exclude lines it did not record.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import process from 'node:process';
import { recipeHarnessRoot } from '../lib/recipe-paths.mjs';

function usage() { console.error('Usage: cleanup-extension-harness.mjs [--target <metamask-extension>]'); }
let target = process.cwd();
for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg === '--target') {
    if (i + 1 >= process.argv.length) { usage(); process.exit(2); }
    target = process.argv[++i];
  } else if (arg === '-h' || arg === '--help') {
    usage(); process.exit(0);
  } else {
    console.error(`cleanup-extension-harness: unknown arg: ${arg}`);
    usage(); process.exit(2);
  }
}

target = path.resolve(target);
const harnessRoot = harnessRootValue();
const harnessDir = path.join(target, harnessRoot, 'extension');
removeRecordedGitExcludeEntries(target, path.join(harnessDir, 'added-git-exclude'));
fs.rmSync(harnessDir, { recursive: true, force: true });
console.log(`Cleaned extension recipe harness from ${target}`);

function harnessRootValue() {
  return recipeHarnessRoot();
}

function removeRecordedGitExcludeEntries(repo, recordFile) {
  if (!fs.existsSync(recordFile)) return;
  const gitDirResult = spawnSync('git', ['-C', repo, 'rev-parse', '--git-dir'], { encoding: 'utf8' });
  if (gitDirResult.status !== 0) return;
  let gitDir = gitDirResult.stdout.trim();
  if (!path.isAbsolute(gitDir)) gitDir = path.join(repo, gitDir);
  const excludeFile = path.join(gitDir, 'info/exclude');
  if (!fs.existsSync(excludeFile)) return;
  const remove = new Set(fs.readFileSync(recordFile, 'utf8').split('\n').filter(Boolean));
  const kept = fs.readFileSync(excludeFile, 'utf8').split('\n').filter((line) => !remove.has(line));
  fs.writeFileSync(excludeFile, `${kept.join('\n').replace(/\n+$/u, '')}\n`);
}
