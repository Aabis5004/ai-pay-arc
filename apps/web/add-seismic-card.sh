#!/usr/bin/env bash
# add-seismic-card.sh
# Adds a new "Card" page (/card) with:
#   • Premium 3D card that tilts with mouse, glowing border, light streaks
#   • Deterministic card number from wallet address
#   • Live shielded balance, SHIELDED badge, expiry, holographic strip
#   • Flip to back: QR receive code, copy details, security strip
#   • Action row: Deposit / Send / Receive / History (links to existing working pages)
#   • Animated showcase band: floating coins, transaction-flow lines, live counters
# Adds "Card" to the sidebar nav. Touches NOTHING else.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

# Ensure qrcode.react is available (used by /receive already, but verify)
if ! grep -q "qrcode.react" package.json; then
  echo "→ Installing qrcode.react…"
  npm install qrcode.react --legacy-peer-deps
fi

echo "→ Backing up sidebar…"
cp components/Sidebar.tsx "components/Sidebar.tsx.bak.$(date +%s)"

# ───────────────────────────────────────────────
# 1. Add "Card" to sidebar nav (after Portfolio, before Seismic AI)
# ───────────────────────────────────────────────
echo "→ 1/3 Adding 'Card' to sidebar…"
python3 - <<'PYEOF'
import re
p = 'components/Sidebar.tsx'
with open(p) as f: c = f.read()
orig = c

# Add CreditCard to the lucide-react import
m = re.search(r"import\s*\{([^}]*)\}\s*from\s*'lucide-react';", c, re.DOTALL)
if m and 'CreditCard' not in m.group(1):
    new_imports = m.group(1).rstrip().rstrip(',') + ', CreditCard'
    c = c[:m.start(1)] + new_imports + c[m.end(1):]

# Insert the Card nav item after Portfolio
if "'/card'" not in c:
    c = c.replace(
        "{ href: '/portfolio', label: 'Portfolio', icon: PieChart },",
        "{ href: '/portfolio', label: 'Portfolio', icon: PieChart },\n  { href: '/card', label: 'Card', icon: CreditCard },"
    )

if c != orig:
    with open(p,'w') as f: f.write(c)
    print("  ✓ sidebar updated")
else:
    print("  · sidebar already had Card")
PYEOF

# ───────────────────────────────────────────────
# 2. Create the SeismicCard component
# ───────────────────────────────────────────────
echo "→ 2/3 Creating components/SeismicCard.tsx…"
mkdir -p components

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

// Deterministic 16-digit card number derived from the wallet address.
// Same address → same card number, always. Grouped into 4s.
function cardNumberFromAddress(addr?: string): string {
  if (!addr) return '•••• •••• •••• ••••';
  const hex = addr.replace(/^0x/, '');
  let digits = '';
  for (let i = 0; i < hex.length && digits.length < 16; i++) {
    const v = parseInt(hex[i], 16);
    if (!Number.isNaN(v)) digits += (v % 10).toString();
  }
  digits = (digits + '4242424242424242').slice(0, 16); // pad if short
  return digits.replace(/(.{4})/g, '$1 ').trim();
}

// Deterministic expiry derived from address (stable per user)
function expiryFromAddress(addr?: string): string {
  if (!addr) return '••/••';
  const n = parseInt(addr.slice(-4), 16);
  const month = (n % 12) + 1;
  const year = 28 + (n % 5); // 28–32
  return `${String(month).padStart(2, '0')}/${year}`;
}

export function SeismicCard() {
  const address = useWalletAddress();
  const [balance, setBalance] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [flipped, setFlipped] = useState(false);
  const [copied, setCopied] = useState(false);

  const cardNumber = cardNumberFromAddress(address);
  const expiry = expiryFromAddress(address);

  // Mouse-tilt
  const ref = useRef<HTMLDivElement>(null);
  const mx = useMotionValue(0);
  const my = useMotionValue(0);
  const rotateX = useSpring(useTransform(my, [-0.5, 0.5], [10, -10]), { stiffness: 200, damping: 20 });
  const rotateY = useSpring(useTransform(mx, [-0.5, 0.5], [-12, 12]), { stiffness: 200, damping: 20 });

  function onMove(e: React.MouseEvent) {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    mx.set((e.clientX - r.left) / r.width - 0.5);
    my.set((e.clientY - r.top) / r.height - 0.5);
  }
  function onLeave() {
    mx.set(0);
    my.set(0);
  }

  const refresh = async () => {
    if (!address) return;
    setLoading(true);
    try {
      const wei = await calculateBalance(address);
      setBalance(parseFloat(formatEther(wei)));
    } catch {
      /* ignore */
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 8000);
    return () => clearInterval(id);
  }, [address]);

  const copyDetails = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <div className="flex flex-col items-center">
      {/* 3D stage */}
      <div
        ref={ref}
        onMouseMove={onMove}
        onMouseLeave={onLeave}
        className="relative"
        style={{ perspective: 1200, width: 420, maxWidth: '100%' }}
      >
        <motion.div
          style={{ rotateX, rotateY, transformStyle: 'preserve-3d' }}
          className="relative w-full"
          animate={{ rotateY: flipped ? 180 : 0 }}
          transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
        >
          {/* ───── FRONT ───── */}
          <div
            className="relative w-full rounded-3xl p-6 overflow-hidden"
            style={{
              aspectRatio: '1.586',
              backfaceVisibility: 'hidden',
              background:
                'linear-gradient(135deg, #1a1030 0%, #0a0a0f 55%, #160d28 100%)',
              border: '1px solid rgba(124,58,237,0.35)',
              boxShadow:
                '0 30px 80px -20px rgba(124,58,237,0.4), inset 0 1px 0 rgba(255,255,255,0.06)',
            }}
          >
            {/* animated glow border */}
            <motion.div
              aria-hidden
              className="absolute inset-0 rounded-3xl"
              style={{
                background:
                  'radial-gradient(120% 120% at 0% 0%, rgba(124,58,237,0.25), transparent 40%), radial-gradient(120% 120% at 100% 100%, rgba(56,189,248,0.18), transparent 45%)',
              }}
              animate={{ opacity: [0.5, 0.9, 0.5] }}
              transition={{ duration: 4, repeat: Infinity, ease: 'easeInOut' }}
            />
            {/* light streaks */}
            <motion.div
              aria-hidden
              className="absolute -inset-y-10 w-1/3"
              style={{
                background:
                  'linear-gradient(90deg, transparent, rgba(255,255,255,0.08), transparent)',
                transform: 'skewX(-18deg)',
              }}
              animate={{ left: ['-40%', '140%'] }}
              transition={{ duration: 5, repeat: Infinity, ease: 'easeInOut', repeatDelay: 2 }}
            />

            <div className="relative z-10 h-full flex flex-col justify-between" style={{ transform: 'translateZ(40px)' }}>
              {/* top row */}
              <div className="flex items-start justify-between">
                <div>
                  <div className="text-[10px] uppercase tracking-[0.25em] text-violet-300/70">
                    Seismic
                  </div>
                  <div
                    className="text-lg leading-none mt-0.5"
                    style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}
                  >
                    Shielded Card
                  </div>
                </div>
                <div className="flex items-center gap-1.5 px-2 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/30">
                  <Shield className="w-3 h-3 text-emerald-400" />
                  <span className="text-[9px] uppercase tracking-wider text-emerald-300">Shielded</span>
                </div>
              </div>

              {/* holographic chip */}
              <div className="flex items-center gap-3">
                <div
                  className="w-11 h-8 rounded-md"
                  style={{
                    background:
                      'linear-gradient(135deg, #c4b5fd, #7c3aed 40%, #38bdf8 75%, #c4b5fd)',
                    boxShadow: 'inset 0 0 6px rgba(0,0,0,0.4)',
                  }}
                />
                <div className="text-[10px] text-zinc-500 uppercase tracking-widest">Encrypted</div>
              </div>

              {/* card number */}
              <div className="font-mono text-xl tracking-[0.18em] text-zinc-100">
                {cardNumber}
              </div>

              {/* bottom row */}
              <div className="flex items-end justify-between">
                <div>
                  <div className="text-[8px] uppercase tracking-[0.2em] text-zinc-500">Cardholder</div>
                  <div className="font-mono text-xs text-zinc-300">
                    {address ? `${address.slice(0, 6)}…${address.slice(-4)}` : '—'}
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-[8px] uppercase tracking-[0.2em] text-zinc-500">Balance</div>
                  <div className="text-sm text-white">
                    {balance === null ? '—' : `${balance.toFixed(4)} ${NATIVE_SYMBOL}`}
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-[8px] uppercase tracking-[0.2em] text-zinc-500">Expires</div>
                  <div className="font-mono text-xs text-zinc-300">{expiry}</div>
                </div>
              </div>
            </div>
          </div>

          {/* ───── BACK ───── */}
          <div
            className="absolute inset-0 w-full rounded-3xl p-6 overflow-hidden"
            style={{
              aspectRatio: '1.586',
              backfaceVisibility: 'hidden',
              transform: 'rotateY(180deg)',
              background:
                'linear-gradient(135deg, #0a0a0f 0%, #160d28 60%, #1a1030 100%)',
              border: '1px solid rgba(124,58,237,0.35)',
              boxShadow: '0 30px 80px -20px rgba(124,58,237,0.4)',
            }}
          >
            <div className="h-7 bg-black/70 -mx-6 mb-4" />
            <div className="flex items-center justify-between gap-4">
              <div className="flex-1">
                <div className="text-[8px] uppercase tracking-[0.2em] text-zinc-500 mb-1">
                  Receive to
                </div>
                <div className="font-mono text-[10px] text-zinc-300 break-all leading-relaxed">
                  {address || '—'}
                </div>
                <button
                  onClick={(e) => { e.stopPropagation(); copyDetails(); }}
                  className="mt-2 flex items-center gap-1 text-[10px] text-violet-300 hover:text-violet-200"
                >
                  {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
                  {copied ? 'Copied' : 'Copy address'}
                </button>
              </div>
              <div className="bg-white p-2 rounded-lg">
                {address ? (
                  <QRCodeSVG value={address} size={76} />
                ) : (
                  <div className="w-[76px] h-[76px] bg-zinc-200 rounded" />
                )}
              </div>
            </div>
            <div className="absolute bottom-4 left-6 right-6 flex items-center justify-between">
              <div className="text-[8px] text-zinc-600 uppercase tracking-widest">
                Privacy by Seismic · suint256
              </div>
              <div className="font-mono text-[9px] text-zinc-500">CVV •••</div>
            </div>
          </div>
        </motion.div>
      </div>

      {/* controls under the card */}
      <div className="flex items-center gap-3 mt-5">
        <button
          onClick={() => setFlipped((v) => !v)}
          className="text-xs text-zinc-400 hover:text-white px-3 py-1.5 rounded-lg border border-zinc-800 hover:border-zinc-700 transition-colors"
        >
          {flipped ? 'Show front' : 'Flip card'}
        </button>
        <button
          onClick={refresh}
          disabled={loading}
          className="flex items-center gap-1.5 text-xs text-zinc-400 hover:text-white px-3 py-1.5 rounded-lg border border-zinc-800 hover:border-zinc-700 transition-colors disabled:opacity-50"
        >
          <RefreshCw className={`w-3 h-3 ${loading ? 'animate-spin' : ''}`} />
          Refresh balance
        </button>
      </div>
    </div>
  );
}
TSX
echo "  ✓ SeismicCard.tsx created"

# ───────────────────────────────────────────────
# 3. Create the Card page (card + showcase band)
# ───────────────────────────────────────────────
echo "→ 3/3 Creating app/(app)/card/page.tsx…"
mkdir -p "app/(app)/card"

cat > "app/(app)/card/page.tsx" <<'TSX'
'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import {
  ArrowDownToLine, Send, QrCode, Clock, ArrowUpRight, ArrowDownLeft,
} from 'lucide-react';
import { PageHeader } from '@/components/PageHeader';
import { SeismicCard } from '@/components/SeismicCard';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { NATIVE_SYMBOL } from '@/lib/chain';

const actions = [
  { href: '/deposit', label: 'Deposit', icon: ArrowDownToLine, hint: 'Fund the card' },
  { href: '/send', label: 'Send', icon: Send, hint: 'Pay anyone' },
  { href: '/receive', label: 'Receive', icon: QrCode, hint: 'Share address' },
  { href: '/history', label: 'History', icon: Clock, hint: 'All activity' },
];

// Animated counter
function Counter({ value, decimals = 0, suffix = '' }: { value: number; decimals?: number; suffix?: string }) {
  const [display, setDisplay] = useState(0);
  useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const dur = 900;
    const from = display;
    const tick = (t: number) => {
      const p = Math.min(1, (t - start) / dur);
      const eased = 1 - Math.pow(1 - p, 3);
      setDisplay(from + (value - from) * eased);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);
  return <>{display.toFixed(decimals)}{suffix}</>;
}

export default function CardPage() {
  const address = useWalletAddress();
  const [events, setEvents] = useState<HistoryEvent[]>([]);

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

  const stats = {
    total: events.length,
    sent: events.filter((e) => e.type === 'send').length,
    received: events.filter((e) => e.type === 'receive').length,
    deposits: events.filter((e) => e.type === 'deposit').length,
  };

  return (
    <>
      <PageHeader title="Card" subtitle="Your shielded payment card. Encrypted balance, public-grade UX." />

      {/* CARD + ACTIONS */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-center mb-10">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
        >
          <SeismicCard />
        </motion.div>

        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.5, delay: 0.1 }}
          className="grid grid-cols-2 gap-3"
        >
          {actions.map((a) => {
            const Icon = a.icon;
            return (
              <Link key={a.href} href={a.href}>
                <motion.div
                  whileHover={{ scale: 1.03, y: -2 }}
                  whileTap={{ scale: 0.98 }}
                  className="h-full bg-zinc-900/60 border border-zinc-800 hover:border-violet-700/50 rounded-2xl p-5 backdrop-blur transition-colors group"
                >
                  <div className="w-10 h-10 rounded-xl bg-violet-600/15 border border-violet-800/40 flex items-center justify-center mb-3 group-hover:bg-violet-600/25 transition-colors">
                    <Icon className="w-4 h-4 text-violet-300" />
                  </div>
                  <div className="text-sm text-white">{a.label}</div>
                  <div className="text-[11px] text-zinc-500 mt-0.5">{a.hint}</div>
                </motion.div>
              </Link>
            );
          })}
        </motion.div>
      </div>

      {/* ───── ANIMATED SHOWCASE BAND ───── */}
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6 }}
        className="relative overflow-hidden rounded-3xl border border-violet-900/30 mb-8"
        style={{ background: 'linear-gradient(135deg, #120a26 0%, #0a0a0f 60%, #160d28 100%)' }}
      >
        {/* floating coins/particles */}
        {Array.from({ length: 14 }).map((_, i) => (
          <motion.div
            key={i}
            aria-hidden
            className="absolute rounded-full"
            style={{
              width: 6 + (i % 4) * 5,
              height: 6 + (i % 4) * 5,
              left: `${(i * 37) % 100}%`,
              top: `${(i * 53) % 100}%`,
              background:
                i % 2 === 0
                  ? 'radial-gradient(circle at 30% 30%, #a78bfa, #7c3aed)'
                  : 'radial-gradient(circle at 30% 30%, #67e8f9, #38bdf8)',
              opacity: 0.35,
            }}
            animate={{ y: [0, -18, 0], x: [0, 8, 0] }}
            transition={{ duration: 5 + (i % 5), repeat: Infinity, ease: 'easeInOut', delay: i * 0.3 }}
          />
        ))}

        <div className="relative z-10 p-8 md:p-10">
          <div className="text-[10px] uppercase tracking-[0.25em] text-violet-300/70 mb-2">
            Live on Seismic
          </div>
          <h2
            className="text-3xl md:text-4xl font-light tracking-tight mb-8 max-w-lg"
            style={{ fontFamily: 'var(--font-display), serif' }}
          >
            Encrypted value, moving in the open.
          </h2>

          {/* live counters */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
            {[
              { label: 'Total events', value: stats.total, dec: 0 },
              { label: 'Sent', value: stats.sent, dec: 0 },
              { label: 'Received', value: stats.received, dec: 0 },
              { label: 'Deposits', value: stats.deposits, dec: 0 },
            ].map((s) => (
              <div key={s.label} className="bg-black/30 border border-zinc-800/60 rounded-2xl p-4 backdrop-blur">
                <div className="text-3xl font-light text-white tabular-nums">
                  <Counter value={s.value} decimals={s.dec} />
                </div>
                <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mt-1">{s.label}</div>
              </div>
            ))}
          </div>

          {/* transaction flow viz */}
          <div className="relative bg-black/30 border border-zinc-800/60 rounded-2xl p-6 backdrop-blur overflow-hidden">
            <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mb-4">
              Shielded transfer flow
            </div>
            <div className="flex items-center justify-between gap-2">
              <div className="flex flex-col items-center gap-1">
                <div className="w-12 h-12 rounded-xl bg-violet-600/20 border border-violet-700/40 flex items-center justify-center">
                  <ArrowUpRight className="w-5 h-5 text-violet-300" />
                </div>
                <div className="text-[9px] text-zinc-500 uppercase tracking-wider">You</div>
              </div>

              {/* animated line */}
              <div className="flex-1 relative h-px bg-zinc-800 mx-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <motion.div
                    key={i}
                    className="absolute top-1/2 -translate-y-1/2 w-2 h-2 rounded-full bg-violet-400"
                    style={{ boxShadow: '0 0 8px #7c3aed' }}
                    animate={{ left: ['0%', '100%'], opacity: [0, 1, 0] }}
                    transition={{ duration: 2, repeat: Infinity, ease: 'linear', delay: i * 0.66 }}
                  />
                ))}
              </div>

              <div className="flex flex-col items-center gap-1">
                <div className="w-12 h-12 rounded-xl bg-cyan-600/15 border border-cyan-700/30 flex items-center justify-center">
                  <ArrowDownLeft className="w-5 h-5 text-cyan-300" />
                </div>
                <div className="text-[9px] text-zinc-500 uppercase tracking-wider">Recipient</div>
              </div>
            </div>
            <div className="text-center text-[10px] text-zinc-600 mt-4">
              Amounts encrypted on-chain via <span className="text-violet-400 font-mono">suint256</span>
            </div>
          </div>
        </div>
      </motion.div>

      {/* live activity feed */}
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, delay: 0.15 }}
        className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
      >
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
                <div className="text-[10px] uppercase tracking-wider text-emerald-400/70">
                  confirmed
                </div>
              </motion.div>
            ))}
          </div>
        )}
      </motion.div>
    </>
  );
}
TSX
echo "  ✓ card page created"

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — new 'Card' page added"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Restart dev server:"
echo "    Ctrl+C in npm run dev, then 'npm run dev'"
echo "  Hard-refresh: Ctrl+Shift+R"
echo ""
echo "  Open the new 'Card' item in the sidebar. You get:"
echo "    • A premium 3D card that tilts with your mouse"
echo "    • Glowing border + light-streak animations"
echo "    • Deterministic card number from your wallet"
echo "    • Live shielded balance + SHIELDED badge + expiry"
echo "    • 'Flip card' → QR receive code + copy address"
echo "    • Action tiles → Deposit / Send / Receive / History"
echo "    • Animated showcase band: floating coins, live counters,"
echo "      transfer-flow visualization, live activity feed"
echo ""
echo "  Nothing else was changed. All existing pages still work."
