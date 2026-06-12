#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import process from 'node:process';
import { recipeHarnessRoot } from '../orchestration/lib/recipe-paths.mjs';

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
