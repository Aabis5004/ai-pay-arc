
'use client';

import { motion } from 'framer-motion';

const ROWS = [
  { name: 'Fast blocks / preconfirms', base: 'Yes', arb: 'Yes', sol: 'Yes', rialo: 'Yes', baseC: 'g', arbC: 'g', solC: 'g', rialoC: 'g' },
  { name: 'High compute efficiency', base: 'EVM', arb: 'Stylus', sol: 'High', rialo: 'RISC-V + SVM', baseC: 'y', arbC: 'g', solC: 'g', rialoC: 'g' },
  { name: 'Custom chains', base: 'Limited', arb: 'Orbit', sol: 'No', rialo: 'Full stack', baseC: 'y', arbC: 'g', solC: 'r', rialoC: 'g' },
  { name: 'Native HTTPS / live Web2 data', base: 'Oracle', arb: 'Oracle', sol: 'Oracle', rialo: 'Built-in', baseC: 'r', arbC: 'r', solC: 'r', rialoC: 'g' },
  { name: 'Native event-driven / reactive', base: 'Keepers', arb: 'Keepers', sol: 'Keepers', rialo: 'Native', baseC: 'r', arbC: 'r', solC: 'r', rialoC: 'g' },
  { name: 'Native privacy / confidential', base: 'Public', arb: 'Improving', sol: 'Limited', rialo: 'ZK + REX', baseC: 'r', arbC: 'y', solC: 'y', rialoC: 'g' },
  { name: 'AI-agent friendliness', base: 'Bolted on', arb: 'Better', sol: 'Glue', rialo: 'By design', baseC: 'r', arbC: 'y', solC: 'r', rialoC: 'g' },
];

const CARDS = [
  { name: 'Block time', lbl: 'LOWER IS BETTER', eth: '12s', sol: '0.4s', base: '2s', rialo: '0.05s', ethW: 80, solW: 20, baseW: 40, rialoW: 5 },
  { name: 'Time to finality', lbl: 'LOWER IS BETTER', eth: '12m', sol: '12.8s', base: '2s', rialo: '0.13s', ethW: 100, solW: 30, baseW: 40, rialoW: 10 },
  { name: 'Real-world TPS', lbl: 'HIGHER IS BETTER', eth: '15-30', sol: '3-4k', base: '~100', rialo: '1M+', ethW: 10, solW: 60, baseW: 20, rialoW: 100 },
  { name: 'Native real-world reach', lbl: 'EVENTS + LIVE DATA', eth: 'bots', sol: 'bots', base: 'bots', rialo: 'native', ethW: 0, solW: 0, baseW: 0, rialoW: 100 },
];

export function ComparisonTable() {
  const getColor = (c: string) => {
    if (c === 'g') return 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.8)]';
    if (c === 'y') return 'bg-amber-400 shadow-[0_0_8px_rgba(251,191,36,0.8)]';
    if (c === 'r') return 'bg-rose-500 opacity-60';
    return '';
  };

  const getTextColor = (c: string, isRialo: boolean = false) => {
    if (isRialo) return 'text-emerald-400 font-bold';
    if (c === 'r') return 'text-zinc-500';
    return 'text-zinc-400';
  };

  return (
    <div className="w-full max-w-5xl mx-auto my-16">
      
      {/* Table Grid */}
      <div className="bg-[#12131C]/60 border border-zinc-800/80 rounded-[24px] overflow-hidden mb-10 shadow-2xl backdrop-blur-lg">
        <div className="grid grid-cols-[1.5fr_1fr_1fr_1fr_1fr] border-b border-zinc-800/80">
          <div className="p-4"></div>
          <div className="p-4 text-xs font-bold text-zinc-400 flex items-center gap-2"><div className="w-4 h-4 rounded-full bg-blue-500/20 text-blue-400 flex items-center justify-center text-[10px]">-</div> Base / OP</div>
          <div className="p-4 text-xs font-bold text-zinc-400 flex items-center gap-2"><div className="w-4 h-4 rounded-full bg-cyan-500/20 text-cyan-400 flex items-center justify-center text-[10px]">^</div> Arbitrum</div>
          <div className="p-4 text-xs font-bold text-zinc-400 flex items-center gap-2"><div className="w-4 h-4 rounded-full bg-purple-500/20 text-purple-400 flex items-center justify-center text-[10px]">=</div> Solana</div>
          <div className="p-4 text-sm font-bold text-emerald-400 bg-emerald-500/5 flex items-center gap-2 border-b-2 border-emerald-500/30">
            <svg viewBox="0 0 24 24" fill="none" className="w-5 h-5 drop-shadow-[0_0_5px_rgba(52,211,153,0.6)]"><path d="M12 2L2 7l10 5 10-5-10-5z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round"/></svg>
            Rialo
          </div>
        </div>

        {ROWS.map((row, i) => (
          <div key={i} className={`grid grid-cols-[1.5fr_1fr_1fr_1fr_1fr] border-b border-zinc-800/50 hover:bg-white/[0.02] transition-colors ${i === ROWS.length -1 ? 'border-b-0' : ''}`}>
            <div className="p-4 text-sm font-medium text-zinc-300 flex items-center">{row.name}</div>
            
            <div className="p-4 flex items-center gap-2">
              <div className={`w-1.5 h-1.5 rounded-full flex-none ${getColor(row.baseC)}`} />
              <span className={`text-xs font-mono ${getTextColor(row.baseC)}`}>{row.base}</span>
            </div>
            
            <div className="p-4 flex items-center gap-2">
              <div className={`w-1.5 h-1.5 rounded-full flex-none ${getColor(row.arbC)}`} />
              <span className={`text-xs font-mono ${getTextColor(row.arbC)}`}>{row.arb}</span>
            </div>
            
            <div className="p-4 flex items-center gap-2">
              <div className={`w-1.5 h-1.5 rounded-full flex-none ${getColor(row.solC)}`} />
              <span className={`text-xs font-mono ${getTextColor(row.solC)}`}>{row.sol}</span>
            </div>
            
            <div className="p-4 flex items-center gap-2 bg-emerald-500/5">
              <span className={`text-xs font-mono ${getTextColor(row.rialoC, true)}`}>{row.rialo}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Metric Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {CARDS.map((card, i) => (
          <div key={i} className="bg-[#12131C]/60 border border-zinc-800/80 rounded-[20px] p-6 backdrop-blur shadow-xl">
            <div className="flex justify-between items-baseline mb-6">
              <h4 className="text-lg font-bold text-white">{card.name}</h4>
              <span className="text-[10px] text-zinc-500 font-mono tracking-widest">{card.lbl}</span>
            </div>
            
            <div className="space-y-4">
              {/* Ethereum */}
              <div className="grid grid-cols-[70px_1fr_50px] gap-4 items-center">
                <span className="text-xs font-mono text-zinc-400">Ethereum</span>
                <div className="h-2 bg-zinc-800/50 rounded-full overflow-hidden">
                  <motion.div initial={{ width: 0 }} whileInView={{ width: `${card.ethW}%` }} viewport={{ once: true }} transition={{ duration: 1 }} className="h-full bg-indigo-500/80 rounded-full" />
                </div>
                <span className="text-sm font-bold text-zinc-300 text-right">{card.eth}</span>
              </div>
              
              {/* Solana */}
              <div className="grid grid-cols-[70px_1fr_50px] gap-4 items-center">
                <span className="text-xs font-mono text-zinc-400">Solana</span>
                <div className="h-2 bg-zinc-800/50 rounded-full overflow-hidden">
                  <motion.div initial={{ width: 0 }} whileInView={{ width: `${card.solW}%` }} viewport={{ once: true }} transition={{ duration: 1, delay: 0.1 }} className="h-full bg-gradient-to-r from-purple-500 to-green-400 rounded-full" />
                </div>
                <span className="text-sm font-bold text-zinc-300 text-right">{card.sol}</span>
              </div>
              
              {/* Base */}
              <div className="grid grid-cols-[70px_1fr_50px] gap-4 items-center">
                <span className="text-xs font-mono text-zinc-400">Base</span>
                <div className="h-2 bg-zinc-800/50 rounded-full overflow-hidden">
                  <motion.div initial={{ width: 0 }} whileInView={{ width: `${card.baseW}%` }} viewport={{ once: true }} transition={{ duration: 1, delay: 0.2 }} className="h-full bg-blue-500 rounded-full" />
                </div>
                <span className="text-sm font-bold text-zinc-300 text-right">{card.base}</span>
              </div>
              
              {/* Rialo */}
              <div className="grid grid-cols-[70px_1fr_50px] gap-4 items-center">
                <span className="text-xs font-mono text-emerald-400">Rialo</span>
                <div className="h-2 bg-zinc-800/50 rounded-full overflow-hidden shadow-[0_0_10px_rgba(52,211,153,0.2)]">
                  <motion.div initial={{ width: 0 }} whileInView={{ width: `${card.rialoW}%` }} viewport={{ once: true }} transition={{ duration: 1, delay: 0.3 }} className="h-full bg-gradient-to-r from-emerald-400 to-cyan-400 rounded-full shadow-[0_0_10px_rgba(52,211,153,0.8)]" />
                </div>
                <span className="text-sm font-bold text-emerald-400 text-right">{card.rialo}</span>
              </div>
            </div>
          </div>
        ))}
      </div>

    </div>
  );
}
