import { runAdapter, withExtensionPage } from '../platform/cdp.mjs';

function target(input) {
  return String(input.node?.target ?? input.node?.destination ?? input.node?.screen ?? 'home').toLowerCase();
}

runAdapter((input) => withExtensionPage(input, async (page) => {
  const selected = target(input);
  if (selected === 'home' || selected === 'wallet') {
    const navigation = await page.navigateHash('#/');
    return { action: input.action, target: selected, navigation, proofPath: 'ui-navigation' };
  }
  if (selected === 'perps' || selected === 'perps_home') {
    const navigation = await page.navigateHash('#/?tab=perps');
    await page.waitForExpression('document.body && document.body.innerText.includes("Perps")', { timeoutMs: 15000 });
    return { action: input.action, target: selected, navigation, proofPath: 'ui-navigation' };
  }
  throw new Error(`Unsupported extension wallet navigation target: ${selected}`);
}));
