import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import type { RecipeRunResult } from '@farmslot/recipe-harness';
import type { MetaMaskRecipeAdapter } from './types.ts';

export interface RecipeRecordingOptions {
  record?: boolean;
  cdpPort?: string;
}

interface ActiveRecipeRecording {
  child: ChildProcessWithoutNullStreams;
  outputPath: string;
  relativePath: string;
  pid: number;
  stdout: string;
  stderr: string;
  exited: boolean;
  exitCode: number | null;
  error?: Error;
  stderrBuffer: string;
  pendingSnapshots: Map<string, PendingRecordingSnapshot>;
}

interface PendingRecordingSnapshot {
  outputPath: string;
  timer: NodeJS.Timeout;
  resolve: (event: Record<string, unknown>) => void;
  reject: (error: Error) => void;
}

const activeRecordingsByPid = new Map<number, ActiveRecipeRecording>();

export async function startRecipeRecording(
  adapter: MetaMaskRecipeAdapter,
  projectRoot: string,
  artifactsDir: string,
  options: RecipeRecordingOptions,
): Promise<ActiveRecipeRecording | undefined> {
  if (!options.record) return undefined;
  if (adapter !== 'extension') {
    console.error(
      'WARN: --record is currently implemented for the extension adapter only; continuing without video.',
    );
    return undefined;
  }
  if (process.platform !== 'darwin') {
    console.error(
      'WARN: --record uses capture-helper and is currently supported only on macOS; continuing without video.',
    );
    return undefined;
  }

  const cdpPort = options.cdpPort ?? process.env.CDP_PORT ?? process.env.RECIPE_CDP_PORT;
  if (!captureHelperSupportsRecordSessionSnapshots(projectRoot)) {
    console.error(
      'WARN: --record requires capture-helper capability record_session_snapshot; continuing without video so screenshots use normal capture-helper snapshot.',
    );
    return undefined;
  }
  const pid = resolveExtensionBrowserPid(projectRoot, artifactsDir, cdpPort);
  if (!pid) {
    console.error(
      `WARN: --record could not resolve the extension browser PID from CDP port ${cdpPort ?? '<unset>'}; continuing without video.`,
    );
    return undefined;
  }

  const relativePath = 'videos/full-run.mp4';
  const outputPath = path.join(artifactsDir, relativePath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.rmSync(outputPath, { force: true });
  const child = spawn(captureHelperPath(), ['record', '--framed', '--pid', String(pid), '--output', outputPath], {
    cwd: projectRoot,
    env: process.env,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const recording: ActiveRecipeRecording = {
    child,
    outputPath,
    relativePath,
    pid,
    stdout: '',
    stderr: '',
    exited: false,
    exitCode: null,
    stderrBuffer: '',
    pendingSnapshots: new Map(),
  };
  child.stdout.on('data', (chunk) => {
    recording.stdout += String(chunk);
  });
  child.stderr.on('data', (chunk) => {
    recording.stderr += String(chunk);
    handleRecordingStderr(recording, String(chunk));
  });
  child.on('error', (error) => {
    recording.error = error;
    recording.stderr += error.message;
    recording.exited = true;
  });
  child.on('close', (exitCode) => {
    recording.exited = true;
    recording.exitCode = exitCode;
    activeRecordingsByPid.delete(recording.pid);
    rejectPendingSnapshots(recording, new Error(`capture-helper recording exited before snapshot completed (code=${exitCode ?? 'unknown'})`));
  });

  await sleep(750);
  if (recording.exited) {
    console.error(
      `WARN: capture-helper record exited before the recipe started (code=${recording.exitCode ?? 'unknown'}): ${recording.stderr || recording.stdout}`,
    );
    return undefined;
  }
  activeRecordingsByPid.set(pid, recording);
  console.error(`INFO: recording recipe video with capture-helper pid=${pid} output=${outputPath}`);
  return recording;
}

export async function captureActiveRecipeRecordingSnapshot(
  pid: number,
  outputPath: string,
  timeoutMs = 30_000,
): Promise<Record<string, unknown> | undefined> {
  const recording = activeRecordingsByPid.get(pid);
  if (!recording || recording.exited) return undefined;
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.rmSync(outputPath, { force: true });
  return new Promise<Record<string, unknown>>((resolve, reject) => {
    const timer = setTimeout(() => {
      recording.pendingSnapshots.delete(outputPath);
      reject(new Error(`capture-helper record session snapshot timed out after ${timeoutMs}ms: ${outputPath}`));
    }, timeoutMs);
    recording.pendingSnapshots.set(outputPath, { outputPath, timer, resolve, reject });
    recording.child.stdin.write(`snapshot ${outputPath}\n`, (error) => {
      if (!error) return;
      clearTimeout(timer);
      recording.pendingSnapshots.delete(outputPath);
      reject(error);
    });
  });
}

export async function stopRecipeRecording(
  recording: ActiveRecipeRecording | undefined,
  result?: RecipeRunResult,
): Promise<void> {
  if (!recording) return;
  if (!recording.exited) {
    recording.child.stdin.end('stop\n');
    await waitForRecordingExit(recording, 15_000);
  }
  if (!recording.exited) {
    recording.child.kill('SIGINT');
    await waitForRecordingExit(recording, 5_000);
  }
  if (!recording.exited) {
    recording.child.kill('SIGTERM');
    await waitForRecordingExit(recording, 3_000);
  }
  const validation = validateRecordingArtifact(recording);
  if (validation.ok === false) {
    try {
      fs.rmSync(recording.outputPath, { force: true });
    } catch (error) {
      console.error(
        `WARN: could not remove unusable capture-helper video ${recording.outputPath}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
    console.error(
      `WARN: capture-helper recording did not produce a usable video artifact: ${validation.reason}`,
    );
    if (result) removeRecordingArtifactFromManifest(result, recording.relativePath);
    return;
  }
  if (result) addRecordingArtifactToManifest(result, recording);
}

async function waitForRecordingExit(recording: ActiveRecipeRecording, timeoutMs: number): Promise<void> {
  if (recording.exited) return;
  await new Promise<void>((resolve) => {
    const timer = setTimeout(resolve, timeoutMs);
    recording.child.once('close', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}



function handleRecordingStderr(recording: ActiveRecipeRecording, chunk: string): void {
  recording.stderrBuffer += chunk;
  let newlineIndex = recording.stderrBuffer.indexOf('\n');
  while (newlineIndex !== -1) {
    const line = recording.stderrBuffer.slice(0, newlineIndex).trim();
    recording.stderrBuffer = recording.stderrBuffer.slice(newlineIndex + 1);
    if (line) handleRecordingEventLine(recording, line);
    newlineIndex = recording.stderrBuffer.indexOf('\n');
  }
}

function handleRecordingEventLine(recording: ActiveRecipeRecording, line: string): void {
  let event: Record<string, unknown>;
  try {
    const parsed = JSON.parse(line);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return;
    event = parsed as Record<string, unknown>;
  } catch {
    return;
  }
  const output = typeof event.output === 'string' ? event.output : undefined;
  if (!output) return;
  const pending = recording.pendingSnapshots.get(output);
  if (!pending) return;
  if (event.type === 'snapshot') {
    clearTimeout(pending.timer);
    recording.pendingSnapshots.delete(output);
    pending.resolve(event);
    return;
  }
  if (event.type === 'error') {
    clearTimeout(pending.timer);
    recording.pendingSnapshots.delete(output);
    pending.reject(new Error(String(event.message ?? `capture-helper snapshot failed: ${output}`)));
  }
}

function rejectPendingSnapshots(recording: ActiveRecipeRecording, error: Error): void {
  for (const pending of recording.pendingSnapshots.values()) {
    clearTimeout(pending.timer);
    pending.reject(error);
  }
  recording.pendingSnapshots.clear();
}

function validateRecordingArtifact(recording: ActiveRecipeRecording): { ok: true } | { ok: false; reason: string } {
  if (!fs.existsSync(recording.outputPath)) {
    return { ok: false, reason: `missing output ${recording.outputPath}` };
  }
  const size = fs.statSync(recording.outputPath).size;
  if (size === 0) {
    return { ok: false, reason: `empty output ${recording.outputPath}` };
  }
  const recorderOutput = `${recording.stdout}\n${recording.stderr}`;
  if (!recorderOutput.includes('record_complete')) {
    return {
      ok: false,
      reason: `capture-helper did not report record_complete for ${recording.outputPath}: ${recorderOutput.trim() || 'no recorder output'}`,
    };
  }

  const ffprobe = spawnSync(
    'ffprobe',
    ['-hide_banner', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', recording.outputPath],
    { encoding: 'utf8' },
  );
  if (ffprobe.error && (ffprobe.error as NodeJS.ErrnoException).code === 'ENOENT') {
    return { ok: true };
  }
  if (ffprobe.error) {
    return { ok: false, reason: `ffprobe failed for ${recording.outputPath}: ${ffprobe.error.message}` };
  }
  if (ffprobe.status !== 0) {
    return {
      ok: false,
      reason: `invalid MP4 ${recording.outputPath}: ${ffprobe.stderr.trim() || ffprobe.stdout.trim() || `ffprobe exited ${ffprobe.status}`}`,
    };
  }
  const durationSeconds = Number(ffprobe.stdout.trim());
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return { ok: false, reason: `MP4 has no positive duration: ${recording.outputPath}` };
  }
  return { ok: true };
}

function addRecordingArtifactToManifest(result: RecipeRunResult, recording: ActiveRecipeRecording): void {
  const manifestPath = result.artifactManifestPath;
  if (!manifestPath || !fs.existsSync(manifestPath)) {
    console.error(`WARN: cannot add video artifact to missing artifact manifest: ${manifestPath ?? '<unset>'}`);
    return;
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as {
    artifacts?: Array<Record<string, unknown>>;
  };
  if (!Array.isArray(manifest.artifacts)) manifest.artifacts = [];
  manifest.artifacts = manifest.artifacts.filter((artifact) => artifact.path !== recording.relativePath);
  manifest.artifacts.push({
    path: recording.relativePath,
    type: 'video',
    label: 'Full recipe replay video',
    category: 'evidence',
    mimeType: 'video/mp4',
    record: 'full_run',
    metadata: {
      provider: 'capture-helper',
      mode: 'full_run',
      pid: recording.pid,
    },
  });
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

function removeRecordingArtifactFromManifest(result: RecipeRunResult, relativePath: string): void {
  const manifestPath = result.artifactManifestPath;
  if (!manifestPath || !fs.existsSync(manifestPath)) return;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as {
    artifacts?: Array<Record<string, unknown>>;
  };
  if (!Array.isArray(manifest.artifacts)) return;
  const nextArtifacts = manifest.artifacts.filter((artifact) => artifact.path !== relativePath);
  if (nextArtifacts.length === manifest.artifacts.length) return;
  manifest.artifacts = nextArtifacts;
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}


function captureHelperSupportsRecordSessionSnapshots(projectRoot: string): boolean {
  const result = spawnSync(captureHelperPath(), ['version', '--json'], {
    cwd: projectRoot,
    encoding: 'utf8',
  });
  if (result.status !== 0) return false;
  try {
    const parsed = JSON.parse(result.stdout) as { capabilities?: unknown };
    return Array.isArray(parsed.capabilities) && parsed.capabilities.includes('record_session_snapshot');
  } catch {
    return false;
  }
}

function resolveExtensionBrowserPid(projectRoot: string, artifactsDir: string, cdpPort: string | undefined): number | null {
  const explicit = parsePositivePid(process.env.METAMASK_RECIPE_EXTENSION_BROWSER_PID);
  if (explicit) return explicit;
  if (cdpPort) {
    const lsof = spawnSync('lsof', ['-nP', `-iTCP:${cdpPort}`, '-sTCP:LISTEN', '-t'], {
      cwd: projectRoot,
      encoding: 'utf8',
    });
    if (lsof.status === 0) {
      const pid = parsePositivePid(String(lsof.stdout).split(/\s+/u).find(Boolean));
      if (pid) return pid;
    }
  }
  for (const file of [
    path.join(artifactsDir, 'extension-runtime/runtime.json'),
    path.join(projectRoot, 'temp/recipe/runtime/runtime.json'),
  ]) {
    const pid = parsePositivePid(readJsonFile(file)?.pid);
    if (pid) return pid;
  }
  for (const file of [
    path.join(projectRoot, 'temp/recipe/runtime/chromium.pid'),
    path.join(projectRoot, 'temp/recipe/runtime/browser.pid'),
  ]) {
    const pid = parsePositivePid(readTextFile(file));
    if (pid) return pid;
  }
  return null;
}

function captureHelperPath(): string {
  return process.env.CAPTURE_HELPER_PATH || 'capture-helper';
}

function parsePositivePid(value: unknown): number | null {
  const pid = Number(String(value ?? '').trim());
  return Number.isInteger(pid) && pid > 0 ? pid : null;
}

function readJsonFile(file: string): Record<string, unknown> | null {
  if (!fs.existsSync(file)) return null;
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch (error) {
    console.error(
      `WARN: could not parse JSON while resolving extension browser PID from ${file}: ${error instanceof Error ? error.message : String(error)}`,
    );
    return null;
  }
}

function readTextFile(file: string): string {
  if (!fs.existsSync(file)) return '';
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (error) {
    console.error(
      `WARN: could not read PID file while resolving extension browser PID from ${file}: ${error instanceof Error ? error.message : String(error)}`,
    );
    return '';
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
