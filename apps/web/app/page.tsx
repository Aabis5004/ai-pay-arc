'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { motion } from 'framer-motion';
import { Shield, Sparkles, Lock, Zap } from 'lucide-react';

const features = [
  {
    icon: Shield,
    title: 'Secure by default',
    body: 'Balances and amounts are securely managed on-chain via Arc Pay contracts.',
  },
  {
    icon: Sparkles,
    title: 'Just tell the agent',
    body: 'Natural language for sends, deposits, balance checks.',
  },
  {
    icon: Lock,
    title: 'Yours alone',
    body: 'Signed reads ensure only you can see your own balance.',
  },
  {
    icon: Zap,
    title: 'Sub-second finality',
    body: 'Built on Arc Testnet for fast settlement.',
  },
];

export default function Home() {
  const { ready, authenticated, login } = usePrivy();
  const router = useRouter();

  useEffect(() => {
    if (ready && authenticated) router.replace('/dashboard');
  }, [ready, authenticated, router]);

  if (!ready) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <main className="min-h-screen relative overflow-hidden bg-grid">
      <div
        aria-hidden
        className="absolute top-0 left-1/2 -translate-x-1/2 w-[800px] h-[400px] bg-violet-600/20 rounded-full blur-3xl pointer-events-none"
      />
      <div
        aria-hidden
        className="absolute bottom-0 right-0 w-[500px] h-[500px] bg-cyan-500/10 rounded-full blur-3xl pointer-events-none"
      />

      <div className="relative max-w-5xl mx-auto px-6 py-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-medium text-white/60 mb-8">
            <div className="w-1.5 h-1.5 rounded-full bg-violet-500" />
            Built on Arc
          </div>
          <h1 className="text-6xl md:text-7xl tracking-tight leading-[1.05] mb-6">
            Smart payments,
            <br />
            <span className="font-display italic text-violet-300">spoken plainly.</span>
          </h1>
          <p className="text-lg text-zinc-400 max-w-xl mx-auto mb-10 leading-relaxed">
            Tell the agent what to do. Send, deposit, check balances — all
            secure, all on-chain, all without leaving the conversation.
          </p>
          <motion.button
            whileHover={{ scale: 1.03 }}
            whileTap={{ scale: 0.97 }}
            onClick={login}
            className="px-7 py-3.5 bg-violet-600 hover:bg-violet-500 transition-colors rounded-xl text-base font-medium shadow-lg shadow-violet-900/40"
          >
            Sign in to begin
          </motion.button>
        </motion.div>

        <motion.div
          initial="hidden"
          animate="show"
          variants={{
            hidden: {},
            show: { transition: { staggerChildren: 0.08, delayChildren: 0.4 } },
          }}
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-12"
        >
          {features.map((f) => {
            const Icon = f.icon;
            return (
              <motion.div
                key={f.title}
                variants={{
                  hidden: { opacity: 0, y: 16 },
                  show: { opacity: 1, y: 0 },
                }}
                whileHover={{ y: -3 }}
                className="bg-zinc-900/40 border border-zinc-800/80 backdrop-blur rounded-2xl p-5 transition-colors hover:border-zinc-700"
              >
                <Icon className="w-5 h-5 text-violet-400 mb-3" />
                <div className="text-sm font-medium mb-1.5">{f.title}</div>
                <div className="text-xs text-zinc-500 leading-relaxed">
                  {f.body}
                </div>
              </motion.div>
            );
          })}
        </motion.div>

        <div className="text-center mt-20 text-xs text-zinc-600">
          Phase 4 build · Local sanvil · Gemini agent
        </div>
      </div>
    </main>
  );
}
