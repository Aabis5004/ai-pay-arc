#!/usr/bin/env bash
# apply-hotfix-5-1.sh
# Fixes "seismic_getTeePublicKey does not exist" by splitting the RPC transport:
#   · seismic_* methods → direct HTTP to sanvil (MetaMask filters these)
#   · signing methods   → through MetaMask (so the user signs)
#   · everything else   → HTTP (faster, no popups)
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Patching lib/useShielded.ts with split transport…"

cat > lib/useShielded.ts << '___F_USESHIELDED___'
'use client';

import { useEffect, useState } from 'react';
import { useWallets, type ConnectedWallet } from '@privy-io/react-auth';
import { useAccount, useChainId, useWalletClient } from 'wagmi';
import { createShieldedWalletClient, sanvil } from 'seismic-viem';
import { custom, type Address } from 'viem';

/* eslint-disable @typescript-eslint/no-explicit-any */
type ShieldedClient = any;
type EthereumProvider = { request: (args: { method: string; params?: any[] }) => Promise<any> };
/* eslint-enable @typescript-eslint/no-explicit-any */

type Diag = {
  isConnected: boolean;
  address?: string;
  chainId?: number;
  expectedChainId: number;
  privyWalletsCount: number;
  hasWagmiClient: boolean;
  strategyUsed?: string;
  error?: string;
};

const RPC_URL =
  process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';

// Methods that need to go through the wallet (signing, account-related)
const WALLET_METHODS = new Set([
  'eth_sign',
  'eth_signTransaction',
  'eth_sendTransaction',
  'eth_sendRawTransaction',
  'eth_signTypedData_v4',
  'eth_signTypedData_v3',
  'personal_sign',
  'eth_requestAccounts',
  'eth_accounts',
  'wallet_switchEthereumChain',
  'wallet_addEthereumChain',
  'wallet_watchAsset',
  'wallet_requestPermissions',
]);

/**
 * Build a transport that routes:
 *   · seismic_*    → direct HTTP (MetaMask filters these methods)
 *   · WALLET_METHODS → through the user's wallet (signing)
 *   · everything else → HTTP first, wallet fallback
 */
function makeSplitProvider(wallet: EthereumProvider): EthereumProvider {
  return {
    async request({ method, params }) {
      // 1. Anything signing-related → wallet (so MetaMask popup appears)
      if (WALLET_METHODS.has(method)) {
        return wallet.request({ method, params });
      }

      // 2. Try HTTP direct (works for seismic_* + standard reads)
      try {
        const res = await fetch(RPC_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            jsonrpc: '2.0',
            method,
            params: params || [],
            id: Math.floor(Math.random() * 1e9),
          }),
        });
        const json = await res.json();
        if (json.error) {
          // For seismic_*, don't fall back to wallet — MetaMask will choke on it
          if (method.startsWith('seismic_')) {
            throw new Error(
              `${json.error.message || 'rpc error'} (method=${method})`,
            );
          }
          // For other methods, fall through to wallet
          throw json.error;
        }
        return json.result;
      } catch (e) {
        if (method.startsWith('seismic_')) throw e;
        // 3. Fallback to wallet
        return wallet.request({ method, params });
      }
    },
  };
}

export function useShielded() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { wallets } = useWallets();
  const { data: wagmiClient } = useWalletClient();

  const [walletClient, setWalletClient] = useState<ShieldedClient | null>(null);
  const [diag, setDiag] = useState<Diag>({
    isConnected: false,
    expectedChainId: sanvil.id,
    privyWalletsCount: 0,
    hasWagmiClient: false,
  });

  useEffect(() => {
    let cancelled = false;
    const base: Diag = {
      isConnected,
      address,
      chainId,
      expectedChainId: sanvil.id,
      privyWalletsCount: wallets.length,
      hasWagmiClient: !!wagmiClient,
    };
    setDiag(base);

    async function init() {
      if (!isConnected || !address) {
        setWalletClient(null);
        return;
      }
      if (chainId !== sanvil.id) {
        setWalletClient(null);
        setDiag((d) => ({ ...d, error: `Wrong chain: ${chainId}` }));
        return;
      }

      // Get a wallet provider — try Privy first, then window.ethereum
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

      // Build the split-routing provider
      const splitProvider = makeSplitProvider(walletProvider);

      try {
        console.log(`[useShielded] creating shielded client via ${providerSource} + split transport`);
        const c = await createShieldedWalletClient({
          chain: sanvil,
          transport: custom(splitProvider),
          account: address as Address,
        });
        if (!cancelled) {
          console.log('[useShielded] ✓ shielded client ready');
          setWalletClient(c);
          setDiag((d) => ({
            ...d,
            strategyUsed: `split:${providerSource}`,
            error: undefined,
          }));
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error('[useShielded] shielded client creation failed:', e);
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
  }, [address, isConnected, chainId, wallets, wagmiClient]);

  return {
    walletClient,
    account: address ? ({ address: address as Address } as const) : null,
    address: address as Address | undefined,
    ready: !!walletClient,
    chainId,
    diagnostic: diag,
    error: diag.error,
  };
}
___F_USESHIELDED___

echo ""
echo "✓ Hotfix applied."
echo ""
echo "What changed:"
echo "  · lib/useShielded.ts now uses a SPLIT TRANSPORT:"
echo "    - seismic_* methods bypass MetaMask via direct HTTP to sanvil"
echo "    - signing methods (eth_sendTransaction, etc.) still go through MetaMask"
echo "    - reads happen via HTTP (faster, no popups)"
echo ""
echo "Next:"
echo "  1. Ctrl+C the dev server, then 'npm run dev'"
echo "  2. Hard-refresh: Ctrl+Shift+R"
echo "  3. Check balance card — should show 0.0000 ETH (not '—')"
echo "  4. Try a deposit. MetaMask should pop up for signing."
echo ""
echo "If the balance card now shows a different error:"
echo "  Run this curl first to confirm sanvil supports the TEE method:"
echo "    curl -s -X POST -H 'Content-Type: application/json' \\"
echo "      --data '{\"jsonrpc\":\"2.0\",\"method\":\"seismic_getTeePublicKey\",\"params\":[],\"id\":1}' \\"
echo "      http://127.0.0.1:8545"
echo "  If that returns 'method not found', sanvil doesn't expose the TEE method"
echo "  and we need to switch to Seismic Testnet (chain 5124) — paste the curl output."
