'use client';

import { motion } from 'framer-motion';
import { useChainId, useSwitchChain } from 'wagmi';
import { AlertTriangle } from 'lucide-react';
import { ACTIVE_CHAIN } from '@/lib/chain';

export function NetworkGate({ children }: { children: React.ReactNode }) {
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  if (chainId === ACTIVE_CHAIN.id) return <>{children}</>;

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-amber-950/30 border border-amber-900/50 rounded-2xl p-6 mb-6"
    >
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
        <div className="flex-1">
          <div className="text-sm font-medium text-amber-200 mb-1">
            Wrong network
          </div>
          <div className="text-xs text-amber-300/70 mb-4">
            Your wallet is on chain {chainId || 'unknown'}. AI Pay Seismic is
            configured for <strong>{ACTIVE_CHAIN.name}</strong> (chain {ACTIVE_CHAIN.id}).
          </div>
          <button
            onClick={() => switchChain({ chainId: ACTIVE_CHAIN.id })}
            disabled={isPending}
            className="px-4 py-2 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 rounded-lg text-sm font-medium text-amber-50 transition-colors"
          >
            {isPending ? 'Switching…' : `Switch to ${ACTIVE_CHAIN.name}`}
          </button>
        </div>
      </div>
    </motion.div>
  );
}
