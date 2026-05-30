import { navigate, runAdapter } from '../platform/bridge.mjs';
import { navigatePerps } from '../perps/perps.mjs';

function selectedTarget(input) {
  return String(input.node?.target ?? input.node?.destination ?? input.node?.screen ?? input.node?.route ?? 'home').toLowerCase();
}

runAdapter(async (input) => {
  const route = input.node?.route ?? input.node?.screen;
  if (route) {
    const params = input.node?.params && typeof input.node.params === 'object' ? input.node.params : {};
    const navigation = await navigate(input, String(route), params);
    return { action: input.action, route: String(route), navigation, proofPath: 'agentic-navigation' };
  }
  const target = selectedTarget(input);
  if (target === 'perps' || target === 'perps_home' || target === 'market' || target === 'market_details') {
    return navigatePerps(input);
  }
  if (target === 'home' || target === 'wallet') {
    const navigation = await navigate(input, 'WalletView', {});
    return { action: input.action, target, navigation, proofPath: 'agentic-navigation' };
  }
  throw new Error(`Unsupported mobile app navigation target: ${target}`);
});
