'use client';

import { motion } from 'framer-motion';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { arcTestnet } from '@/lib/chain';
import { BalanceCard } from '@/components/BalanceCard';
import { PageHeader } from '@/components/PageHeader';
import { useShielded } from '@/lib/useShielded';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { explorerTxUrl } from '@/lib/explorer';
import {
  Send,
  ArrowDownToLine,
  QrCode,
  Clock,
  ArrowDownLeft,
  ArrowUpRight,
  ArrowUpFromLine,
  ExternalLink,
} from 'lucide-react';

const quick = [
  { href: '/send', icon: Send, label: 'Send', hint: 'Shielded transfer' },
  { href: '/deposit', icon: ArrowDownToLine, label: 'Deposit', hint: 'Fund your vault' },
  { href: '/receive', icon: QrCode, label: 'Receive', hint: 'Share address' },
  { href: '/history', icon: Clock, label: 'Activity', hint: 'Recent events' },
];

const iconMap = {
  deposit: ArrowDownToLine,
  withdraw: ArrowUpFromLine,
  send: ArrowUpRight,
  receive: ArrowDownLeft,
};

export default function Dashboard() {
  const { address } = useShielded();

  const [recent, setRecent] = useState<HistoryEvent[]>([]);

  useEffect(() => {
    if (!address) return;
    let cancelled = false;
    fetchHistory(address).then((evts) => {
      if (!cancelled) setRecent(evts.slice(0, 4));
    });
    return () => {
      cancelled = true;
    };
  }, [address]);

  return (
    <>
      <PageHeader title="Dashboard" subtitle="Welcome back." />

      <BalanceCard />

      <motion.div
        initial="hidden"
        animate="show"
        variants={{
          hidden: {},
          show: { transition: { staggerChildren: 0.06, delayChildren: 0.15 } },
        }}
        className="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-6"
      >
        {quick.map((q) => {
          const Icon = q.icon;
          return (
            <motion.div
              key={q.href}
              variants={{
                hidden: { opacity: 0, y: 12 },
                show: { opacity: 1, y: 0 },
              }}
            >
              <Link href={q.href} className="block">
                <motion.div
                  whileHover={{ y: -3 }}
                  className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-5 hover:border-zinc-700 transition-colors cursor-pointer h-full"
                >
                  <Icon className="w-5 h-5 text-sky-400 mb-3" />
                  <div className="text-sm font-medium">{q.label}</div>
                  <div className="text-xs text-zinc-500 mt-1">{q.hint}</div>
                </motion.div>
              </Link>
            </motion.div>
          );
        })}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.3 }}
        className="mt-8 bg-zinc-900/60 border border-zinc-800 rounded-2xl backdrop-blur overflow-hidden"
      >
        <div className="px-5 py-3 border-b border-zinc-800 flex items-center justify-between">
          <span className="text-xs uppercase tracking-[0.2em] text-zinc-500">
            Recent activity
          </span>
          <Link
            href="/history"
            className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
          >
            View all →
          </Link>
        </div>
        {recent.length === 0 ? (
          <div className="p-8 text-center text-sm text-zinc-500">
            No transactions yet. Try a deposit to get started.
          </div>
        ) : (
          <ul className="divide-y divide-zinc-800/50">
            {recent.map((ev) => {
              const Icon = iconMap[ev.type];
              const url = explorerTxUrl(ev.txHash, arcTestnet.id);
              return (
                <li
                  key={ev.txHash}
                  className="flex items-center gap-4 px-5 py-3"
                >
                  <div className="w-8 h-8 rounded-lg bg-zinc-800/60 flex items-center justify-center">
                    <Icon className="w-3.5 h-3.5 text-zinc-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm capitalize">{ev.type}</div>
                    {ev.counterparty && (
                      <div className="text-[11px] font-mono text-zinc-500 truncate">
                        {ev.counterparty.slice(0, 10)}…{ev.counterparty.slice(-6)}
                      </div>
                    )}
                  </div>
                  {url ? (
                    <a
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-zinc-500 hover:text-sky-400 transition-colors"
                    >
                      <ExternalLink className="w-3.5 h-3.5" />
                    </a>
                  ) : (
                    <span className="text-[10px] font-mono text-zinc-700">
                      {ev.txHash.slice(0, 8)}…
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </motion.div>
    </>
  );
}
