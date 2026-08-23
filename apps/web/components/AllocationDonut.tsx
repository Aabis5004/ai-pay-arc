'use client';

import { motion } from 'framer-motion';

type Slice = { label: string; value: number; color: string };

export function AllocationDonut({ slices, size = 200 }: { slices: Slice[]; size?: number }) {
  const total = slices.reduce((s, x) => s + x.value, 0) || 1;
  const r = size / 2 - 8;
  const cx = size / 2;
  const cy = size / 2;
  const circ = 2 * Math.PI * r;

  let acc = 0;
  return (
    <div className="flex flex-col items-center">
      <svg width={size} height={size} className="-rotate-90">
        <circle
          cx={cx}
          cy={cy}
          r={r}
          fill="none"
          stroke="#1f1f27"
          strokeWidth={16}
        />
        {slices.map((s, i) => {
          const frac = s.value / total;
          const offset = (acc / total) * circ;
          acc += s.value;
          return (
            <motion.circle
              key={s.label}
              initial={{ strokeDasharray: `0 ${circ}` }}
              animate={{ strokeDasharray: `${frac * circ} ${circ - frac * circ}` }}
              transition={{ duration: 1.1, delay: 0.1 * i, ease: [0.16, 1, 0.3, 1] }}
              cx={cx}
              cy={cy}
              r={r}
              fill="none"
              stroke={s.color}
              strokeWidth={16}
              strokeDashoffset={-offset}
              strokeLinecap="butt"
            />
          );
        })}
      </svg>
      <div className="mt-4 space-y-1.5">
        {slices.map((s) => (
          <div key={s.label} className="flex items-center gap-2 text-xs">
            <div
              className="w-2.5 h-2.5 rounded-full"
              style={{ backgroundColor: s.color }}
            />
            <span className="text-zinc-300">{s.label}</span>
            <span className="text-zinc-500">
              {((s.value / total) * 100).toFixed(1)}%
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
