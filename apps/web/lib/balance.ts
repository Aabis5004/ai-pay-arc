'use client';

import { createPublicClient, http, parseAbi, type Address } from 'viem';
import { arcPay } from './contract';
import { arcTestnet } from './chain';
import { MOCK_TOKENS } from './tokens';

export async function calculateBalances(userAddress: Address): Promise<{ walletUsdc: bigint; usdc: bigint }> {
  if (!userAddress) return { walletUsdc: 0n, usdc: 0n };

  const client = createPublicClient({
    chain: arcTestnet,
    transport: http(arcTestnet.rpcUrls.default.http[0]),
  });

  const usdcTokenAddress = MOCK_TOKENS[0].address as Address; // USDC

  try {
    const [walletUsdc, usdc] = await Promise.all([
      client.getBalance({ address: userAddress }),
      client.readContract({
        address: arcPay.address as Address,
        abi: parseAbi(['function vaultBalance(address user, address token) external view returns (uint256)']),
        functionName: 'vaultBalance',
        args: [userAddress, usdcTokenAddress],
      }) as Promise<bigint>,
    ]);
    return { walletUsdc, usdc };
  } catch (e) {
    console.error('Failed to fetch balances:', e);
    return { walletUsdc: 0n, usdc: 0n };
  }
}
