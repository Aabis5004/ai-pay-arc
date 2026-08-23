'use client';

import { motion } from 'framer-motion';

const actions = [
  { label: 'Check balance', hint: '"What\'s my balance?"' },
  { label: 'Deposit', hint: '"Deposit 100 USDC"' },
  { label: 'Send', hint: '"Send 50 USDC to 0x123..."' },
];

export function QuickActions() {
  return (
    <motion.div
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.5, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
      className="space-y-2"
    >
      <div className="text-xs uppercase tracking-widest text-zinc-500 mb-3">
        Quick actions
      </div>
      {actions.map((a, i) => (
        <motion.div
          key={a.label}
          initial={{ opacity: 0, x: 10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.3 + i * 0.08 }}
          className="bg-zinc-900/60 border border-zinc-800 rounded-xl p-4 hover:border-zinc-700 transition-colors cursor-default"
        >
          <div className="font-medium text-sm">{a.label}</div>
          <div className="text-xs text-zinc-500 mt-1 font-mono">{a.hint}</div>
        </motion.div>
      ))}
    </motion.div>
  );
}
