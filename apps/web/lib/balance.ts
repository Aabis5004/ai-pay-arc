'use client';

import { createPublicClient, http, type Address, zeroAddress } from 'viem';
import { arcPay } from './contract';
import { arcTestnet } from './chain';

export async function calculateBalances(userAddress: Address): Promise<{ walletUsdc: bigint; usdc: bigint }> {
  if (!userAddress) return { walletUsdc: 0n, usdc: 0n };

  const client = createPublicClient({
    chain: arcTestnet,
    transport: http(arcTestnet.rpcUrls.default.http[0]),
  });

  try {
    const [walletUsdc, usdc] = await Promise.all([
      client.getBalance({ address: userAddress }),
      client.readContract({
        address: arcPay.address as Address,
        abi: arcPay.abi,
        functionName: 'balanceOf',
        args: [userAddress, zeroAddress],
      }) as Promise<bigint>,
    ]);
    return { walletUsdc, usdc };
  } catch (e) {
    console.error('Failed to fetch balances:', e);
    return { walletUsdc: 0n, usdc: 0n };
  }
}
