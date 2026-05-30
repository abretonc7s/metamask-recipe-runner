import { navigate, runAdapter } from '../platform/bridge.mjs';
import { navigatePerps } from '../perps/perps.mjs';
import { navigateWalletHome } from './home.mjs';

function target(input) {
  return String(input.node?.target ?? input.node?.destination ?? input.node?.screen ?? 'home').toLowerCase();
}

runAdapter(async (input) => {
  const selected = target(input);
  if (selected === 'perps' || selected === 'perps_home') {
    return navigatePerps({ ...input, node: { ...input.node, target: 'home' } });
  }
  if (selected === 'home' || selected === 'wallet') {
    const result = await navigateWalletHome(input);
    return { action: input.action, target: selected, ...result };
  }
  throw new Error(`Unsupported mobile wallet navigation target: ${selected}`);
});
