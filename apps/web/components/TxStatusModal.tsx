'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { CheckCircle2, XCircle, Loader2, ExternalLink } from 'lucide-react';
import { useChainId } from 'wagmi';
import { explorerTxUrl } from '@/lib/explorer';

export type TxStatus =
  | { state: 'idle' }
  | { state: 'preparing'; summary: string }
  | { state: 'signing'; summary: string }
  | { state: 'broadcasting'; summary: string }
  | { state: 'confirming'; summary: string; hash: string }
  | { state: 'confirmed'; summary: string; hash: string }
  | { state: 'failed'; summary: string; error: string };

export function TxStatusModal({
  status,
  onClose,
}: {
  status: TxStatus;
  onClose: () => void;
}) {
  const chainId = useChainId();
  const open = status.state !== 'idle';

  const hash =
    'hash' in status && status.hash ? status.hash : null;
  const explorerUrl = hash ? explorerTxUrl(hash, chainId) : null;

  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm"
            onClick={status.state === 'confirmed' || status.state === 'failed' ? onClose : undefined}
          />
          <motion.div
            initial={{ opacity: 0, y: 20, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.96 }}
            transition={{ type: 'spring', stiffness: 320, damping: 28 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none"
          >
            <div className="w-full max-w-md bg-zinc-900 border border-zinc-800 rounded-2xl p-6 pointer-events-auto shadow-2xl">
              <StatusIcon status={status} />
              <div className="text-center mt-4">
                <div className="text-sm font-medium text-zinc-100">
                  {statusTitle(status)}
                </div>
                <div className="text-xs text-zinc-500 mt-1">
                  {'summary' in status ? status.summary : ''}
                </div>
              </div>

              {hash && (
                <div className="mt-5 p-3 bg-zinc-950/60 border border-zinc-800 rounded-lg">
                  <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mb-1">
                    Transaction
                  </div>
                  <div className="text-[11px] font-mono text-zinc-300 break-all">
                    {hash}
                  </div>
                  {explorerUrl && (
                    <a
                      href={explorerUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 mt-2 text-xs text-violet-400 hover:text-violet-300"
                    >
                      View on explorer <ExternalLink className="w-3 h-3" />
                    </a>
                  )}
                </div>
              )}

              {status.state === 'failed' && (
                <div className="mt-4 p-3 bg-red-950/30 border border-red-900/40 rounded-lg">
                  <div className="text-[11px] font-mono text-red-300 break-all">
                    {status.error}
                  </div>
                </div>
              )}

              {(status.state === 'confirmed' || status.state === 'failed') && (
                <button
                  onClick={onClose}
                  className="w-full mt-5 py-2.5 bg-zinc-800 hover:bg-zinc-700 rounded-lg text-sm font-medium transition-colors"
                >
                  Done
                </button>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}

function StatusIcon({ status }: { status: TxStatus }) {
  if (status.state === 'confirmed')
    return (
      <div className="flex justify-center">
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: 'spring', stiffness: 260, damping: 20 }}
          className="w-14 h-14 rounded-full bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center"
        >
          <CheckCircle2 className="w-7 h-7 text-emerald-400" />
        </motion.div>
      </div>
    );
  if (status.state === 'failed')
    return (
      <div className="flex justify-center">
        <div className="w-14 h-14 rounded-full bg-red-500/15 border border-red-500/30 flex items-center justify-center">
          <XCircle className="w-7 h-7 text-red-400" />
        </div>
      </div>
    );
  return (
    <div className="flex justify-center">
      <div className="w-14 h-14 rounded-full bg-violet-500/15 border border-violet-500/30 flex items-center justify-center">
        <Loader2 className="w-7 h-7 text-violet-400 animate-spin" />
      </div>
    </div>
  );
}

function statusTitle(s: TxStatus): string {
  switch (s.state) {
    case 'preparing':
      return 'Preparing transaction';
    case 'signing':
      return 'Confirm in your wallet';
    case 'broadcasting':
      return 'Broadcasting to network';
    case 'confirming':
      return 'Confirming on chain';
    case 'confirmed':
      return 'Transaction confirmed';
    case 'failed':
      return 'Transaction failed';
    default:
      return '';
  }
}
