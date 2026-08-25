'use client';

import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { ArrowDownToLine, ArrowUpRight, ArrowDownLeft } from 'lucide-react';
import { ArcCard, cardNumberFromAddress } from '@/components/ArcCard';
import { CardActionModal, type CardAction } from '@/components/CardActionModal';
import { CardRegisterBanner } from '@/components/CardRegisterBanner';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { arcTestnet } from '@/lib/chain';

function Counter({ value, decimals = 0 }: { value: number; decimals?: number }) {
  const [d, setD] = useState(0);
  useEffect(() => {
    let raf = 0; const start = performance.now(); const from = d;
    const tick = (t: number) => {
      const p = Math.min(1, (t - start) / 900);
      const eased = 1 - Math.pow(1 - p, 3);
      setD(from + (value - from) * eased);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);
  return <>{d.toFixed(decimals)}</>;
}

export default function CardPage() {
  const address = useWalletAddress();
  const [events, setEvents] = useState<HistoryEvent[]>([]);
  const [balance, setBalance] = useState<number | null>(null);
  const [action, setAction] = useState<CardAction>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const cardNumber = cardNumberFromAddress(address);
  const tokenSymbol = 'USDC';

  const loadEvents = async () => {
    if (!address) return;
    try { setEvents(await fetchHistory(address)); } catch { /* ignore */ }
  };

  useEffect(() => {
    loadEvents();
    const id = setInterval(loadEvents, 8000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address]);

  const sent = events.filter((e) => e.type === 'send').length;
  const received = events.filter((e) => e.type === 'receive').length;

  const afterSuccess = () => {
    setRefreshKey((k) => k + 1); // forces card balance refresh
    loadEvents();
  };

  return (
    <div className="relative">
      <div className="text-center pt-8 pb-4">
        <h1 className="text-2xl md:text-3xl font-light tracking-tight mb-2 text-white">
          ArcPay Card
        </h1>
        <p className="text-zinc-400 text-sm">
          Your public on-chain debit card for USDC payments.
        </p>
      </div>

      <CardRegisterBanner cardNumber={cardNumber} />

      <div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums">
            {balance === null ? '—' : <Counter value={balance} decimals={2} />}
          </div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Balance ({tokenSymbol})</div>
        </div>
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums"><Counter value={sent} /></div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Sent</div>
        </div>
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums"><Counter value={received} /></div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Received</div>
        </div>
      </div>

      <motion.div
        initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
        className="flex justify-center mb-14"
      >
        <ArcCard onBalance={setBalance} onAction={setAction} refreshKey={refreshKey} />
      </motion.div>

      <div className="max-w-3xl mx-auto bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur">
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">Recent activity</div>
        {events.length === 0 ? (
          <div className="text-sm text-zinc-500 py-6 text-center">No activity yet. Deposit to your card to get started.</div>
        ) : (
          <div className="space-y-2">
            {events.filter(e => ['deposit', 'withdraw', 'send', 'receive'].includes(e.type)).slice(0, 6).map((e, i) => (
              <motion.div key={`${e.txHash}-${i}`} initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.05 }}
                className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-zinc-800/40 transition-colors">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-zinc-800/60 flex items-center justify-center">
                    {e.type === 'deposit' && <ArrowDownToLine className="w-3.5 h-3.5 text-emerald-400" />}
                    {e.type === 'send' && <ArrowUpRight className="w-3.5 h-3.5 text-red-400" />}
                    {e.type === 'receive' && <ArrowDownLeft className="w-3.5 h-3.5 text-violet-400" />}
                    {e.type === 'withdraw' && <ArrowUpRight className="w-3.5 h-3.5 text-amber-400" />}
                  </div>
                  <div>
                    <div className="text-sm text-zinc-200 capitalize">{e.type}</div>
                    <div className="text-[10px] font-mono text-zinc-600">{e.txHash ? `${e.txHash.slice(0, 10)}…` : ''}</div>
                  </div>
                </div>
                <div className="text-[10px] uppercase tracking-wider text-emerald-400/70">confirmed</div>
              </motion.div>
            ))}
          </div>
        )}
      </div>

      <CardActionModal
        action={action}
        cardNumber={cardNumber}
        onClose={() => setAction(null)}
        onSuccess={afterSuccess}
      />
    </div>
  );
}
