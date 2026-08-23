'use client';

import { useEffect, useState } from 'react';
import { useWallets, type ConnectedWallet } from '@privy-io/react-auth';
import { useAccount, useWalletClient } from 'wagmi';
import { createWalletClient, custom, type Address, type WalletClient } from 'viem';
import { arcTestnet } from './chain';

/* eslint-disable @typescript-eslint/no-explicit-any */
type EthereumProvider = { request: (args: { method: string; params?: any[] }) => Promise<any> };
/* eslint-enable @typescript-eslint/no-explicit-any */

type Diag = {
  isConnected: boolean;
  address?: string;
  expectedChainId: number;
  privyWalletsCount: number;
  hasWagmiClient: boolean;
  strategyUsed?: string;
  error?: string;
};

export function useShielded() {
  const { address, isConnected } = useAccount();
  const { wallets } = useWallets();
  const { data: wagmiClient } = useWalletClient();

  const [walletClient, setWalletClient] = useState<WalletClient | null>(null);
  const [diag, setDiag] = useState<Diag>({
    isConnected: false,
    expectedChainId: arcTestnet.id,
    privyWalletsCount: 0,
    hasWagmiClient: false,
  });

  useEffect(() => {
    let cancelled = false;
    const base: Diag = {
      isConnected,
      address,
      expectedChainId: arcTestnet.id,
      privyWalletsCount: wallets.length,
      hasWagmiClient: !!wagmiClient,
    };
    setDiag(base);

    async function init() {
      if (!isConnected || !address) {
        setWalletClient(null);
        return;
      }

      let walletProvider: EthereumProvider | null = null;
      let providerSource = '';

      if (wallets.length > 0) {
        try {
          const w = wallets[0] as ConnectedWallet;
          walletProvider = await w.getEthereumProvider();
          providerSource = 'privy';
        } catch (e) {
          console.error('[useShielded] privy provider failed:', e);
        }
      }

      if (!walletProvider && typeof window !== 'undefined') {
        const eth = (window as { ethereum?: EthereumProvider }).ethereum;
        if (eth) {
          walletProvider = eth;
          providerSource = 'window';
        }
      }

      if (!walletProvider) {
        if (!cancelled)
          setDiag((d) => ({ ...d, error: 'No wallet provider available' }));
        return;
      }

      try {
        const c = createWalletClient({
          chain: arcTestnet,
          transport: custom(walletProvider),
          account: address as Address,
        });
        if (!cancelled) {
          setWalletClient(c);
          setDiag((d) => ({
            ...d,
            strategyUsed: `custom:${providerSource}`,
            error: undefined,
          }));
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error('[useShielded] client creation failed:', e);
        if (!cancelled) {
          setWalletClient(null);
          setDiag((d) => ({ ...d, error: msg, strategyUsed: providerSource }));
        }
      }
    }

    init();
    return () => {
      cancelled = true;
    };
  }, [address, isConnected, wallets, wagmiClient]);

  return {
    walletClient,
    account: address ? ({ address: address as Address } as const) : null,
    address: address as Address | undefined,
    ready: !!walletClient,
    diagnostic: diag,
    error: diag.error,
  };
}
