'use client';

import { motion } from 'framer-motion';
import { useEffect, useRef, useState } from 'react';
import { useShielded } from '@/lib/useShielded';
import { executeTool, type ToolCall, type ToolResult } from '@/lib/tools';
import { useToast } from './Toast';

export function ToolConfirmation({
  call,
  onResult,
}: {
  call: ToolCall;
  onResult: (r: ToolResult) => void;
}) {
  const { walletClient, account } = useShielded();
  const [status, setStatus] = useState<'idle' | 'running' | 'done'>('idle');
  const startedRef = useRef(false);
  const toast = useToast();

  const isReadOnly = call.name === 'get_balance';

  const run = async () => {
    if (startedRef.current) return;
    startedRef.current = true;
    setStatus('running');
    const result = await executeTool(call, walletClient, account);
    setStatus('done');
    onResult(result);
    if (result.ok) {
      toast.push({
        kind: 'success',
        title: result.data,
        body: result.hash ? `Tx: ${result.hash.slice(0, 18)}…` : undefined,
      });
    } else if (call.name !== 'get_balance') {
      toast.push({ kind: 'error', title: 'Action failed', body: result.error });
    }
  };

  useEffect(() => {
    if (isReadOnly && status === 'idle' && walletClient && account) {
      run();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isReadOnly, walletClient, account]);

  const summary = (() => {
    if (call.name === 'send_payment')
      return `Send ${call.args.amount} USDC to ${String(call.args.to).slice(0, 8)}…`;
    if (call.name === 'deposit')
      return `Deposit ${call.args.amount} USDC to shielded vault`;
    if (call.name === 'get_balance') return 'Reading shielded balance';
    return call.name;
  })();

  if (isReadOnly) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: 1, y: 0 }}
        className="mt-2 text-xs text-zinc-500 italic"
      >
        → {summary}
        {status === 'running' ? '…' : ''}
      </motion.div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      className="mt-3 p-3 bg-zinc-950/60 border border-violet-900/50 rounded-lg"
    >
      <div className="text-[10px] uppercase tracking-[0.15em] text-violet-400 mb-1">
        Proposed action
      </div>
      <div className="text-sm mb-3 break-words">{summary}</div>
      {status === 'idle' && (
        <div className="flex gap-2">
          <button
            onClick={run}
            className="flex-1 px-3 py-2 bg-violet-600 hover:bg-violet-500 rounded-md text-xs font-medium transition-colors"
          >
            Confirm &amp; sign
          </button>
          <button
            onClick={() => onResult({ ok: false, error: 'Cancelled' })}
            className="px-3 py-2 bg-zinc-800 hover:bg-zinc-700 rounded-md text-xs font-medium transition-colors"
          >
            Cancel
          </button>
        </div>
      )}
      {status === 'running' && (
        <div className="text-xs text-zinc-400 flex items-center gap-2">
          <span className="w-2 h-2 bg-violet-500 rounded-full animate-pulse" />
          Signing &amp; broadcasting…
        </div>
      )}
    </motion.div>
  );
}
