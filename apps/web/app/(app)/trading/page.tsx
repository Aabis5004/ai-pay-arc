'use client';

import { motion } from 'framer-motion';
import { PageHeader } from '@/components/PageHeader';
import { ChatPanel } from '@/components/ChatPanel';
import { Info } from 'lucide-react';

export default function TradingPage() {
  return (
    <>
      <PageHeader
        title="Flow AI"
        subtitle="Ask about FlowPay, or tell the agent to deposit, send, and check balances."
      />

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="bg-zinc-900/40 border border-zinc-800 rounded-2xl p-5 mb-6 backdrop-blur flex items-start gap-3"
      >
        <Info className="w-4 h-4 text-sky-400 mt-0.5 shrink-0" />
        <div className="text-xs text-zinc-300 leading-relaxed">
          <strong className="text-zinc-100">Flow AI</strong> can answer questions
          about FlowPay — what it is, how App Kit works, how it's built for programmable money
          — and it can also act: deposit USDC, send transfers, and
          check your balance. Just ask in plain English.
        </div>
      </motion.div>

      <div className="max-w-3xl">
        <motion.div
          initial={{ opacity: 0, x: -16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className=""
        >
          <ChatPanel />
        </motion.div>
      </div>
    </>
  );
}
