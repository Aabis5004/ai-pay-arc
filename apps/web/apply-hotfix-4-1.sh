#!/usr/bin/env bash
# apply-hotfix-4-1.sh
# Diagnoses + fixes the silent wallet bridge failure.
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Patching lib/useShielded.ts with multi-strategy bridge + diagnostics…"

cat > lib/useShielded.ts << '___F_USESHIELDED___'
'use client';

import { useEffect, useState } from 'react';
import { useWallets } from '@privy-io/react-auth';
import { useAccount, useChainId, useWalletClient } from 'wagmi';
import { createShieldedWalletClient, sanvil } from 'seismic-viem';
import { custom, type Address } from 'viem';

/* eslint-disable @typescript-eslint/no-explicit-any */
type ShieldedClient = any;
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
    const baseDiag: Diag = {
      isConnected,
      address,
      chainId,
      expectedChainId: sanvil.id,
      privyWalletsCount: wallets.length,
      hasWagmiClient: !!wagmiClient,
    };
    setDiag(baseDiag);

    async function init() {
      console.log('[useShielded] state', baseDiag);

      if (!isConnected || !address) {
        console.log('[useShielded] skip: not connected');
        setWalletClient(null);
        return;
      }
      if (chainId !== sanvil.id) {
        console.log(
          '[useShielded] skip: wrong chain',
          { chainId, expected: sanvil.id },
        );
        setWalletClient(null);
        setDiag((d) => ({ ...d, error: `Wrong chain: ${chainId}` }));
        return;
      }

      // Strategy A — Privy embedded provider
      if (wallets.length > 0) {
        try {
          console.log('[useShielded] try A: Privy provider');
          const provider = await wallets[0].getEthereumProvider();
          const c = await createShieldedWalletClient({
            chain: sanvil,
            transport: custom(provider),
            account: address as Address,
          });
          if (!cancelled) {
            console.log('[useShielded] ✓ A succeeded');
            setWalletClient(c);
            setDiag((d) => ({ ...d, strategyUsed: 'privy', error: undefined }));
            return;
          }
        } catch (e) {
          console.error('[useShielded] A failed:', e);
          if (!cancelled)
            setDiag((d) => ({
              ...d,
              error: `A(privy): ${e instanceof Error ? e.message : String(e)}`,
            }));
        }
      }

      // Strategy B — wagmi wallet client transport
      if (wagmiClient) {
        try {
          console.log('[useShielded] try B: wagmi transport');
          const c = await createShieldedWalletClient({
            chain: sanvil,
            transport: custom(wagmiClient.transport),
            account: address as Address,
          });
          if (!cancelled) {
            console.log('[useShielded] ✓ B succeeded');
            setWalletClient(c);
            setDiag((d) => ({ ...d, strategyUsed: 'wagmi', error: undefined }));
            return;
          }
        } catch (e) {
          console.error('[useShielded] B failed:', e);
          if (!cancelled)
            setDiag((d) => ({
              ...d,
              error: `B(wagmi): ${e instanceof Error ? e.message : String(e)}`,
            }));
        }
      }

      // Strategy C — window.ethereum
      if (typeof window !== 'undefined') {
        const eth = (window as { ethereum?: unknown }).ethereum;
        if (eth) {
          try {
            console.log('[useShielded] try C: window.ethereum');
            const c = await createShieldedWalletClient({
              chain: sanvil,
              transport: custom(eth as Parameters<typeof custom>[0]),
              account: address as Address,
            });
            if (!cancelled) {
              console.log('[useShielded] ✓ C succeeded');
              setWalletClient(c);
              setDiag((d) => ({
                ...d,
                strategyUsed: 'window',
                error: undefined,
              }));
              return;
            }
          } catch (e) {
            console.error('[useShielded] C failed:', e);
            if (!cancelled)
              setDiag((d) => ({
                ...d,
                error: `C(window): ${e instanceof Error ? e.message : String(e)}`,
              }));
          }
        }
      }

      console.error('[useShielded] all strategies failed');
      if (!cancelled) setWalletClient(null);
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
    diagnostic: diag,
    error: diag.error,
  };
}
___F_USESHIELDED___

echo "→ Patching components/BalanceCard.tsx to expose errors instead of silent dash…"

cat > components/BalanceCard.tsx << '___F_BALCARD___'
'use client';

import { motion } from 'framer-motion';
import { useCallback, useEffect, useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { formatEther } from 'viem';
import { RefreshCw, EyeOff, AlertCircle } from 'lucide-react';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { NumberCounter } from './NumberCounter';

export function BalanceCard() {
  const { walletClient, account, ready, error: bridgeError, diagnostic } =
    useShielded();
  const [balance, setBalance] = useState<number | null>(null);
  const [readError, setReadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [hidden, setHidden] = useState(false);

  const refresh = useCallback(async () => {
    if (!walletClient || !account) return;
    setLoading(true);
    setReadError(null);
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      const bal = (await contract.read.balanceOf([account.address])) as bigint;
      setBalance(parseFloat(formatEther(bal)));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('balance read failed:', e);
      setReadError(msg.slice(0, 200));
      setBalance(null);
    } finally {
      setLoading(false);
    }
  }, [walletClient, account]);

  useEffect(() => {
    if (ready) refresh();
  }, [ready, refresh]);

  const surfaceError = bridgeError || readError;
  const stateLabel = (() => {
    if (!diagnostic.isConnected) return 'wallet not connected';
    if (diagnostic.chainId !== diagnostic.expectedChainId)
      return `wrong chain · ${diagnostic.chainId ?? '?'}`;
    if (!ready) return 'connecting…';
    return null;
  })();

  return (
    <motion.div
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
      className="relative overflow-hidden bg-gradient-to-br from-violet-950/30 via-zinc-900/60 to-zinc-900/60 border border-violet-900/30 rounded-2xl p-7 backdrop-blur"
    >
      <div
        className="absolute -top-20 -right-20 w-60 h-60 bg-violet-500/10 rounded-full blur-3xl pointer-events-none"
        aria-hidden
      />
      <div className="relative">
        <div className="flex items-center justify-between mb-3">
          <span className="text-xs uppercase tracking-[0.2em] text-zinc-500">
            Shielded balance
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setHidden((h) => !h)}
              className="text-zinc-500 hover:text-zinc-300 transition-colors"
              aria-label="Toggle hide"
            >
              <EyeOff className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={refresh}
              disabled={loading || !ready}
              className="text-zinc-500 hover:text-zinc-300 transition-colors disabled:opacity-40"
              aria-label="Refresh"
            >
              <RefreshCw
                className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`}
              />
            </button>
          </div>
        </div>
        <div className="text-5xl font-light tracking-tight">
          {hidden ? (
            <span className="text-zinc-600">••••••</span>
          ) : balance === null ? (
            <span className="text-zinc-600">—</span>
          ) : (
            <NumberCounter value={balance} decimals={4} />
          )}
          <span className="text-xl text-zinc-500 font-normal ml-2">ETH</span>
        </div>
        <div className="text-[11px] text-zinc-600 mt-4 font-mono">
          {account?.address
            ? `${account.address.slice(0, 6)}…${account.address.slice(-4)}`
            : 'wallet not connected'}
        </div>

        {stateLabel && !surfaceError && (
          <div className="mt-4 text-[11px] text-amber-400/70">
            · {stateLabel}
          </div>
        )}

        {surfaceError && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            className="mt-4 p-3 bg-red-950/30 border border-red-900/40 rounded-lg"
          >
            <div className="flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-red-400 mt-0.5 shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="text-xs font-medium text-red-300 mb-1">
                  Bridge error — paste this to Claude:
                </div>
                <div className="text-[11px] text-red-200/80 font-mono break-all">
                  {surfaceError}
                </div>
                <div className="text-[10px] text-red-300/50 mt-2">
                  strategy tried: {diagnostic.strategyUsed || 'none worked'} ·
                  chain {diagnostic.chainId} · wallets{' '}
                  {diagnostic.privyWalletsCount} · wagmi{' '}
                  {diagnostic.hasWagmiClient ? 'yes' : 'no'}
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </div>
    </motion.div>
  );
}
___F_BALCARD___

echo ""
echo "✓ Hotfix applied."
echo ""
echo "What changed:"
echo "  · lib/useShielded.ts — now tries 3 connection strategies (Privy → wagmi → window.ethereum)"
echo "    and logs every step to the browser console with [useShielded] prefix"
echo "  · components/BalanceCard.tsx — surfaces the actual error in the UI"
echo "    instead of showing a silent '—'"
echo ""
echo "Next steps:"
echo "  1. Restart dev server (Ctrl+C, then 'npm run dev')"
echo "  2. Hard-refresh browser (Ctrl+Shift+R)"
echo "  3. Open browser console (F12 → Console tab)"
echo "  4. Filter for [useShielded] — paste those logs to Claude"
echo "  5. If balance still shows error: paste the red error text from the balance card"
