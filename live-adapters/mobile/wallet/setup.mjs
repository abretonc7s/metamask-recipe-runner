import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { runAdapter } from '../platform/bridge.mjs';

async function fixtureSummary(projectRoot) {
  const candidates = [
    path.join(projectRoot, '.agent/wallet-fixture.json'),
    path.join(projectRoot, 'temp/runtime/wallet-fixture.json'),
    path.join(projectRoot, 'scripts/perps/agentic/wallet-fixture.json'),
  ];
  for (const candidate of candidates) {
    try {
      const fixture = JSON.parse(await readFile(candidate, 'utf8'));
      return {
        path: path.relative(projectRoot, candidate),
        accounts: Array.isArray(fixture.accounts) ? fixture.accounts.length : null,
        hasPassword: Boolean(fixture.password),
      };
    } catch (error) {
      if (error?.code === 'ENOENT') continue;
      throw error;
    }
  }
  throw new Error('No wallet fixture found for Mobile setup.');
}

runAdapter(async (input) => ({
  action: input.action,
  setup: 'preseeded-mobile-fixture-verified',
  fixture: await fixtureSummary(input.context.projectRoot),
  proofPath: 'mobile-fixture-profile',
}));
