
'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Settings, Zap } from 'lucide-react';

const SERVICES = [
  { id: 'price', name: 'Price & data feeds', desc: 'Oracle network for external data', baseCost: 400 },
  { id: 'api', name: 'Custom API calls', desc: 'Chainlink Functions or similar', baseCost: 150 },
  { id: 'keepers', name: 'Keepers & automation', desc: 'Bots triggering your contract', baseCost: 200 },
  { id: 'indexer', name: 'Indexer / subgraph', desc: 'Making chain state queryable', baseCost: 300 },
  { id: 'rpc', name: 'RPC & node access', desc: 'Reading and writing to the chain', baseCost: 500 },
  { id: 'servers', name: 'Always-on servers', desc: 'VPS keeping your bots alive', baseCost: 200 },
];

export function GlueBillCalculator() {
  const [scale, setScale] = useState<'side' | 'growing' | 'prod'>('growing');
  const [activeServices, setActiveServices] = useState<string[]>(SERVICES.map(s => s.id));
  const [flipped, setFlipped] = useState(false);

  const multiplier = scale === 'side' ? 0.2 : scale === 'growing' ? 1 : 4.5;
  
  const toggleService = (id: string) => {
    setActiveServices(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  };

  const totalCost = SERVICES
    .filter(s => activeServices.includes(s.id))
    .reduce((sum, s) => sum + (s.baseCost * multiplier), 0);

  return (
    <div className="w-full max-w-5xl mx-auto my-16 font-sans">
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_420px] gap-8 items-start">
        
        {/* Left Column: Toggles */}
        <div className="bg-[#12131C]/50 backdrop-blur-xl border border-zinc-800/80 rounded-[20px] p-6 lg:p-8 shadow-2xl">
          <div className="mb-8">
            <h2 className="text-xl font-bold text-white mb-2">What are you running?</h2>
            <p className="text-sm text-zinc-400">Pick your scale, then toggle the services your app depends on.</p>
          </div>

          <div className="flex bg-[#0A0A0E]/60 p-1.5 rounded-xl border border-zinc-800/50 mb-8">
            <button 
              onClick={() => setScale('side')}
              className={`flex-1 py-2.5 rounded-lg text-xs font-mono transition-all ${scale === 'side' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/30' : 'text-zinc-500 hover:text-zinc-300 border border-transparent'}`}
            >
              <span className="block font-bold text-sm mb-0.5 font-sans">Side project</span>
              low traffic
            </button>
            <button 
              onClick={() => setScale('growing')}
              className={`flex-1 py-2.5 rounded-lg text-xs font-mono transition-all ${scale === 'growing' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/30' : 'text-zinc-500 hover:text-zinc-300 border border-transparent'}`}
            >
              <span className="block font-bold text-sm mb-0.5 font-sans">Growing app</span>
              real users
            </button>
            <button 
              onClick={() => setScale('prod')}
              className={`flex-1 py-2.5 rounded-lg text-xs font-mono transition-all ${scale === 'prod' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/30' : 'text-zinc-500 hover:text-zinc-300 border border-transparent'}`}
            >
              <span className="block font-bold text-sm mb-0.5 font-sans">Production</span>
              at scale
            </button>
          </div>

          <div className="space-y-2">
            {SERVICES.map(service => {
              const isActive = activeServices.includes(service.id);
              const cost = service.baseCost * multiplier;
              return (
                <button
                  key={service.id}
                  onClick={() => toggleService(service.id)}
                  className={`w-full flex items-center gap-4 p-3.5 rounded-xl border transition-all text-left group
                    ${isActive 
                      ? 'bg-rose-500/5 border-rose-500/30 hover:border-rose-500/50' 
                      : 'bg-[#0A0A0E]/40 border-zinc-800/50 hover:border-zinc-700 hover:translate-x-1'}`}
                >
                  <div className={`w-9 h-5 rounded-full relative transition-colors ${isActive ? 'bg-rose-500/30' : 'bg-zinc-800'}`}>
                    <div className={`absolute top-1 w-3 h-3 rounded-full transition-all ${isActive ? 'bg-rose-400 left-5 shadow-[0_0_10px_rgba(251,113,133,0.8)]' : 'bg-zinc-500 left-1'}`} />
                  </div>
                  <div className="flex-1">
                    <div className="font-semibold text-sm text-zinc-200 group-hover:text-white transition-colors">{service.name}</div>
                    <div className="text-[11px] text-zinc-500">{service.desc}</div>
                  </div>
                  <div className={`font-mono text-xs ${isActive ? 'text-rose-400' : 'text-zinc-600'}`}>
                    ${(cost).toLocaleString()}
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Right Column: Receipt */}
        <div className="relative sticky top-24">
          <div className={`relative bg-gradient-to-br from-[#1A1A22] to-[#0E0E13] backdrop-blur-xl border rounded-[20px] p-6 lg:p-8 shadow-2xl overflow-hidden transition-all duration-700
            ${flipped ? 'border-emerald-500/50 shadow-[0_0_50px_-10px_rgba(52,211,153,0.2)]' : 'border-zinc-800/80'}`}
          >
            {/* Shimmer sweep */}
            <motion.div 
              animate={{ left: ['-100%', '200%'] }}
              transition={{ duration: 3, repeat: Infinity, ease: 'linear', repeatDelay: 2 }}
              className="absolute top-0 w-[50%] h-full bg-gradient-to-r from-transparent via-white/5 to-transparent skew-x-[-20deg] pointer-events-none"
            />

            <div className="text-center mb-6 pb-4 border-b border-zinc-800/80 relative">
              <div className="absolute bottom-0 left-0 right-0 h-[1px] bg-gradient-to-r from-transparent via-emerald-500/50 to-transparent"></div>
              <h3 className={`font-bold tracking-wider text-sm uppercase transition-colors duration-500 ${flipped ? 'text-emerald-400 drop-shadow-[0_0_8px_rgba(52,211,153,0.6)]' : 'bg-clip-text text-transparent bg-gradient-to-r from-emerald-400 via-cyan-400 to-violet-400 drop-shadow-[0_0_8px_rgba(52,211,153,0.4)]'}`}>
                Monthly Infra Bill
              </h3>
              <div className="text-[10px] text-zinc-500 mt-2 font-mono uppercase tracking-[0.1em]">
                {flipped ? 'SAME APP ON RIALO' : 'GROWING APP - TODAY\'S STACK'}
              </div>
            </div>

            <div className="min-h-[220px] space-y-3">
              <AnimatePresence>
                {SERVICES.filter(s => activeServices.includes(s.id)).map((service, i) => (
                  <motion.div 
                    key={service.id}
                    layout
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, scale: 0.95 }}
                    className={`flex items-center gap-3 text-sm transition-all duration-500 ${flipped ? 'opacity-40' : 'opacity-100'}`}
                  >
                    <div className={`w-1.5 h-1.5 rounded-full ${flipped ? 'bg-zinc-600' : 'bg-amber-400 shadow-[0_0_8px_rgba(251,191,36,0.8)]'}`} />
                    <div className="flex-1 text-zinc-400 text-xs">{service.name}</div>
                    <div className="font-mono text-zinc-200 font-semibold text-xs relative">
                      {flipped ? (
                        <div className="flex items-center gap-2 text-emerald-400">
                          <span className="line-through text-zinc-600 opacity-50">${(service.baseCost * multiplier).toLocaleString()}</span>
                          <span className="font-bold drop-shadow-[0_0_5px_rgba(52,211,153,0.8)]">GONE</span>
                        </div>
                      ) : (
                        <>${(service.baseCost * multiplier).toLocaleString()}</>
                      )}
                    </div>
                  </motion.div>
                ))}
              </AnimatePresence>
              {activeServices.length === 0 && (
                <div className="text-zinc-500 text-xs text-center py-8">No external services running.</div>
              )}
            </div>

            <div className="mt-6 pt-6 relative border-t border-zinc-800">
              <div className="absolute top-0 left-0 right-0 h-[1px] bg-gradient-to-r from-emerald-500/50 to-transparent"></div>
              <div className="flex justify-between items-end">
                <div className="font-bold text-xs text-zinc-500 uppercase tracking-widest">Total</div>
                <div className="text-right">
                  <div className={`font-bold text-4xl tracking-tight leading-none transition-colors duration-700 ${flipped ? 'text-emerald-400 drop-shadow-[0_0_15px_rgba(52,211,153,0.5)]' : 'text-transparent bg-clip-text bg-gradient-to-r from-rose-400 to-amber-400 drop-shadow-[0_0_15px_rgba(251,113,133,0.3)]'}`}>
                    ${flipped ? '0' : totalCost.toLocaleString()}
                  </div>
                  {!flipped && <div className="text-[10px] text-zinc-500 mt-1 font-mono tracking-wider">${(totalCost * 12).toLocaleString()} a year</div>}
                </div>
              </div>
            </div>

            <div className="mt-8 pt-6 border-t border-zinc-800/80 flex items-center justify-between gap-4">
              <div className="text-[11px] text-zinc-400 leading-relaxed">
                <b className="text-white block uppercase tracking-wider text-xs mb-1">Same app, on Rialo</b>
                Collapse the stack to eliminate off-chain fees entirely.
              </div>
              <button 
                onClick={() => setFlipped(!flipped)}
                className={`px-4 py-2 rounded-xl text-xs font-bold font-mono tracking-wider uppercase transition-all duration-300 shrink-0
                  ${flipped 
                    ? 'bg-gradient-to-r from-emerald-400 to-cyan-400 text-[#08120E] shadow-[0_0_20px_-5px_rgba(52,211,153,0.6)]' 
                    : 'bg-emerald-400/10 text-emerald-400 border border-emerald-500/50 hover:bg-emerald-400 hover:text-[#08120E] hover:shadow-[0_0_20px_-5px_rgba(52,211,153,0.6)]'}`}
              >
                {flipped ? 'Revert' : 'Flip Bill'}
              </button>
            </div>

          </div>
        </div>

      </div>
    </div>
  );
}
