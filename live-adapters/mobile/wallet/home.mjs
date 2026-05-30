import { bridgeCommand, navigate, waitForRoute } from '../platform/bridge.mjs';

/**
 * Navigate to the wallet home across MetaMask Mobile navigation generations.
 *
 * Current checkouts can navigate directly to `WalletView`. Some historical
 * checkouts only register `HomeNav` at the navigator boundary and then resolve
 * to `WalletView` after React Navigation processes the parent route. The
 * historical path is still a real app navigation command; it is not state
 * injection.
 */
export async function navigateWalletHome(input) {
  try {
    const direct = await navigate(input, 'WalletView', {});
    return { navigation: direct, route: 'WalletView', proofPath: 'agentic-navigation' };
  } catch (directError) {
    const parent = await bridgeCommand(input, ['navigate', 'HomeNav', '{}']);
    const currentRoute = await waitForRoute(
      input,
      'WalletView',
      Number(input.node?.navigation_timeout_ms ?? 15000),
    );
    return {
      navigation: {
        ...parent,
        currentRoute,
        verifiedRoute: 'WalletView',
        fallbackFrom: 'WalletView',
        fallbackReason: directError instanceof Error ? directError.message : String(directError),
      },
      route: 'HomeNav',
      proofPath: 'agentic-navigation-home-nav',
    };
  }
}
