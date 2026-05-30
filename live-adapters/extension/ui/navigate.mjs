import { runAdapter, withExtensionPage } from '../platform/cdp.mjs';

function selectedTarget(input) {
  return String(input.node?.target ?? input.node?.destination ?? input.node?.screen ?? input.node?.route ?? 'home').toLowerCase();
}

runAdapter((input) => withExtensionPage(input, async (page) => {
  const hash = input.node?.hash ?? input.node?.route ?? input.node?.path;
  if (hash) {
    const navigation = await page.navigateHash(String(hash));
    return { action: input.action, hash: String(hash), navigation, proofPath: 'ui-navigation' };
  }
  const target = selectedTarget(input);
  if (target === 'home' || target === 'wallet') {
    const navigation = await page.navigateHash('#/');
    return { action: input.action, target, navigation, proofPath: 'ui-navigation' };
  }
  if (target === 'perps' || target === 'perps_home') {
    const navigation = await page.navigateHash('#/?tab=perps');
    await page.waitForExpression('document.body && document.body.innerText.includes("Perps")', { timeoutMs: 15000 });
    return { action: input.action, target, navigation, proofPath: 'ui-navigation' };
  }
  throw new Error(`Unsupported extension app navigation target: ${target}`);
}));
