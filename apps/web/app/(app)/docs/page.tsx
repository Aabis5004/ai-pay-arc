
'use client';

import { motion } from 'framer-motion';
import { ArrowRight, CheckCircle2, Cpu, Zap, Activity, Layers, ShieldCheck } from 'lucide-react';
import Link from 'next/link';

export default function DocsPage() {
  return (
    <div className="relative min-h-screen pb-24 overflow-hidden" style={{ fontFamily: 'var(--font-sans)' }}>
      {/* Ambient Animated Background (Rialo/Glue-Bill Inspiration) */}
      <div className="fixed inset-0 z-0 pointer-events-none overflow-hidden">
        <motion.div 
          animate={{ x: [0, 100, 0], y: [0, -50, 0], scale: [1, 1.1, 1] }} 
          transition={{ duration: 20, repeat: Infinity, ease: "easeInOut" }}
          className="absolute top-[-100px] left-[-100px] w-[500px] h-[500px] rounded-full bg-emerald-500/10 blur-[100px]"
        />
        <motion.div 
          animate={{ x: [0, -100, 0], y: [0, 80, 0], scale: [1, 1.15, 1] }} 
          transition={{ duration: 25, repeat: Infinity, ease: "easeInOut", delay: 2 }}
          className="absolute bottom-[-150px] right-[-100px] w-[600px] h-[600px] rounded-full bg-cyan-500/10 blur-[120px]"
        />
        <motion.div 
          animate={{ x: [0, 50, 0], y: [0, -80, 0], scale: [1, 1.05, 1] }} 
          transition={{ duration: 18, repeat: Infinity, ease: "easeInOut", delay: 5 }}
          className="absolute top-[30%] left-[30%] w-[400px] h-[400px] rounded-full bg-violet-500/10 blur-[100px]"
        />
        <div className="absolute inset-0 opacity-[0.03]" style={{ backgroundImage: 'linear-gradient(rgba(255,255,255,1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,1) 1px, transparent 1px)', backgroundSize: '40px 40px', maskImage: 'radial-gradient(ellipse at 50% 30%, black 20%, transparent 70%)' }}></div>
      </div>

      <div className="relative z-10 max-w-5xl mx-auto pt-16">
        
        {/* Header Section */}
        <header className="mb-20 max-w-3xl">
          <motion.div 
            initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }}
            className="flex items-center gap-3 text-emerald-400 mb-6 font-mono text-xs uppercase tracking-[0.2em]"
            style={{ fontFamily: 'var(--font-space-mono)' }}
          >
            <span className="w-8 h-px bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.8)]"></span>
            Architecture & Roadmap
          </motion.div>
          
          <motion.h1 
            initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6, delay: 0.1 }}
            className="text-5xl md:text-6xl lg:text-7xl font-bold tracking-tight mb-6"
            style={{ fontFamily: 'var(--font-bricolage)' }}
          >
            The stack collapses <br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-rose-400 to-amber-300 drop-shadow-[0_0_15px_rgba(251,113,133,0.3)]">into the chain.</span>
          </motion.h1>
          
          <motion.p 
            initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6, delay: 0.2 }}
            className="text-lg text-zinc-400 leading-relaxed"
          >
            FlowPay is evolving. Our upcoming roadmap introduces fully on-chain <b>Recurring Payments</b>, eliminating fragile off-chain automation bots by leveraging the native capabilities of the <b>Rialo</b> infrastructure.
          </motion.p>
        </header>

        {/* Section 1: Roadmap */}
        <motion.div 
          initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.8 }}
          className="mb-24"
        >
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-3xl font-bold" style={{ fontFamily: 'var(--font-bricolage)' }}>The Roadmap: Recurring Payments</h2>
            <div className="px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs font-mono uppercase tracking-wider">Q4 2026 Focus</div>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            
            {/* Glass Card 1 */}
            <div className="relative group p-8 rounded-[24px] bg-zinc-950/40 border border-zinc-800/60 backdrop-blur-xl shadow-[0_20px_50px_-20px_rgba(0,0,0,0.5)] overflow-hidden transition-all duration-500 hover:border-emerald-500/40 hover:shadow-[0_20px_60px_-20px_rgba(52,211,153,0.15)]">
              <div className="absolute inset-0 bg-gradient-to-br from-emerald-500/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>
              <Activity className="w-8 h-8 text-emerald-400 mb-6" />
              <h3 className="text-xl font-bold text-zinc-100 mb-3" style={{ fontFamily: 'var(--font-bricolage)' }}>Streaming Vaults</h3>
              <p className="text-zinc-400 text-sm leading-relaxed mb-6">Users deposit USDC into the FlowPay vault once. Funds are then continuously streamed or pulled on a schedule by authorized merchants without requiring repetitive manual approvals.</p>
              
              <div className="space-y-3">
                <div className="flex items-center gap-3 text-xs font-mono text-zinc-500">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" /> Auto-renewing subscriptions
                </div>
                <div className="flex items-center gap-3 text-xs font-mono text-zinc-500">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" /> Payroll streaming
                </div>
              </div>
            </div>

            {/* Glass Card 2 */}
            <div className="relative group p-8 rounded-[24px] bg-zinc-950/40 border border-zinc-800/60 backdrop-blur-xl shadow-[0_20px_50px_-20px_rgba(0,0,0,0.5)] overflow-hidden transition-all duration-500 hover:border-cyan-500/40 hover:shadow-[0_20px_60px_-20px_rgba(34,211,238,0.15)]">
              <div className="absolute inset-0 bg-gradient-to-br from-cyan-500/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>
              <Cpu className="w-8 h-8 text-cyan-400 mb-6" />
              <h3 className="text-xl font-bold text-zinc-100 mb-3" style={{ fontFamily: 'var(--font-bricolage)' }}>Flow AI Agent Automation</h3>
              <p className="text-zinc-400 text-sm leading-relaxed mb-6">Our integrated AI agent acts as a co-pilot, monitoring your vault liquidity and proactively suggesting swaps or alerting you before a major recurring payment is due.</p>
              
              <div className="space-y-3">
                <div className="flex items-center gap-3 text-xs font-mono text-zinc-500">
                  <CheckCircle2 className="w-4 h-4 text-cyan-500" /> Natural language scheduling
                </div>
                <div className="flex items-center gap-3 text-xs font-mono text-zinc-500">
                  <CheckCircle2 className="w-4 h-4 text-cyan-500" /> Predictive balance alerts
                </div>
              </div>
            </div>

          </div>
        </motion.div>

        {/* Section 2: Rialo Integration */}
        <motion.div 
          initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.8 }}
          className="relative p-10 md:p-14 rounded-[32px] bg-zinc-900/30 border border-zinc-800/50 backdrop-blur-2xl overflow-hidden"
        >
          {/* Inner glowing ring effect */}
          <div className="absolute inset-0 rounded-[32px] border-[1px] border-white/5 opacity-50" style={{ maskImage: 'linear-gradient(to bottom, white, transparent)' }}></div>
          <div className="absolute top-0 left-1/4 right-1/4 h-[1px] bg-gradient-to-r from-transparent via-violet-500 to-transparent opacity-50"></div>

          <div className="flex flex-col md:flex-row gap-12 items-center relative z-10">
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-4">
                <Layers className="w-5 h-5 text-violet-400" />
                <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-violet-400">Powered by Rialo</span>
              </div>
              
              <h2 className="text-3xl md:text-4xl font-bold mb-6" style={{ fontFamily: 'var(--font-bricolage)' }}>
                Reactive Transactions
              </h2>
              
              <p className="text-zinc-400 text-sm md:text-base leading-relaxed mb-6">
                Current blockchain applications rely on a fragile tower of off-chain automation. Blockchains are fundamentally synchronous systems. 
              </p>
              <p className="text-zinc-400 text-sm md:text-base leading-relaxed mb-8">
                By integrating with <b>Rialo</b>—the infrastructure for the next generation of intelligent systems—FlowPay brings <b>native automation</b> to our smart contracts. Recurring payments are triggered natively on-chain without the "Glue Bill" of centralized relayers and keepers.
              </p>

              <div className="grid grid-cols-2 gap-4">
                <div className="p-4 rounded-2xl bg-zinc-950/50 border border-zinc-800">
                  <div className="font-bold text-lg text-white mb-1" style={{ fontFamily: 'var(--font-bricolage)' }}>Supermodularity</div>
                  <div className="text-[10px] text-zinc-500 font-mono uppercase tracking-widest">Architecture</div>
                </div>
                <div className="p-4 rounded-2xl bg-zinc-950/50 border border-zinc-800">
                  <div className="font-bold text-lg text-white mb-1" style={{ fontFamily: 'var(--font-bricolage)' }}>Gauss SMR</div>
                  <div className="text-[10px] text-zinc-500 font-mono uppercase tracking-widest">Protocol Safety</div>
                </div>
              </div>
            </div>
            
            <div className="flex-1 w-full max-w-sm">
              <div className="relative aspect-square rounded-[32px] border border-violet-500/30 bg-gradient-to-br from-violet-500/10 to-transparent flex items-center justify-center shadow-[0_0_80px_-20px_rgba(139,92,246,0.2)]">
                <div className="absolute inset-2 border border-white/5 rounded-[24px]"></div>
                <Zap className="w-24 h-24 text-violet-400 drop-shadow-[0_0_30px_rgba(139,92,246,0.6)]" />
              </div>
            </div>
          </div>
        </motion.div>

      </div>
    </div>
  );
}
