'use client';

import { useRef, useState, useEffect } from 'react';
import { motion, useMotionValue, useSpring, useTransform } from 'framer-motion';
import { QRCodeSVG } from 'qrcode.react';
import { Shield, Copy, Check, RefreshCw, RotateCw, Send, ArrowDownToLine, QrCode } from 'lucide-react';
import { formatEther, formatUnits } from 'viem';
import { calculateBalances } from '@/lib/balance';
import { useWalletAddress } from '@/lib/useWalletAddress';
import type { CardAction } from './CardActionModal';

export function cardNumberFromAddress(addr?: string): string {
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
  return `${String((n % 12) + 1).padStart(2, '0')}/${28 + (n % 5)}`;
}

export function ArcCard({
  onBalance, onAction, refreshKey = 0,
}: {
  onBalance?: (n: number | null) => void;
  onAction?: (a: CardAction) => void;
  refreshKey?: number;
}) {
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
  const rotateYTilt = useSpring(useTransform(mx, [-0.5, 0.5], [-10, 10]), { stiffness: 200, damping: 20 });

  function onMove(e: React.MouseEvent) {
    if (flipped) return;
    const el = ref.current; if (!el) return;
    const r = el.getBoundingClientRect();
    mx.set((e.clientX - r.left) / r.width - 0.5);
    my.set((e.clientY - r.top) / r.height - 0.5);
  }
  function onLeave() { mx.set(0); my.set(0); }

  const refresh = async () => {
    if (!address) return;
    setLoading(true);
    try {
      const bals = await calculateBalances(address);
      const v = parseFloat(formatUnits(bals.usdc, 6));
      setBalance(v); onBalance?.(v);
    } catch { /* ignore */ } finally { setLoading(false); }
  };

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 8000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address, refreshKey]);

  const copyAddr = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true); setTimeout(() => setCopied(false), 1500);
  };

  const cardGradient = 'linear-gradient(135deg, #09090b 0%, #18181b 100%)';
  const cardBorder = 'rgba(255,255,255,0.08)';

  return (
    <div className="flex flex-col items-center w-full">
      <div className="relative w-full" style={{ perspective: 1400, maxWidth: 420 }}>
        <motion.div
          animate={{ rotateY: flipped ? 180 : 0 }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
          className="relative w-full"
          style={{ transformStyle: 'preserve-3d' }}
        >
          {/* FRONT */}
          <div
            className="relative w-full rounded-[16px] p-6 overflow-hidden transition-all duration-700"
            style={{
              aspectRatio: '1.586', backfaceVisibility: 'hidden',
              background: cardGradient,
              border: `1px solid ${cardBorder}`,
              boxShadow: `0 10px 40px -10px rgba(0,0,0,0.5)`,
            }}
          >
            {/* Subtle metallic chip effect */}
            <div className="absolute top-16 left-6 w-12 h-9 rounded-md border border-zinc-700" style={{ 
              background: 'linear-gradient(135deg, #3f3f46, #71717a 40%, #52525b 75%, #a1a1aa)' 
            }} />
            
            <div className="relative z-10 h-full flex flex-col justify-between">
              <div className="flex items-start justify-between">
                <div>
                  <div className="text-xl font-medium tracking-tight text-white">
                    ArcPay
                  </div>
                </div>
                <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-zinc-800 border border-zinc-700">
                  <span className="text-[10px] uppercase tracking-wider text-zinc-400 font-medium">
                    Debit
                  </span>
                </div>
              </div>
              
              <div className="mt-14 font-mono text-xl tracking-[0.25em] text-zinc-200">
                {cardNumber}
              </div>
              
              <div className="flex items-end justify-between mt-auto">
                <div>
                  <div className="text-[9px] uppercase tracking-[0.2em] text-zinc-500 mb-1">Cardholder</div>
                  <div className="font-mono text-[11px] text-zinc-300">{address ? `${address.slice(0, 6)}…${address.slice(-4)}` : '—'}</div>
                </div>
                <div className="text-right">
                  <div className="text-[9px] uppercase tracking-[0.2em] text-zinc-500 mb-1">Balance</div>
                  <div className="text-sm text-white font-medium">{balance === null ? '—' : `${balance.toFixed(2)} USDC`}</div>
                </div>
                <div className="text-right">
                  <div className="text-[9px] uppercase tracking-[0.2em] text-zinc-500 mb-1">Valid Thru</div>
                  <div className="font-mono text-[11px] text-zinc-300">{expiry}</div>
                </div>
              </div>
            </div>
          </div>

          {/* BACK */}
          <div
            className="absolute inset-0 w-full rounded-[16px] overflow-hidden transition-all duration-700"
            style={{
              aspectRatio: '1.586', backfaceVisibility: 'hidden', transform: 'rotateY(180deg)',
              background: cardGradient,
              border: `1px solid ${cardBorder}`,
              boxShadow: `0 10px 40px -10px rgba(0,0,0,0.5)`,
            }}
          >
            {/* Magnetic strip */}
            <div className="h-10 bg-black mt-6 w-full" />
            
            <div className="px-6 pt-4 flex gap-4">
              <div className="flex-1">
                <div className="bg-zinc-200 h-8 w-full rounded flex items-center justify-end px-3">
                  <div className="font-mono text-xs text-zinc-800">424</div>
                </div>
                <div className="text-[9px] text-zinc-500 mt-2 uppercase tracking-widest">
                  Authorized signature required
                </div>
                <button
                  onClick={(e) => { e.stopPropagation(); copyAddr(); }}
                  className="mt-4 flex items-center gap-1.5 text-[11px] text-zinc-400 hover:text-white transition-colors"
                >
                  {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                  {copied ? 'Copied' : 'Copy address'}
                </button>
              </div>
              <div className="bg-white p-1.5 rounded-lg shrink-0 w-[72px] h-[72px]">
                {address ? <QRCodeSVG value={address} size={60} /> : <div className="w-[60px] h-[60px] bg-zinc-200 rounded" />}
              </div>
            </div>
            
            <div className="absolute bottom-4 left-6 text-[10px] text-zinc-600 font-medium tracking-wide">
              Powered by Arc Network
            </div>
          </div>
        </motion.div>
      </div>

      {/* COMPACT ACTION BUTTONS under the card */}
      <div className="flex items-center justify-center gap-2 mt-6 w-full" style={{ maxWidth: 540 }}>
        <CompactBtn icon={ArrowDownToLine} label="Deposit" onClick={() => onAction?.('deposit')} />
        <CompactBtn icon={Send} label="Send" onClick={() => onAction?.('send')} />
        <CompactBtn icon={QrCode} label="Receive" onClick={() => onAction?.('receive')} />
        <CompactBtn icon={RotateCw} label="Flip" onClick={() => setFlipped((v) => !v)} />
        <CompactBtn icon={RefreshCw} label="" onClick={refresh} spinning={loading} square />
      </div>
    </div>
  );
}

function CompactBtn({
  icon: Icon, label, onClick, spinning, square
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string; onClick: () => void; spinning?: boolean; square?: boolean;
}) {
  return (
    <motion.button
      whileHover={{ scale: 1.05, y: -2 }} whileTap={{ scale: 0.96 }}
      onClick={onClick}
      className={`flex items-center justify-center gap-1.5 ${square ? 'px-3' : 'flex-1 px-3'} py-2.5 rounded-xl bg-zinc-900/70 border border-zinc-800 hover:border-sky-700/50 hover:bg-zinc-800/70 text-zinc-300 hover:text-white transition-colors text-xs`}
    >
      <Icon className={`w-3.5 h-3.5 ${spinning ? 'animate-spin' : ''}`} />
      {label && <span>{label}</span>}
    </motion.button>
  );
}
