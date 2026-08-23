#!/usr/bin/env bash
# upgrade-card-premium.sh
# Rebuilds the Card page in a premium Plasma-inspired layout, but in Seismic's
# black + violet identity (not silver). Big bold stats (Balance / Sent / Received)
# sit above a large hero card on a reflective dark stage with a floating reflection.
#
# Replaces components/SeismicCard.tsx and app/(app)/card/page.tsx.
# Touches nothing else.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

echo "→ Backing up existing card files…"
cp components/SeismicCard.tsx "components/SeismicCard.tsx.bak.$(date +%s)" 2>/dev/null || true
cp "app/(app)/card/page.tsx" "app/(app)/card/page.tsx.bak.$(date +%s)" 2>/dev/null || true

# ───────────────────────────────────────────────
# 1. Premium hero card component (bigger, thicker, with reflection)
# ───────────────────────────────────────────────
echo "→ 1/2 Writing premium SeismicCard.tsx…"

cat > components/SeismicCard.tsx <<'TSX'
'use client';

import { useRef, useState, useEffect } from 'react';
import { motion, useMotionValue, useSpring, useTransform } from 'framer-motion';
import { QRCodeSVG } from 'qrcode.react';
import { Shield, Copy, Check, RefreshCw } from 'lucide-react';
import { formatEther } from 'viem';
import { calculateBalance } from '@/lib/balance';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { NATIVE_SYMBOL } from '@/lib/chain';

function cardNumberFromAddress(addr?: string): string {
  if (!addr) return '•••• •••• •••• ••••';
  const hex = addr.replace(/^0x/, '');
  let digits = '';
  for (let i = 0; i < hex.length && digits.length < 16; i++) {
    const v = parseInt(hex[i], 16);
    if (!Number.isNaN(v)) digits += (v % 10).toString();
  }
  digits = (digits + '4242424242424242').slice(0, 16);
  return digits.replace(/(.{4})/g, '$1 ').trim();
}

function expiryFromAddress(addr?: string): string {
  if (!addr) return '••/••';
  const n = parseInt(addr.slice(-4), 16);
  const month = (n % 12) + 1;
  const year = 28 + (n % 5);
  return `${String(month).padStart(2, '0')}/${year}`;
}

// The card face, reused for the main card and its mirrored reflection.
function CardFace({
  address, balance, cardNumber, expiry, dimmed = false,
}: {
  address?: string; balance: number | null; cardNumber: string; expiry: string; dimmed?: boolean;
}) {
  return (
    <div
      className="relative w-full rounded-[1.4rem] p-7 overflow-hidden"
      style={{
        aspectRatio: '1.586',
        background:
          'linear-gradient(135deg, #241248 0%, #120a26 45%, #0a0a0f 75%, #1b0f33 100%)',
        border: '1px solid rgba(139,92,246,0.45)',
        boxShadow: dimmed
          ? 'none'
          : '0 40px 90px -25px rgba(124,58,237,0.55), inset 0 1px 0 rgba(255,255,255,0.08), inset 0 0 60px rgba(124,58,237,0.08)',
      }}
    >
      {/* deep violet glow corners */}
      <div
        aria-hidden
        className="absolute inset-0"
        style={{
          background:
            'radial-gradient(130% 130% at 0% 0%, rgba(139,92,246,0.35), transparent 42%), radial-gradient(130% 130% at 100% 100%, rgba(99,102,241,0.25), transparent 48%)',
        }}
      />
      {/* sweeping shine */}
      {!dimmed && (
        <motion.div
          aria-hidden
          className="absolute -inset-y-16 w-1/3"
          style={{
            background: 'linear-gradient(90deg, transparent, rgba(196,181,253,0.14), transparent)',
            transform: 'skewX(-18deg)',
          }}
          animate={{ left: ['-40%', '150%'] }}
          transition={{ duration: 5.5, repeat: Infinity, ease: 'easeInOut', repeatDelay: 2.5 }}
        />
      )}

      <div className="relative z-10 h-full flex flex-col justify-between" style={{ transform: 'translateZ(50px)' }}>
        <div className="flex items-start justify-between">
          <div>
            <div className="text-[10px] uppercase tracking-[0.3em] text-violet-300/80">Seismic</div>
            <div
              className="text-2xl leading-none mt-1"
              style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}
            >
              Shielded
            </div>
          </div>
          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/30">
            <Shield className="w-3 h-3 text-emerald-400" />
            <span className="text-[9px] uppercase tracking-wider text-emerald-300">Private</span>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <div
            className="w-12 h-9 rounded-md"
            style={{
              background: 'linear-gradient(135deg, #ddd6fe, #7c3aed 40%, #6366f1 75%, #c4b5fd)',
              boxShadow: 'inset 0 0 8px rgba(0,0,0,0.5)',
            }}
          />
          <div className="text-[10px] text-violet-300/50 uppercase tracking-[0.2em]">TEE encrypted</div>
        </div>

        <div className="font-mono text-2xl tracking-[0.2em] text-zinc-50">{cardNumber}</div>

        <div className="flex items-end justify-between">
          <div>
            <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40">Cardholder</div>
            <div className="font-mono text-xs text-zinc-300">
              {address ? `${address.slice(0, 6)}…${address.slice(-4)}` : '—'}
            </div>
          </div>
          <div className="text-right">
            <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40">Balance</div>
            <div className="text-base text-white font-light">
              {balance === null ? '—' : `${balance.toFixed(4)} ${NATIVE_SYMBOL}`}
            </div>
          </div>
          <div className="text-right">
            <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40">Expires</div>
            <div className="font-mono text-xs text-zinc-300">{expiry}</div>
          </div>
        </div>
      </div>
    </div>
  );
}

export function SeismicCard({ onBalance }: { onBalance?: (n: number | null) => void }) {
  const address = useWalletAddress();
  const [balance, setBalance] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [flipped, setFlipped] = useState(false);
  const [copied, setCopied] = useState(false);

  const cardNumber = cardNumberFromAddress(address);
  const expiry = expiryFromAddress(address);

  const ref = useRef<HTMLDivElement>(null);
  const mx = useMotionValue(0);
  const my = useMotionValue(0);
  const rotateX = useSpring(useTransform(my, [-0.5, 0.5], [9, -9]), { stiffness: 200, damping: 20 });
  const rotateY = useSpring(useTransform(mx, [-0.5, 0.5], [-12, 12]), { stiffness: 200, damping: 20 });

  function onMove(e: React.MouseEvent) {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    mx.set((e.clientX - r.left) / r.width - 0.5);
    my.set((e.clientY - r.top) / r.height - 0.5);
  }
  function onLeave() { mx.set(0); my.set(0); }

  const refresh = async () => {
    if (!address) return;
    setLoading(true);
    try {
      const wei = await calculateBalance(address);
      const v = parseFloat(formatEther(wei));
      setBalance(v);
      onBalance?.(v);
    } catch { /* ignore */ } finally { setLoading(false); }
  };

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 8000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address]);

  const copyDetails = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <div className="flex flex-col items-center w-full">
      {/* reflective stage */}
      <div
        ref={ref}
        onMouseMove={onMove}
        onMouseLeave={onLeave}
        className="relative w-full"
        style={{ perspective: 1400, maxWidth: 540 }}
      >
        {/* main card */}
        <motion.div
          style={{ rotateX, rotateY, transformStyle: 'preserve-3d' }}
          animate={{ rotateY: flipped ? 180 : 0 }}
          transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
          className="relative w-full"
        >
          <div style={{ backfaceVisibility: 'hidden' }}>
            <CardFace address={address} balance={balance} cardNumber={cardNumber} expiry={expiry} />
          </div>
          {/* back */}
          <div
            className="absolute inset-0 w-full rounded-[1.4rem] p-7 overflow-hidden"
            style={{
              aspectRatio: '1.586',
              backfaceVisibility: 'hidden',
              transform: 'rotateY(180deg)',
              background: 'linear-gradient(135deg, #0a0a0f 0%, #160d28 60%, #241248 100%)',
              border: '1px solid rgba(139,92,246,0.45)',
              boxShadow: '0 40px 90px -25px rgba(124,58,237,0.55)',
            }}
          >
            <div className="h-8 bg-black/70 -mx-7 mb-5" />
            <div className="flex items-center justify-between gap-4">
              <div className="flex-1">
                <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40 mb-1">Receive to</div>
                <div className="font-mono text-[10px] text-zinc-300 break-all leading-relaxed">{address || '—'}</div>
                <button
                  onClick={(e) => { e.stopPropagation(); copyDetails(); }}
                  className="mt-2 flex items-center gap-1 text-[10px] text-violet-300 hover:text-violet-200"
                >
                  {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
                  {copied ? 'Copied' : 'Copy address'}
                </button>
              </div>
              <div className="bg-white p-2 rounded-lg">
                {address ? <QRCodeSVG value={address} size={84} /> : <div className="w-[84px] h-[84px] bg-zinc-200 rounded" />}
              </div>
            </div>
            <div className="absolute bottom-5 left-7 right-7 flex items-center justify-between">
              <div className="text-[8px] text-violet-300/40 uppercase tracking-widest">Privacy by Seismic · suint256</div>
              <div className="font-mono text-[9px] text-zinc-500">CVV •••</div>
            </div>
          </div>
        </motion.div>

        {/* floating reflection underneath */}
        <div
          aria-hidden
          className="w-full mt-3 pointer-events-none select-none"
          style={{
            transform: 'rotateX(180deg)',
            maskImage: 'linear-gradient(to bottom, rgba(0,0,0,0.4), transparent 55%)',
            WebkitMaskImage: 'linear-gradient(to bottom, rgba(0,0,0,0.4), transparent 55%)',
            opacity: 0.5,
            filter: 'blur(1px)',
          }}
        >
          <CardFace address={address} balance={balance} cardNumber={cardNumber} expiry={expiry} dimmed />
        </div>
      </div>

      <div className="flex items-center gap-3 mt-1">
        <button
          onClick={() => setFlipped((v) => !v)}
          className="text-xs text-zinc-400 hover:text-white px-3 py-1.5 rounded-lg border border-zinc-800 hover:border-violet-700/50 transition-colors"
        >
          {flipped ? 'Show front' : 'Flip card'}
        </button>
        <button
          onClick={refresh}
          disabled={loading}
          className="flex items-center gap-1.5 text-xs text-zinc-400 hover:text-white px-3 py-1.5 rounded-lg border border-zinc-800 hover:border-violet-700/50 transition-colors disabled:opacity-50"
        >
          <RefreshCw className={`w-3 h-3 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>
    </div>
  );
}
TSX
echo "  ✓ SeismicCard.tsx (premium hero + reflection)"

# ───────────────────────────────────────────────
# 2. Card page — Plasma-style big stats on top, hero card center
# ───────────────────────────────────────────────
echo "→ 2/2 Writing premium card page…"

cat > "app/(app)/card/page.tsx" <<'TSX'
'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import {
  ArrowDownToLine, Send, QrCode, Clock, ArrowUpRight, ArrowDownLeft,
} from 'lucide-react';
import { SeismicCard } from '@/components/SeismicCard';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { NATIVE_SYMBOL } from '@/lib/chain';

function Counter({ value, decimals = 0 }: { value: number; decimals?: number }) {
  const [d, setD] = useState(0);
  useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const from = d;
    const tick = (t: number) => {
      const p = Math.min(1, (t - start) / 900);
      const eased = 1 - Math.pow(1 - p, 3);
      setD(from + (value - from) * eased);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);
  return <>{d.toFixed(decimals)}</>;
}

const actions = [
  { href: '/deposit', label: 'Deposit', icon: ArrowDownToLine },
  { href: '/send', label: 'Send', icon: Send },
  { href: '/receive', label: 'Receive', icon: QrCode },
  { href: '/history', label: 'History', icon: Clock },
];

export default function CardPage() {
  const address = useWalletAddress();
  const [events, setEvents] = useState<HistoryEvent[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!address) return;
      try {
        const evts = await fetchHistory(address);
        if (!cancelled) setEvents(evts);
      } catch { /* ignore */ }
    }
    load();
    const id = setInterval(load, 8000);
    return () => { cancelled = true; clearInterval(id); };
  }, [address]);

  const sent = events.filter((e) => e.type === 'send').length;
  const received = events.filter((e) => e.type === 'receive').length;

  return (
    <div className="relative">
      {/* ambient background glow */}
      <div
        aria-hidden
        className="absolute inset-0 -z-10"
        style={{
          background:
            'radial-gradient(60% 50% at 50% 0%, rgba(124,58,237,0.12), transparent 70%)',
        }}
      />

      {/* HERO: big stats Plasma-style */}
      <div className="text-center pt-4 pb-2">
        <div className="text-[11px] uppercase tracking-[0.3em] text-violet-300/70 mb-2">
          Seismic Shielded Card
        </div>
        <h1
          className="text-3xl md:text-4xl font-light tracking-tight mb-10"
          style={{ fontFamily: 'var(--font-display), serif' }}
        >
          Your money, encrypted on-chain.
        </h1>
      </div>

      {/* big bold stat row */}
      <div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums">
            {balance === null ? '—' : <Counter value={balance} decimals={2} />}
          </div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">
            Balance ({NATIVE_SYMBOL})
          </div>
        </div>
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums">
            <Counter value={sent} />
          </div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Sent</div>
        </div>
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums">
            <Counter value={received} />
          </div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Received</div>
        </div>
      </div>

      {/* HERO CARD on reflective stage */}
      <motion.div
        initial={{ opacity: 0, y: 30, rotateX: 8 }}
        animate={{ opacity: 1, y: 0, rotateX: 0 }}
        transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
        className="flex justify-center mb-14"
      >
        <SeismicCard onBalance={setBalance} />
      </motion.div>

      {/* action row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 max-w-3xl mx-auto mb-10">
        {actions.map((a) => {
          const Icon = a.icon;
          return (
            <Link key={a.href} href={a.href}>
              <motion.div
                whileHover={{ scale: 1.04, y: -3 }}
                whileTap={{ scale: 0.98 }}
                className="bg-zinc-900/60 border border-zinc-800 hover:border-violet-700/50 rounded-2xl p-5 backdrop-blur transition-colors flex flex-col items-center gap-2 group"
              >
                <div className="w-11 h-11 rounded-xl bg-violet-600/15 border border-violet-800/40 flex items-center justify-center group-hover:bg-violet-600/25 transition-colors">
                  <Icon className="w-4 h-4 text-violet-300" />
                </div>
                <div className="text-sm text-white">{a.label}</div>
              </motion.div>
            </Link>
          );
        })}
      </div>

      {/* live activity feed */}
      <div className="max-w-3xl mx-auto bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur">
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">Recent activity</div>
        {events.length === 0 ? (
          <div className="text-sm text-zinc-500 py-6 text-center">
            No activity yet. Deposit to your card to get started.
          </div>
        ) : (
          <div className="space-y-2">
            {events.slice(0, 6).map((e, i) => (
              <motion.div
                key={`${e.hash}-${i}`}
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: i * 0.05 }}
                className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-zinc-800/40 transition-colors"
              >
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-zinc-800/60 flex items-center justify-center">
                    {e.type === 'deposit' && <ArrowDownToLine className="w-3.5 h-3.5 text-emerald-400" />}
                    {e.type === 'send' && <ArrowUpRight className="w-3.5 h-3.5 text-red-400" />}
                    {e.type === 'receive' && <ArrowDownLeft className="w-3.5 h-3.5 text-violet-400" />}
                    {e.type === 'withdraw' && <ArrowUpRight className="w-3.5 h-3.5 text-amber-400" />}
                  </div>
                  <div>
                    <div className="text-sm text-zinc-200 capitalize">{e.type}</div>
                    <div className="text-[10px] font-mono text-zinc-600">
                      {e.hash ? `${e.hash.slice(0, 10)}…` : ''}
                    </div>
                  </div>
                </div>
                <div className="text-[10px] uppercase tracking-wider text-emerald-400/70">confirmed</div>
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
TSX
echo "  ✓ card page (Plasma-style premium layout)"

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — premium card page"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Ctrl+C npm run dev, then 'npm run dev', hard-refresh."
echo ""
echo "  Now the Card page has:"
echo "    • Big bold stats up top (Balance / Sent / Received),"
echo "      Plasma-style, counting up"
echo "    • A large premium black+violet hero card on a reflective"
echo "      stage, with a floating mirror reflection underneath"
echo "    • Mouse tilt, sweeping shine, deep violet glow"
echo "    • Flip to QR back, action tiles, live activity feed"
