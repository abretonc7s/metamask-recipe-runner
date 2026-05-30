import { navigate, runAdapter } from '../platform/bridge.mjs';
import { navigatePerps } from '../perps/perps.mjs';

function target(input) {
  return String(input.node?.target ?? input.node?.destination ?? input.node?.screen ?? 'home').toLowerCase();
}

runAdapter(async (input) => {
  const selected = target(input);
  if (selected === 'perps' || selected === 'perps_home') {
    return navigatePerps({ ...input, node: { ...input.node, target: 'home' } });
  }
  if (selected === 'home' || selected === 'wallet') {
    const navigation = await navigate(input, 'WalletView', {});
    return { action: input.action, target: selected, navigation, proofPath: 'agentic-navigation' };
  }
  throw new Error(`Unsupported mobile wallet navigation target: ${selected}`);
});
