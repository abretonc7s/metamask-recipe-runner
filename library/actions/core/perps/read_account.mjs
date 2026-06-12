import { getCoreController, runAdapter } from './_controller.mjs';

function redactAccount(account) {
  return {
    totalBalance: account?.totalBalance ?? null,
    spendableBalance: account?.spendableBalance ?? null,
    withdrawableBalance: account?.withdrawableBalance ?? null,
    marginUsed: account?.marginUsed ?? null,
    unrealizedPnl: account?.unrealizedPnl ?? null,
    returnOnEquity: account?.returnOnEquity ?? null,
  };
}

export async function readAccount(input) {
  const { controller, accountAddress, network } = await getCoreController(input);
  const account = await controller.getAccountState({
    standalone: true,
    userAddress: accountAddress,
  });
  return {
    action: input.action,
    source: 'perps-controller-standalone',
    network,
    account: accountAddress,
    accountState: redactAccount(account),
    proofPath: 'perps-controller-getAccountState',
  };
}

runAdapter(readAccount);
