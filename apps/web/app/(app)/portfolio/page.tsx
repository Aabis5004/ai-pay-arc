'use client';

import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { formatEther, type Address } from 'viem';
import { calculateBalances } from '@/lib/balance';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import { NumberCounter } from '@/components/NumberCounter';
import { AllocationDonut } from '@/components/AllocationDonut';
import { useWalletAddress } from '@/lib/useWalletAddress';

export default function PortfolioPage() {
  const address = useWalletAddress();
  const [balances, setBalances] = useState<{ walletUsdc: number; vaultUsdc: number } | null>(null);
  const [events, setEvents] = useState<HistoryEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      if (!address) return;

      setLoading(true);
      try {
        const [bals, evts] = await Promise.all([
          calculateBalances(address as Address),
          fetchHistory(address),
        ]);
        if (!cancelled) {
          setBalances({
            walletUsdc: parseFloat(formatEther(bals.walletUsdc)),
            vaultUsdc: parseFloat(formatEther(bals.usdc)),
          });
          setEvents(evts);
        }
      } catch (e) {
        console.error('[portfolio] load failed:', e);
        if (!cancelled) {
          setBalances({ walletUsdc: 0, vaultUsdc: 0 });
          setEvents([]);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    const id = setInterval(load, 8000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [address]);

  const stats = {
    deposits: events.filter((e) => e.type === 'deposit').length,
    sends: events.filter((e) => e.type === 'send').length,
    receives: events.filter((e) => e.type === 'receive').length,
    withdraws: events.filter((e) => e.type === 'withdraw').length,
    total: events.length,
  };

  const allocation = [
    { label: `Vault USDC`, value: balances?.vaultUsdc ?? 0, color: '#7c3aed' },
    { label: `Wallet USDC`, value: balances?.walletUsdc ?? 0, color: '#38bdf8' },
  ];

  const showPlaceholder = loading && events.length === 0 && balances === null;

  return (
    <>
      <PageHeader title="Portfolio" subtitle="Your holdings and activity stats on Arc Testnet." />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="bg-gradient-to-br from-violet-950/40 via-zinc-900/60 to-zinc-900/60 border border-violet-900/30 rounded-2xl p-8"
        >
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-2">
            Vault USDC Balance
          </div>
          <div className="text-5xl font-light tracking-tight">
            {balances === null ? '—' : <NumberCounter value={balances.vaultUsdc} decimals={2} />}
            <span className="text-2xl text-zinc-500 ml-2">USDC</span>
          </div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.1 }}
          className="bg-gradient-to-br from-sky-950/40 via-zinc-900/60 to-zinc-900/60 border border-sky-900/30 rounded-2xl p-8"
        >
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-2">
            Wallet USDC Balance
          </div>
          <div className="text-5xl font-light tracking-tight">
            {balances === null ? '—' : <NumberCounter value={balances.walletUsdc} decimals={2} />}
            <span className="text-2xl text-zinc-500 ml-2">USDC</span>
          </div>
        </motion.div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <motion.div
          initial={{ opacity: 0, x: -16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4 }}
          className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
        >
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">
            Allocation
          </div>
          {balances !== null && (balances.vaultUsdc > 0 || balances.walletUsdc > 0) ? (
            <AllocationDonut slices={allocation} size={200} />
          ) : (
            <div className="py-12 text-center text-sm text-zinc-500">
              No holdings yet. Deposit to populate.
            </div>
          )}
        </motion.div>

        <motion.div
          initial={{ opacity: 0, x: 16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
        >
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">
            Activity stats
          </div>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Deposits', value: stats.deposits, color: 'text-emerald-400' },
              { label: 'Sent', value: stats.sends, color: 'text-red-400' },
              { label: 'Received', value: stats.receives, color: 'text-violet-400' },
              { label: 'Withdraws', value: stats.withdraws, color: 'text-amber-400' },
            ].map((s) => (
              <div
                key={s.label}
                className="p-3 bg-zinc-950/40 border border-zinc-800 rounded-lg"
              >
                <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mb-1">
                  {s.label}
                </div>
                <div className={`text-2xl font-light ${s.color}`}>
                  {showPlaceholder ? '…' : s.value}
                </div>
              </div>
            ))}
          </div>
          <div className="mt-4 pt-4 border-t border-zinc-800 flex items-center justify-between text-xs">
            <span className="text-zinc-500">Total events</span>
            <span className="font-mono text-zinc-300">{stats.total}</span>
          </div>
        </motion.div>
      </div>
    </>
  );
}
