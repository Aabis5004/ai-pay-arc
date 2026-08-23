'use client';
import { useEffect, useState, useCallback } from 'react';
import { formatEther } from 'viem';
import { Eye, EyeOff, RefreshCw } from 'lucide-react';
import { motion } from 'framer-motion';
import { calculateBalances } from '@/lib/balance';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { NumberCounter } from './NumberCounter';

export function BalanceCard() {
  const address = useWalletAddress();
  const [balances, setBalances] = useState<{ walletUsdc: number; usdc: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hidden, setHidden] = useState(false);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!address) { setBalances(null); return; }
    setLoading(true);
    setError(null);
    try {
      const { walletUsdc, usdc } = await calculateBalances(address);
      setBalances({
        walletUsdc: parseFloat(formatEther(walletUsdc)),
        usdc: parseFloat(formatEther(usdc)),
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      console.error('[BalanceCard]', e);
    } finally {
      setLoading(false);
    }
  }, [address]);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 6000);
    return () => clearInterval(id);
  }, [refresh]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className="relative overflow-hidden rounded-2xl border border-sky-500/20 bg-gradient-to-br from-slate-900/40 via-zinc-900/40 to-slate-950/40 backdrop-blur-xl p-7"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="text-[11px] tracking-[0.18em] uppercase text-sky-400/50 font-medium">
          Arc Testnet Balances
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setHidden(v => !v)} className="p-1.5 rounded-lg hover:bg-white/5 transition" aria-label="toggle visibility">
            {hidden ? <Eye className="w-4 h-4 text-white/40" /> : <EyeOff className="w-4 h-4 text-white/40" />}
          </button>
          <button onClick={refresh} disabled={loading || !address} className="p-1.5 rounded-lg hover:bg-white/5 transition disabled:opacity-50" aria-label="refresh">
            <RefreshCw className={`w-4 h-4 text-white/40 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="space-y-4">
        {/* Wallet USDC Balance */}
        <div className="flex items-baseline justify-between">
          <div className="flex items-baseline gap-3">
            {!address || balances === null ? (
              <div className="text-4xl font-light text-white/30">—</div>
            ) : hidden ? (
              <div className="text-4xl font-light text-white/60 tracking-wider">••••</div>
            ) : (
              <div className="text-4xl font-light text-white tracking-tight">
                <NumberCounter value={balances.walletUsdc} decimals={2} />
              </div>
            )}
            <div className="text-sm text-white/40 font-light">USDC (Wallet)</div>
          </div>
        </div>

        {/* ArcPay USDC Balance */}
        <div className="flex items-baseline justify-between pt-2 border-t border-white/5">
          <div className="flex items-baseline gap-3">
            {!address || balances === null ? (
              <div className="text-2xl font-light text-white/30">—</div>
            ) : hidden ? (
              <div className="text-2xl font-light text-white/60 tracking-wider">••••</div>
            ) : (
              <div className="text-2xl font-light text-white/80 tracking-tight">
                <NumberCounter value={balances.usdc} decimals={2} />
              </div>
            )}
            <div className="text-xs text-white/40 font-light">USDC (ArcPay Vault)</div>
          </div>
        </div>
      </div>

      {error && (
        <div className="mt-4 p-3 rounded-xl bg-red-500/5 border border-red-500/20">
          <div className="text-xs text-red-400/80">Couldn&apos;t load balances.</div>
        </div>
      )}
    </motion.div>
  );
}
