#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const runnerDir = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const farmslotRoot =
  findFarmslotRoot(runnerDir) ?? findFarmslotRoot(process.cwd());
if (!farmslotRoot) {
  throw new Error(
    'Unable to find Farmslot root for TypeScript check. Set FARMSLOT_ROOT or run near the Farmslot checkout.',
  );
}
const tsc = path.join(farmslotRoot, 'node_modules/typescript/bin/tsc');
if (!fs.existsSync(tsc))
  throw new Error(`TypeScript compiler not found at ${tsc}`);
const generatedTsconfig = path.join(runnerDir, '.tmp', 'tsconfig.check.json');
fs.mkdirSync(path.dirname(generatedTsconfig), { recursive: true });
fs.writeFileSync(
  generatedTsconfig,
  `${JSON.stringify(
    {
      extends: '../tsconfig.json',
      compilerOptions: {
        baseUrl: '..',
        types: ['node'],
        typeRoots: [
          path.relative(
            path.dirname(generatedTsconfig),
            path.join(farmslotRoot, 'node_modules/@types'),
          ),
        ],
        paths: {
          '@farmslot/protocol': [
            path.relative(
              runnerDir,
              path.join(farmslotRoot, 'packages/protocol/src/index.ts'),
            ),
          ],
          '@farmslot/recipe-harness': [
            path.relative(
              runnerDir,
              path.join(farmslotRoot, 'packages/recipe-harness/src/index.ts'),
            ),
          ],
        },
      },
    },
    null,
    2,
  )}\n`,
);
run(process.execPath, [tsc, '--noEmit', '--project', generatedTsconfig]);
for (const file of listFiles(runnerDir, (name) => name.endsWith('.mjs'))) {
  run(process.execPath, ['--check', file]);
}
validateCommittedRecipes();

function run(command, args) {
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    cwd: runnerDir,
    env: process.env,
  });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function findFarmslotRoot(start) {
  const candidates = [process.env.FARMSLOT_ROOT, start].filter(Boolean);
  for (const candidate of candidates) {
    let dir = path.resolve(candidate);
    while (dir !== path.dirname(dir)) {
      if (isFarmslotRoot(dir)) return dir;
      const sibling = path.join(dir, 'farmslot');
      if (isFarmslotRoot(sibling)) return sibling;
      dir = path.dirname(dir);
    }
  }
  return null;
}

function isFarmslotRoot(dir) {
  return (
    fs.existsSync(path.join(dir, 'packages/recipe-harness/package.json')) &&
    fs.existsSync(path.join(dir, 'packages/protocol/package.json'))
  );
}

function listFiles(root, predicate) {
  const out = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (entry.name === '.git' || entry.name === 'node_modules') continue;
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) out.push(...listFiles(full, predicate));
    else if (entry.isFile() && predicate(entry.name)) out.push(full);
  }
  return out;
}

function validateCommittedRecipes() {
  const recipeDir = path.join(runnerDir, 'recipes');
  const recipes = listFiles(recipeDir, (name) => name.endsWith('.recipe.json'));
  const manifests = {
    mobile: readJson(
      path.join(runnerDir, 'manifests/mobile.action-manifest.json'),
    ),
    extension: readJson(
      path.join(runnerDir, 'manifests/extension.action-manifest.json'),
    ),
  };
  const allActions = new Set([
    ...manifestActions(manifests.mobile),
    ...manifestActions(manifests.extension),
  ]);
  for (const recipePath of recipes) {
    const recipe = readJson(recipePath);
    const adapter = adapterForRecipe(recipePath);
    const actions = adapter ? manifestActions(manifests[adapter]) : allActions;
    const failures = validateRecipeShape(recipe, actions);
    if (failures.length > 0) {
      console.error(`Invalid recipe ${path.relative(runnerDir, recipePath)}:`);
      for (const failure of failures) console.error(`  - ${failure}`);
      process.exit(1);
    }
  }
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function manifestActions(manifest) {
  return new Set([
    ...(manifest.supported_official_actions || []),
    ...(manifest.custom_actions || []).map((entry) => entry.name),
  ]);
}

function adapterForRecipe(recipePath) {
  const name = path.basename(recipePath);
  if (name.includes('.mobile.')) return 'mobile';
  if (name.includes('.extension.')) return 'extension';
  return null;
}

function validateRecipeShape(recipe, actions) {
  const failures = [];
  const workflow = recipe?.validate?.workflow;
  if (!workflow || typeof workflow !== 'object' || Array.isArray(workflow)) {
    return ['validate.workflow must be an object'];
  }
  if (
    !workflow.nodes ||
    typeof workflow.nodes !== 'object' ||
    Array.isArray(workflow.nodes)
  ) {
    return ['validate.workflow.nodes must be an object'];
  }
  const nodes = workflow.nodes;
  if (!Object.prototype.hasOwnProperty.call(nodes, workflow.entry)) {
    failures.push(`entry node does not exist: ${workflow.entry}`);
  }
  for (const [nodeId, node] of Object.entries(nodes)) {
    validateNode(
      node,
      `validate.workflow.nodes.${nodeId}`,
      actions,
      nodes,
      failures,
    );
  }
  for (const lifecycleName of ['setup', 'teardown']) {
    validateLifecycle(
      workflow[lifecycleName],
      `validate.workflow.${lifecycleName}`,
      actions,
      failures,
    );
  }
  if (recipe.startState != null) {
    validateNode(recipe.startState, 'startState', actions, nodes, failures, {
      lifecycle: true,
    });
  }
  validateTerminalReachability(workflow, failures);
  return failures;
}

function validateLifecycle(value, label, actions, failures) {
  if (value == null) return;
  if (!Array.isArray(value)) {
    failures.push(`${label} must be an array`);
    return;
  }
  value.forEach((node, index) => {
    validateNode(node, `${label}[${index}]`, actions, {}, failures, {
      lifecycle: true,
    });
  });
}

function validateNode(node, label, actions, nodes, failures, options = {}) {
  if (!node || typeof node !== 'object' || Array.isArray(node)) {
    failures.push(`${label} must be an action node object`);
    return;
  }
  if (typeof node.action !== 'string' || node.action.length === 0) {
    failures.push(`${label}.action must be a non-empty string`);
    return;
  }
  if (!actions.has(node.action))
    failures.push(`${label}.action is not manifest-declared: ${node.action}`);
  if (options.lifecycle) {
    if (node.next != null || node.default != null || node.cases != null) {
      failures.push(
        `${label} lifecycle nodes must not declare graph transitions`,
      );
    }
    return;
  }
  if (node.action === 'end') return;
  const targets = collectTargets(node);
  if (targets.length === 0)
    failures.push(`${label} must transition via next, default, or cases`);
  for (const target of targets) {
    if (!Object.prototype.hasOwnProperty.call(nodes, target)) {
      failures.push(`${label} references missing target: ${target}`);
    }
  }
}

function collectTargets(node) {
  const targets = [];
  if (typeof node.next === 'string' && node.next.length > 0)
    targets.push(node.next);
  if (typeof node.default === 'string' && node.default.length > 0)
    targets.push(node.default);
  if (Array.isArray(node.cases)) {
    for (const entry of node.cases) {
      if (
        entry &&
        typeof entry === 'object' &&
        typeof entry.next === 'string'
      ) {
        targets.push(entry.next);
      }
    }
  } else if (node.cases && typeof node.cases === 'object') {
    for (const target of Object.values(node.cases)) {
      if (typeof target === 'string') targets.push(target);
    }
  }
  return targets;
}

function validateTerminalReachability(workflow, failures) {
  const nodes = workflow.nodes;
  const queue = Object.prototype.hasOwnProperty.call(nodes, workflow.entry)
    ? [workflow.entry]
    : [];
  const reachable = new Set();
  let terminals = 0;
  let reachableTerminals = 0;
  for (const node of Object.values(nodes)) {
    if (node?.action === 'end') terminals += 1;
  }
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId || reachable.has(nodeId)) continue;
    const node = nodes[nodeId];
    if (!node || typeof node !== 'object') continue;
    reachable.add(nodeId);
    if (node.action === 'end') reachableTerminals += 1;
    for (const target of collectTargets(node)) {
      if (
        Object.prototype.hasOwnProperty.call(nodes, target) &&
        !reachable.has(target)
      ) {
        queue.push(target);
      }
    }
  }
  if (terminals === 0)
    failures.push('workflow must include at least one end node');
  else if (queue.length === 0 && reachableTerminals === 0) {
    failures.push('workflow must have at least one reachable end node');
  }
}
