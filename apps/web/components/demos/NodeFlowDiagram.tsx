
'use client';

import { motion } from 'framer-motion';
import { Database, Server, Clock, Webhook, Search, Activity, RotateCcw, Link } from 'lucide-react';

const NODES = [
  { id: 'oracle', name: 'Oracle', desc: 'external data', icon: Database },
  { id: 'vps', name: 'VPS, 24/7', desc: 'always-on', icon: Server },
  { id: 'cron', name: 'Cron jobs', desc: 'scheduling', icon: Clock },
  { id: 'webhook', name: 'Webhooks', desc: 'events', icon: Webhook },
  { id: 'indexer', name: 'Indexer', desc: 'query state', icon: Search },
];

export function NodeFlowDiagram() {
  return (
    <div className="w-full max-w-5xl mx-auto my-16 bg-[#0B0B0F] border border-zinc-800/80 rounded-[24px] p-8 lg:p-12 overflow-hidden relative shadow-2xl">
      <div className="max-w-xl mb-12">
        <h2 className="text-2xl font-bold text-white mb-3">Network of Services</h2>
        <p className="text-zinc-400 text-sm leading-relaxed">
          A typical autonomous dApp isn't one thing. It's an oracle, a server that never sleeps, and a pile of glue in between. Each node is a place to break, and a monthly bill.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_auto_1.2fr] gap-8 items-center min-h-[400px]">
        
        {/* Left: Off-Chain Nodes */}
        <div className="flex flex-col gap-3 relative z-10">
          <div className="text-[10px] text-zinc-500 font-mono uppercase tracking-[0.15em] mb-2">Off-chain, Today</div>
          {NODES.map((node, i) => (
            <motion.div 
              key={node.id}
              initial={{ opacity: 0, x: -20 }}
              whileInView={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              viewport={{ once: true }}
              className="flex items-center justify-between bg-zinc-900/60 border border-zinc-800/80 p-3.5 rounded-xl hover:border-emerald-500/50 hover:shadow-[0_0_20px_-5px_rgba(52,211,153,0.2)] transition-all group cursor-pointer relative"
            >
              <div className="flex items-center gap-3">
                <div className="w-2 h-2 rounded-full bg-zinc-600 group-hover:bg-emerald-400 group-hover:shadow-[0_0_8px_rgba(52,211,153,0.8)] transition-all" />
                <span className="text-sm text-zinc-200 font-medium group-hover:text-white transition-colors">{node.name}</span>
              </div>
              <span className="text-[10px] text-zinc-500 font-mono">{node.desc}</span>
            </motion.div>
          ))}
        </div>

        {/* Middle: Flow Lines (SVG) */}
        <div className="hidden lg:block w-[120px] h-[350px] relative">
          <svg className="absolute inset-0 w-full h-full" overflow="visible">
            {NODES.map((_, i) => {
              const startY = 30 + (i * 62);
              const endY = 175;
              const controlX = 60;
              return (
                <motion.path
                  key={i}
                  d={`M 0 ${startY} C ${controlX} ${startY}, ${controlX} ${endY}, 120 ${endY}`}
                  fill="none"
                  stroke="rgba(52,211,153,0.4)"
                  strokeWidth="1.5"
                  strokeDasharray="6 6"
                  animate={{ strokeDashoffset: [-24, 0] }}
                  transition={{ duration: 1.5, repeat: Infinity, ease: "linear" }}
                />
              );
            })}
          </svg>
        </div>

        {/* Right: One Chain */}
        <motion.div 
          initial={{ opacity: 0, scale: 0.95 }}
          whileInView={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.7, delay: 0.4 }}
          viewport={{ once: true }}
          className="relative z-10"
        >
          <div className="text-[10px] text-emerald-400 font-mono uppercase tracking-[0.15em] mb-2 pl-2">On Rialo</div>
          <div className="relative bg-gradient-to-br from-emerald-500/10 to-transparent border-[1.5px] border-emerald-500/60 rounded-[24px] p-8 lg:p-10 shadow-[0_0_50px_-15px_rgba(52,211,153,0.3)]">
            {/* Pulsing ring */}
            <motion.div 
              animate={{ opacity: [0.5, 0], scale: [1, 1.05] }}
              transition={{ duration: 2.5, repeat: Infinity, ease: "easeOut", delay: 1 }}
              className="absolute inset-[-2px] rounded-[24px] border border-emerald-400 pointer-events-none"
            />
            
            <div className="flex items-center gap-3 mb-6">
              <svg viewBox="0 0 24 24" fill="none" className="w-8 h-8 text-emerald-400 drop-shadow-[0_0_8px_rgba(52,211,153,0.6)]">
                <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
              <h3 className="text-2xl font-bold text-white tracking-tight">One chain</h3>
            </div>
            
            <ul className="space-y-4">
              {['Fetches live data over HTTPS', 'Wakes on real-world events', 'Schedules itself, natively', 'Keeps data private when needed'].map((text, i) => (
                <li key={i} className="flex items-center gap-3 text-sm text-zinc-300">
                  <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.8)]" />
                  {text}
                </li>
              ))}
            </ul>

            <div className="mt-8 pt-6 border-t border-emerald-500/20 text-[11px] font-mono text-emerald-400/80 tracking-widest uppercase">
              write it once → no keepers. no glue
            </div>
          </div>
        </motion.div>

      </div>
    </div>
  );
}
