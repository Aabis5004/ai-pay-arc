'use client';
// Privy-first wallet address hook. Falls back to wagmi if Privy isn't ready.
// Fixes the bug where wagmi's useAccount() returns nothing after MetaMask hiccups.

import { useEffect, useState } from 'react';
import { usePrivy, useWallets } from '@privy-io/react-auth';
import { useAccount } from 'wagmi';
import type { Address } from 'viem';

export function useWalletAddress(): Address | undefined {
  const { ready, authenticated, user } = usePrivy();
  const { wallets } = useWallets();
  const { address: wagmiAddress } = useAccount();
  const [address, setAddress] = useState<Address | undefined>(undefined);

  useEffect(() => {
    if (!ready) return;
    if (!authenticated) { setAddress(undefined); return; }

    if (wallets && wallets.length > 0) {
      const w = wallets[0];
      if (w?.address) { setAddress(w.address as Address); return; }
    }

    const linked = user?.wallet?.address;
    if (linked) { setAddress(linked as Address); return; }

    if (wagmiAddress) { setAddress(wagmiAddress as Address); return; }

    setAddress(undefined);
  }, [ready, authenticated, wallets, user, wagmiAddress]);

  return address;
}
