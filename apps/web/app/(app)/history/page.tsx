'use client';

import { motion } from 'framer-motion';
import { useCallback, useEffect, useState } from 'react';
import { useShielded } from '@/lib/useShielded';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { explorerTxUrl } from '@/lib/explorer';
import { PageHeader } from '@/components/PageHeader';
import { arcTestnet } from '@/lib/chain';
import {
  EyeOff,
  ExternalLink,
  RefreshCw,
  Copy,
  CheckCircle2,
} from 'lucide-react';
import { formatEther } from 'viem';

function timeAgo(ts?: number) {
  if (!ts) return '';
  const diff = (Date.now() - ts) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

function truncate(addr: string | undefined, chars = 4) {
  if (!addr) return '';
  if (addr === 'ArcPay Contract') return addr;
  return `${addr.slice(0, chars + 2)}...${addr.slice(-chars)}`;
}

export default function HistoryPage() {
  const { address } = useShielded();
  const [events, setEvents] = useState<HistoryEvent[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!address) return;
    setLoading(true);
    try {
      const evts = await fetchHistory(address);
      setEvents(evts);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'fetch failed');
    } finally {
      setLoading(false);
    }
  }, [address]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    const id = setInterval(load, 15000);
    return () => clearInterval(id);
  }, [load]);

  const copy = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  return (
    <>
      <PageHeader
        title="Transactions"
        subtitle="On-chain activity involving your address."
        action={
          <button
            onClick={load}
            disabled={loading}
            className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-300 transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        }
      />

      <div className="bg-zinc-900/40 border border-zinc-800/80 rounded-[24px] backdrop-blur overflow-hidden shadow-2xl">
        {/* Table Header */}
        <div className="hidden md:grid grid-cols-5 gap-4 px-6 py-4 border-b border-zinc-800/80 bg-zinc-900/60 text-xs font-semibold text-zinc-400 uppercase tracking-wider">
          <div>From</div>
          <div>To</div>
          <div>Transaction</div>
          <div>Status</div>
          <div className="text-right">Time</div>
        </div>

        {loading && !events ? (
          <div className="p-6 space-y-3">
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="h-16 shimmer rounded-xl" />
            ))}
          </div>
        ) : error ? (
          <div className="p-8 text-sm text-red-400">Error: {error}</div>
        ) : !events || events.length === 0 ? (
          <div className="p-16 text-center">
            <EyeOff className="w-10 h-10 text-zinc-700 mx-auto mb-4" />
            <div className="text-base text-zinc-400 font-medium">No activity yet</div>
            <div className="text-sm text-zinc-600 mt-2">
              Deposits and transfers will appear here.
            </div>
          </div>
        ) : (
          <motion.div
            initial="hidden"
            animate="show"
            variants={{
              hidden: {},
              show: { transition: { staggerChildren: 0.04 } },
            }}
            className="divide-y divide-zinc-800/50"
          >
            {events.map((ev) => {
              const url = explorerTxUrl(ev.txHash, arcTestnet.id);
              let fromAddress = '';
              let toAddress = '';
              let actionType = '';
              
              if (ev.type === 'deposit') {
                fromAddress = address || '';
                toAddress = 'ArcPay Contract';
                actionType = 'Deposit';
              } else if (ev.type === 'withdraw') {
                fromAddress = 'ArcPay Contract';
                toAddress = address || '';
                actionType = 'Withdraw';
              } else if (ev.type === 'send') {
                fromAddress = address || '';
                toAddress = ev.counterparty || '';
                actionType = 'Send';
              } else if (ev.type === 'receive') {
                fromAddress = ev.counterparty || '';
                toAddress = address || '';
                actionType = 'Receive';
              }

              const formattedAmount = ev.amount ? parseFloat(formatEther(ev.amount)).toString() : '0';

              return (
                <motion.div
                  key={ev.txHash}
                  variants={{
                    hidden: { opacity: 0, y: 10 },
                    show: { opacity: 1, y: 0 },
                  }}
                  className="grid grid-cols-1 md:grid-cols-5 gap-4 px-6 py-5 hover:bg-zinc-800/20 transition-colors items-center group"
                >
                  {/* From */}
                  <div className="flex flex-col gap-1.5">
                    <div className="flex items-center gap-2">
                      <div className="w-5 h-5 rounded-full bg-sky-500/20 flex items-center justify-center border border-sky-500/30">
                        <span className="text-[9px] font-bold text-sky-400">$</span>
                      </div>
                      <span className="font-semibold text-zinc-200 text-sm">{formattedAmount} USDC</span>
                    </div>
                    <div className="flex items-center gap-1.5 text-xs text-zinc-500 font-mono">
                      <span>Sender: {truncate(fromAddress)}</span>
                      {fromAddress !== 'ArcPay Contract' && (
                        <button onClick={() => copy(fromAddress)} className="hover:text-zinc-300 transition-colors opacity-0 group-hover:opacity-100">
                          <Copy className="w-3 h-3" />
                        </button>
                      )}
                    </div>
                  </div>

                  {/* To */}
                  <div className="flex flex-col gap-1.5 justify-center">
                    <div className="h-5 flex items-center">
                      <div className="w-16 h-1.5 rounded-full bg-zinc-800/80"></div>
                    </div>
                    <div className="flex items-center gap-1.5 text-xs text-zinc-500 font-mono">
                      <span>Recipient: {truncate(toAddress)}</span>
                      {toAddress !== 'ArcPay Contract' && (
                        <button onClick={() => copy(toAddress)} className="hover:text-zinc-300 transition-colors opacity-0 group-hover:opacity-100">
                          <Copy className="w-3 h-3" />
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Transaction */}
                  <div className="flex flex-col gap-1.5 justify-center">
                    <div className="flex items-center gap-2 text-xs font-medium text-zinc-300">
                      <span className="text-zinc-500">{actionType}:</span>
                      {url ? (
                        <a href={url} target="_blank" rel="noopener noreferrer" className="text-sky-400 hover:text-sky-300 font-mono flex items-center gap-1">
                          {truncate(ev.txHash, 4)}
                          <ExternalLink className="w-3 h-3" />
                        </a>
                      ) : (
                        <span className="font-mono">{truncate(ev.txHash, 4)}</span>
                      )}
                    </div>
                  </div>

                  {/* Status */}
                  <div className="flex items-center">
                    <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[11px] font-medium tracking-wide uppercase">
                      <CheckCircle2 className="w-3 h-3" />
                      Confirmed
                    </div>
                  </div>

                  {/* Time */}
                  <div className="flex flex-col gap-1 md:items-end justify-center">
                    <div className="text-xs text-zinc-400 font-medium">
                      {timeAgo(ev.timestamp)}
                    </div>
                    <div className="text-[10px] text-zinc-600 mt-0.5">
                      Block {ev.blockNumber.toString()}
                    </div>
                  </div>

                </motion.div>
              );
            })}
          </motion.div>
        )}
      </div>
    </>
  );
}
