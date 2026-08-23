'use client';

import { motion } from 'framer-motion';

export function ActivityFeed() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.3, ease: [0.16, 1, 0.3, 1] }}
      className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
    >
      <div className="text-xs uppercase tracking-widest text-zinc-500 mb-3">
        Activity
      </div>
      <div className="text-sm text-zinc-600 leading-relaxed">
        Recent transactions will appear here once you start sending payments.
        Privacy note: only the fact that a tx happened is public — amounts stay
        shielded.
      </div>
    </motion.div>
  );
}
