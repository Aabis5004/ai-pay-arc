'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { X, CheckCircle2, ArrowUpRight } from 'lucide-react';
import { explorerTxUrl } from '@/lib/explorer';
import { arcTestnet } from '@/lib/chain';

interface TxModalProps {
  isOpen: boolean;
  onClose: () => void;
  hash: string;
  sentAmount?: string;
  sentToken?: string;
  receivedAmount?: string;
  receivedToken?: string;
  actionText?: string; // "Staked", "Swapped", "Liquidity Added" etc.
}

export function TxModal({
  isOpen,
  onClose,
  hash,
  sentAmount,
  sentToken,
  receivedAmount,
  receivedToken,
  actionText = "Transaction Completed"
}: TxModalProps) {
  const txUrl = explorerTxUrl(hash, arcTestnet.id);

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 10 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 10 }}
            className="relative w-full max-w-md bg-zinc-950/95 backdrop-blur-xl border border-zinc-800/80 rounded-[24px] shadow-2xl overflow-hidden"
          >
            {/* Header */}
            <div className="flex justify-between items-center p-5 border-b border-zinc-800/50">
              <h2 className="text-zinc-100 font-semibold text-lg">Transaction Details</h2>
              <button
                onClick={onClose}
                className="text-zinc-500 hover:text-zinc-300 transition-colors p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Content */}
            <div className="p-8 flex flex-col items-center">
              <div className="relative mb-6">
                <div className="w-16 h-16 bg-sky-500/20 border border-sky-500/30 rounded-2xl flex items-center justify-center transform rotate-12 shadow-lg">
                  <div className="w-8 h-8 bg-sky-400/30 rounded-full" />
                </div>
                <div className="absolute -bottom-2 -right-2 bg-zinc-950 rounded-full p-0.5">
                  <CheckCircle2 className="w-8 h-8 text-sky-400" />
                </div>
              </div>
              
              <h3 className="text-xl font-bold text-white mb-8">{actionText}</h3>

              <div className="w-full bg-zinc-900/50 border border-zinc-800/50 rounded-2xl p-4 space-y-4">
                {sentAmount && sentToken && (
                  <div className="flex justify-between items-center">
                    <div className="flex items-center gap-2">
                      <div className="bg-zinc-800/80 px-2 py-1 rounded-md text-xs font-semibold text-zinc-400 shadow-sm">
                        Sent
                      </div>
                      <span className="font-medium text-zinc-200">{sentAmount} {sentToken}</span>
                    </div>
                    <a href={txUrl || '#'} target="_blank" rel="noreferrer" className="text-sky-400 font-mono text-sm hover:underline">
                      {hash.slice(0, 6)}...{hash.slice(-4)}
                    </a>
                  </div>
                )}
                
                {receivedAmount && receivedToken && (
                  <div className="flex justify-between items-center">
                    <div className="flex items-center gap-2">
                      <div className="bg-zinc-800/80 px-2 py-1 rounded-md text-xs font-semibold text-zinc-400 shadow-sm">
                        Received
                      </div>
                      <span className="font-medium text-zinc-200">{receivedAmount} {receivedToken}</span>
                    </div>
                    <a href={txUrl || '#'} target="_blank" rel="noreferrer" className="text-sky-400 font-mono text-sm hover:underline">
                      {hash.slice(0, 6)}...{hash.slice(-4)}
                    </a>
                  </div>
                )}
                
                {/* Fallback if no specific amounts are provided */}
                {(!sentAmount && !receivedAmount) && (
                   <div className="flex justify-between items-center">
                     <span className="font-medium text-zinc-400">Transaction Hash</span>
                     <a href={txUrl || '#'} target="_blank" rel="noreferrer" className="text-sky-400 font-mono text-sm hover:underline">
                      {hash.slice(0, 6)}...{hash.slice(-4)}
                    </a>
                   </div>
                )}
              </div>
            </div>

            {/* Footer */}
            <div className="p-5 flex gap-3">
              <a
                href={txUrl || '#'}
                target="_blank"
                rel="noreferrer"
                className="flex-1 flex items-center justify-center gap-2 bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 text-sky-400 font-bold py-3.5 rounded-xl transition-colors"
              >
                VIEW DETAILS
                <ArrowUpRight className="w-4 h-4" />
              </a>
              <button
                onClick={onClose}
                className="flex-1 bg-sky-500 hover:bg-sky-400 text-white font-bold py-3.5 rounded-xl transition-colors shadow-[0_0_20px_rgba(14,165,233,0.3)] hover:shadow-[0_0_25px_rgba(14,165,233,0.5)]"
              >
                DONE
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}
