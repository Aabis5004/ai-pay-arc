#!/usr/bin/env bash
# fix-portfolio-stats.sh
# Fixes the "…" stuck in the activity stat boxes.
# Root cause: load() returns early (before try/finally) when deps aren't ready,
# so setLoading(false) never runs and boxes stay on the loading placeholder.
# Also removes unused getShieldedContract import that can throw.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

echo "→ Backing up portfolio page…"
cp "app/(app)/portfolio/page.tsx" "app/(app)/portfolio/page.tsx.bak.$(date +%s)"

echo "→ Rewriting portfolio page with fixed loading + cleaned imports…"

cat > "app/(app)/portfolio/page.tsx" <<'TSX'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { formatEther, type Address } from 'viem';
import { useShielded } from '@/lib/useShielded';
import { calculateBalance } from '@/lib/balance';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import { NumberCounter } from '@/components/NumberCounter';
import { AllocationDonut } from '@/components/AllocationDonut';
import { NATIVE_SYMBOL } from '@/lib/chain';

export default function PortfolioPage() {
  const { address, ready } = useShielded();
  const [balance, setBalance] = useState<number | null>(null);
  const [events, setEvents] = useState<HistoryEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      // Wait until we actually have an address; do NOT flip loading off here.
      if (!ready || !address) return;

      setLoading(true);
      try {
        const [bal, evts] = await Promise.all([
          calculateBalance(address as Address),
          fetchHistory(address),
        ]);
        if (!cancelled) {
          setBalance(parseFloat(formatEther(bal)));
          setEvents(evts);
        }
      } catch (e) {
        console.error('[portfolio] load failed:', e);
        if (!cancelled) {
          setBalance(0);
          setEvents([]);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    // Refresh every 8s so stats stay live as you transact
    const id = setInterval(load, 8000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [ready, address]);

  const stats = {
    deposits: events.filter((e) => e.type === 'deposit').length,
    sends: events.filter((e) => e.type === 'send').length,
    receives: events.filter((e) => e.type === 'receive').length,
    withdraws: events.filter((e) => e.type === 'withdraw').length,
    total: events.length,
  };

  const allocation = [
    { label: `Shielded ${NATIVE_SYMBOL}`, value: balance ?? 0, color: '#7c3aed' },
  ];

  // Only show the loading placeholder while we have NO data yet.
  // Once events have loaded once, always show real numbers.
  const showPlaceholder = loading && events.length === 0 && balance === null;

  return (
    <>
      <PageHeader title="Portfolio" subtitle="Your shielded holdings and activity stats." />

      <motion.div
        initial={{ opacity: 0, rotate: -1, scale: 0.98 }}
        animate={{ opacity: 1, rotate: 0, scale: 1 }}
        transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
        className="bg-gradient-to-br from-violet-950/40 via-zinc-900/60 to-zinc-900/60 border border-violet-900/30 rounded-2xl p-8 mb-6"
      >
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-2">
          Total shielded value
        </div>
        <div className="text-5xl font-light tracking-tight">
          {balance === null ? '—' : <NumberCounter value={balance} decimals={4} />}
          <span className="text-2xl text-zinc-500 ml-2">{NATIVE_SYMBOL}</span>
        </div>
      </motion.div>

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
          {balance !== null && balance > 0 ? (
            <AllocationDonut slices={allocation} size={200} />
          ) : (
            <div className="py-12 text-center text-sm text-zinc-500">
              No holdings yet. Deposit ETH to populate.
            </div>
          )}
          <div className="mt-4 pt-4 border-t border-zinc-800 text-[11px] text-zinc-600 leading-relaxed">
            Only one asset class (shielded native currency) exists in this build. Multi-token
            support requires deploying additional SRC20 contracts on Seismic.
          </div>
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
TSX

echo "  ✓ portfolio page rewritten"

echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════"
echo "  DONE. Restart dev server:"
echo "    Ctrl+C in npm run dev, then 'npm run dev'"
echo "  Hard-refresh: Ctrl+Shift+R"
echo ""
echo "  The four stat boxes will now show real counts"
echo "  (Deposits / Sent / Received / Withdraws) and refresh"
echo "  every 8 seconds as you transact."
echo "═══════════════════════════════════════════════"
