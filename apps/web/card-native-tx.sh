#!/usr/bin/env bash
# card-native-tx.sh
# Gives the Card its OWN self-contained transaction system (separate from the
# existing Send/Deposit pages). Real on-chain underneath, card-styled UI.
#
#   • lib/cardTx.ts        — standalone deposit/send/balance, talks to chain directly
#   • components/CardActionModal.tsx — card-styled send/deposit/receive flows
#   • components/SeismicCard.tsx      — proper 3D flip, compact buttons under card
#   • app/(app)/card/page.tsx         — wires modals + live balance refresh
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

echo "→ Backing up card files…"
cp components/SeismicCard.tsx "components/SeismicCard.tsx.bak.$(date +%s)" 2>/dev/null || true
cp "app/(app)/card/page.tsx" "app/(app)/card/page.tsx.bak.$(date +%s)" 2>/dev/null || true

# ───────────────────────────────────────────────
# 1. Standalone card transaction lib (own logic, not the existing pages)
# ───────────────────────────────────────────────
echo "→ 1/4 Creating lib/cardTx.ts (card's own tx logic)…"

cat > lib/cardTx.ts <<'TS'
'use client';
// lib/cardTx.ts
// Self-contained transaction logic for the Card system.
// Separate from the app's existing Send/Deposit pages — the Card owns this.
// Real on-chain underneath: deposit() is payable, transfer(to, amount) moves shielded value.

import {
  createWalletClient, createPublicClient, custom, http,
  parseEther, isAddress, type Address,
} from 'viem';
import { seismicPay } from './contract';
import { ACTIVE_CHAIN } from './chain';

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';
const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID) || 31337;
const CHAIN_ID_HEX = '0x' + CHAIN_ID.toString(16);

type Provider = { request: (a: { method: string; params?: unknown }) => Promise<unknown> };

async function ensureNetwork(provider: Provider) {
  const current = (await provider.request({ method: 'eth_chainId' })) as string;
  if (current.toLowerCase() === CHAIN_ID_HEX.toLowerCase()) return;
  try {
    await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: CHAIN_ID_HEX }] });
  } catch (e: unknown) {
    if ((e as { code?: number }).code === 4902) {
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [{
          chainId: CHAIN_ID_HEX, chainName: 'Seismic Local',
          rpcUrls: [RPC_URL], nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
        }],
      });
    } else throw e;
  }
}

function publicClient() {
  return createPublicClient({ chain: ACTIVE_CHAIN, transport: http(RPC_URL) });
}

async function walletClient(provider: Provider, account: Address) {
  await ensureNetwork(provider);
  return createWalletClient({
    account, chain: ACTIVE_CHAIN,
    transport: custom(provider as Parameters<typeof custom>[0]),
  });
}

export async function assertContract(): Promise<void> {
  const code = await publicClient().getBytecode({ address: seismicPay.address as Address });
  if (!code || code === '0x') {
    throw new Error('Card not active on this network. Redeploy the contract (make-it-work.sh).');
  }
}

function friendly(raw: string): string {
  if (/user rejected|user denied/i.test(raw)) return 'You cancelled in your wallet.';
  if (/insufficient funds/i.test(raw)) return 'Not enough ETH for gas.';
  if (/arithmetic|overflow|underflow|reverted/i.test(raw)) return 'Insufficient card balance for this amount.';
  if (/Internal JSON-RPC/i.test(raw)) return 'Network rejected the transaction. Is the chain running?';
  if (/suint256.*encoding/i.test(raw)) return 'Card contract ABI needs refresh (run fix-suint-final.sh).';
  return raw.slice(0, 140);
}

export async function cardDeposit(
  provider: Provider, account: Address, amount: string,
): Promise<`0x${string}`> {
  await assertContract();
  const wc = await walletClient(provider, account);
  try {
    const hash = await wc.writeContract({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      functionName: 'deposit',
      args: [],
      value: parseEther(amount),
      chain: ACTIVE_CHAIN,
    });
    await publicClient().waitForTransactionReceipt({ hash, timeout: 30_000 });
    return hash;
  } catch (e) {
    throw new Error(friendly(e instanceof Error ? (e as { shortMessage?: string }).shortMessage || e.message : String(e)));
  }
}

export async function cardSend(
  provider: Provider, account: Address, to: string, amount: string,
): Promise<`0x${string}`> {
  if (!isAddress(to)) throw new Error('Recipient must be a valid 0x wallet address.');
  await assertContract();
  const wc = await walletClient(provider, account);
  try {
    const hash = await wc.writeContract({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      functionName: 'transfer',
      args: [to as Address, parseEther(amount)],
      chain: ACTIVE_CHAIN,
    });
    const receipt = await publicClient().waitForTransactionReceipt({ hash, timeout: 30_000 });
    if (receipt.status === 'reverted') throw new Error('Transaction reverted — likely insufficient card balance.');
    return hash;
  } catch (e) {
    throw new Error(friendly(e instanceof Error ? (e as { shortMessage?: string }).shortMessage || e.message : String(e)));
  }
}
TS
echo "  ✓ lib/cardTx.ts"

# ───────────────────────────────────────────────
# 2. Card action modal (card-styled send/deposit/receive)
# ───────────────────────────────────────────────
echo "→ 2/4 Creating components/CardActionModal.tsx…"

cat > components/CardActionModal.tsx <<'TSX'
'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { QRCodeSVG } from 'qrcode.react';
import { X, Loader2, CheckCircle2, XCircle, Copy, Check } from 'lucide-react';
import { useWallets } from '@privy-io/react-auth';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { cardDeposit, cardSend } from '@/lib/cardTx';
import { NATIVE_SYMBOL } from '@/lib/chain';
import type { Address } from 'viem';

export type CardAction = 'send' | 'deposit' | 'receive' | null;

type Phase =
  | { s: 'form' }
  | { s: 'working'; label: string }
  | { s: 'done'; hash: string }
  | { s: 'error'; msg: string };

export function CardActionModal({
  action, cardNumber, onClose, onSuccess,
}: {
  action: CardAction;
  cardNumber: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const address = useWalletAddress();
  const { wallets } = useWallets();
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [phase, setPhase] = useState<Phase>({ s: 'form' });
  const [copied, setCopied] = useState(false);

  const reset = () => { setTo(''); setAmount(''); setPhase({ s: 'form' }); };
  const close = () => { reset(); onClose(); };

  async function getProvider() {
    if (wallets && wallets.length > 0) {
      try { return await wallets[0].getEthereumProvider(); } catch { /* fall through */ }
    }
    if (typeof window !== 'undefined' && (window as { ethereum?: unknown }).ethereum) {
      return (window as { ethereum?: unknown }).ethereum;
    }
    return null;
  }

  const run = async () => {
    if (!address) { setPhase({ s: 'error', msg: 'Wallet not connected.' }); return; }
    const provider = await getProvider();
    if (!provider) { setPhase({ s: 'error', msg: 'No wallet provider found.' }); return; }

    try {
      if (action === 'deposit') {
        if (!(parseFloat(amount) > 0)) { setPhase({ s: 'error', msg: 'Enter an amount greater than 0.' }); return; }
        setPhase({ s: 'working', label: 'Depositing to card…' });
        const hash = await cardDeposit(provider as never, address as Address, amount);
        setPhase({ s: 'done', hash });
      } else if (action === 'send') {
        if (!to) { setPhase({ s: 'error', msg: 'Enter a recipient address.' }); return; }
        if (!(parseFloat(amount) > 0)) { setPhase({ s: 'error', msg: 'Enter an amount greater than 0.' }); return; }
        setPhase({ s: 'working', label: 'Sending from card…' });
        const hash = await cardSend(provider as never, address as Address, to, amount);
        setPhase({ s: 'done', hash });
      }
      onSuccess();
    } catch (e) {
      setPhase({ s: 'error', msg: e instanceof Error ? e.message : 'Transaction failed.' });
    }
  };

  const copyAddr = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const title = action === 'send' ? 'Send from card'
    : action === 'deposit' ? 'Deposit to card'
    : action === 'receive' ? 'Receive to card' : '';

  return (
    <AnimatePresence>
      {action && (
        <motion.div
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(5,5,10,0.7)', backdropFilter: 'blur(6px)' }}
          onClick={close}
        >
          <motion.div
            initial={{ scale: 0.94, y: 16 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.94, y: 16 }}
            transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-md rounded-3xl p-7 relative overflow-hidden"
            style={{
              background: 'linear-gradient(135deg, #1a1030 0%, #0a0a0f 60%, #160d28 100%)',
              border: '1px solid rgba(139,92,246,0.4)',
              boxShadow: '0 40px 90px -25px rgba(124,58,237,0.5)',
            }}
          >
            <button onClick={close} className="absolute top-5 right-5 text-zinc-500 hover:text-white">
              <X className="w-5 h-5" />
            </button>

            <div className="text-[10px] uppercase tracking-[0.25em] text-violet-300/70 mb-1">Seismic Card</div>
            <div className="text-xl font-light mb-1" style={{ fontFamily: 'var(--font-display), serif' }}>{title}</div>
            <div className="font-mono text-[11px] text-zinc-500 mb-6">{cardNumber}</div>

            {/* RECEIVE */}
            {action === 'receive' && (
              <div className="flex flex-col items-center gap-4">
                <div className="bg-white p-3 rounded-2xl">
                  {address ? <QRCodeSVG value={address} size={150} /> : <div className="w-[150px] h-[150px] bg-zinc-200 rounded" />}
                </div>
                <div className="w-full">
                  <div className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1">Your address</div>
                  <div className="font-mono text-xs text-zinc-300 break-all bg-black/30 rounded-lg p-3 border border-zinc-800">
                    {address || '—'}
                  </div>
                </div>
                <button
                  onClick={copyAddr}
                  className="w-full py-3 rounded-xl bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium flex items-center justify-center gap-2 transition-colors"
                >
                  {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                  {copied ? 'Copied' : 'Copy card address'}
                </button>
              </div>
            )}

            {/* SEND / DEPOSIT FORM */}
            {(action === 'send' || action === 'deposit') && phase.s === 'form' && (
              <div className="space-y-4">
                {action === 'send' && (
                  <div>
                    <label className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1.5 block">Recipient address</label>
                    <input
                      value={to} onChange={(e) => setTo(e.target.value.trim())} placeholder="0x…"
                      className="w-full bg-black/30 border border-zinc-800 rounded-xl px-4 py-3 font-mono text-sm text-white placeholder-zinc-600 outline-none focus:border-violet-500/60 transition"
                    />
                  </div>
                )}
                <div>
                  <label className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1.5 block">Amount ({NATIVE_SYMBOL})</label>
                  <input
                    value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.0" type="number" step="0.001" min="0"
                    className="w-full bg-black/30 border border-zinc-800 rounded-xl px-4 py-3 text-lg text-white placeholder-zinc-600 outline-none focus:border-violet-500/60 transition"
                  />
                </div>
                <button
                  onClick={run}
                  className="w-full py-3 rounded-xl bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium transition-colors"
                >
                  {action === 'send' ? 'Send shielded' : 'Deposit'}
                </button>
              </div>
            )}

            {/* WORKING */}
            {phase.s === 'working' && (
              <div className="py-8 flex flex-col items-center gap-3">
                <Loader2 className="w-8 h-8 text-violet-400 animate-spin" />
                <div className="text-sm text-zinc-300">{phase.label}</div>
                <div className="text-[11px] text-zinc-500">Confirm in your wallet…</div>
              </div>
            )}

            {/* DONE */}
            {phase.s === 'done' && (
              <div className="py-6 flex flex-col items-center gap-3">
                <CheckCircle2 className="w-10 h-10 text-emerald-400" />
                <div className="text-sm text-white">Transaction confirmed</div>
                <div className="font-mono text-[10px] text-zinc-500 break-all text-center px-4">{phase.hash}</div>
                <button onClick={close} className="mt-2 px-5 py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-sm transition-colors">Done</button>
              </div>
            )}

            {/* ERROR */}
            {phase.s === 'error' && (
              <div className="py-6 flex flex-col items-center gap-3">
                <XCircle className="w-10 h-10 text-red-400" />
                <div className="text-sm text-white text-center">{phase.msg}</div>
                <button onClick={() => setPhase({ s: 'form' })} className="mt-2 px-5 py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-sm transition-colors">Try again</button>
              </div>
            )}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
TSX
echo "  ✓ components/CardActionModal.tsx"

# ───────────────────────────────────────────────
# 3. SeismicCard — proper flip + compact buttons emit action events
# ───────────────────────────────────────────────
echo "→ 3/4 Rewriting SeismicCard.tsx (proper flip + compact buttons)…"

cat > components/SeismicCard.tsx <<'TSX'
'use client';

import { useRef, useState, useEffect } from 'react';
import { motion, useMotionValue, useSpring, useTransform } from 'framer-motion';
import { QRCodeSVG } from 'qrcode.react';
import { Shield, Copy, Check, RefreshCw, RotateCw, Send, ArrowDownToLine, QrCode } from 'lucide-react';
import { formatEther } from 'viem';
import { calculateBalance } from '@/lib/balance';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { NATIVE_SYMBOL } from '@/lib/chain';
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

export function SeismicCard({
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
    if (flipped) return; // don't tilt while flipped
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
      const wei = await calculateBalance(address);
      const v = parseFloat(formatEther(wei));
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

  return (
    <div className="flex flex-col items-center w-full">
      <div
        ref={ref} onMouseMove={onMove} onMouseLeave={onLeave}
        className="relative w-full" style={{ perspective: 1400, maxWidth: 540 }}
      >
        <motion.div
          style={{ rotateX: flipped ? 0 : rotateX, rotateY: rotateYTilt, transformStyle: 'preserve-3d' }}
          animate={{ rotateY: flipped ? 180 : 0 }}
          transition={{ duration: 0.75, ease: [0.16, 1, 0.3, 1] }}
          className="relative w-full"
          style2={{}}
        >
          {/* FRONT */}
          <div
            className="relative w-full rounded-[1.4rem] p-7 overflow-hidden"
            style={{
              aspectRatio: '1.586', backfaceVisibility: 'hidden',
              background: 'linear-gradient(135deg, #241248 0%, #120a26 45%, #0a0a0f 75%, #1b0f33 100%)',
              border: '1px solid rgba(139,92,246,0.45)',
              boxShadow: '0 40px 90px -25px rgba(124,58,237,0.55), inset 0 1px 0 rgba(255,255,255,0.08), inset 0 0 60px rgba(124,58,237,0.08)',
            }}
          >
            <div aria-hidden className="absolute inset-0" style={{ background: 'radial-gradient(130% 130% at 0% 0%, rgba(139,92,246,0.35), transparent 42%), radial-gradient(130% 130% at 100% 100%, rgba(99,102,241,0.25), transparent 48%)' }} />
            <motion.div aria-hidden className="absolute -inset-y-16 w-1/3"
              style={{ background: 'linear-gradient(90deg, transparent, rgba(196,181,253,0.14), transparent)', transform: 'skewX(-18deg)' }}
              animate={{ left: ['-40%', '150%'] }}
              transition={{ duration: 5.5, repeat: Infinity, ease: 'easeInOut', repeatDelay: 2.5 }}
            />
            <div className="relative z-10 h-full flex flex-col justify-between">
              <div className="flex items-start justify-between">
                <div>
                  <div className="text-[10px] uppercase tracking-[0.3em] text-violet-300/80">Seismic</div>
                  <div className="text-2xl leading-none mt-1" style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}>Shielded</div>
                </div>
                <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/30">
                  <Shield className="w-3 h-3 text-emerald-400" />
                  <span className="text-[9px] uppercase tracking-wider text-emerald-300">Private</span>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="w-12 h-9 rounded-md" style={{ background: 'linear-gradient(135deg, #ddd6fe, #7c3aed 40%, #6366f1 75%, #c4b5fd)', boxShadow: 'inset 0 0 8px rgba(0,0,0,0.5)' }} />
                <div className="text-[10px] text-violet-300/50 uppercase tracking-[0.2em]">TEE encrypted</div>
              </div>
              <div className="font-mono text-2xl tracking-[0.2em] text-zinc-50">{cardNumber}</div>
              <div className="flex items-end justify-between">
                <div>
                  <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40">Cardholder</div>
                  <div className="font-mono text-xs text-zinc-300">{address ? `${address.slice(0, 6)}…${address.slice(-4)}` : '—'}</div>
                </div>
                <div className="text-right">
                  <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40">Balance</div>
                  <div className="text-base text-white font-light">{balance === null ? '—' : `${balance.toFixed(4)} ${NATIVE_SYMBOL}`}</div>
                </div>
                <div className="text-right">
                  <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40">Expires</div>
                  <div className="font-mono text-xs text-zinc-300">{expiry}</div>
                </div>
              </div>
            </div>
          </div>

          {/* BACK */}
          <div
            className="absolute inset-0 w-full rounded-[1.4rem] overflow-hidden"
            style={{
              aspectRatio: '1.586', backfaceVisibility: 'hidden', transform: 'rotateY(180deg)',
              background: 'linear-gradient(135deg, #0a0a0f 0%, #160d28 60%, #241248 100%)',
              border: '1px solid rgba(139,92,246,0.45)',
              boxShadow: '0 40px 90px -25px rgba(124,58,237,0.55)',
            }}
          >
            {/* security strip */}
            <div className="h-9 bg-black/80 mt-6" />
            <div className="px-7 pt-4">
              <div className="flex items-center justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <div className="text-[8px] uppercase tracking-[0.2em] text-violet-300/40 mb-1">Account address</div>
                  <div className="font-mono text-[10px] text-zinc-300 break-all leading-relaxed">{address || '—'}</div>
                  <div className="mt-2 grid grid-cols-2 gap-2 text-[9px]">
                    <div>
                      <div className="text-violet-300/40 uppercase tracking-wider">Network</div>
                      <div className="text-zinc-300">Seismic</div>
                    </div>
                    <div>
                      <div className="text-violet-300/40 uppercase tracking-wider">Type</div>
                      <div className="text-zinc-300">Shielded vault</div>
                    </div>
                  </div>
                  <button
                    onClick={(e) => { e.stopPropagation(); copyAddr(); }}
                    className="mt-3 flex items-center gap-1 text-[10px] text-violet-300 hover:text-violet-200"
                  >
                    {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
                    {copied ? 'Copied' : 'Copy card details'}
                  </button>
                </div>
                <div className="bg-white p-2 rounded-lg shrink-0">
                  {address ? <QRCodeSVG value={address} size={82} /> : <div className="w-[82px] h-[82px] bg-zinc-200 rounded" />}
                </div>
              </div>
            </div>
            <div className="absolute bottom-4 left-7 right-7 flex items-center justify-between">
              <div className="text-[8px] text-violet-300/40 uppercase tracking-widest">Privacy by Seismic · suint256</div>
              <div className="font-mono text-[9px] text-zinc-500">CVV •••</div>
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
  icon: Icon, label, onClick, spinning, square,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string; onClick: () => void; spinning?: boolean; square?: boolean;
}) {
  return (
    <motion.button
      whileHover={{ scale: 1.05, y: -2 }} whileTap={{ scale: 0.96 }}
      onClick={onClick}
      className={`flex items-center justify-center gap-1.5 ${square ? 'px-3' : 'flex-1 px-3'} py-2.5 rounded-xl bg-zinc-900/70 border border-zinc-800 hover:border-violet-700/50 hover:bg-zinc-800/70 text-zinc-300 hover:text-white transition-colors text-xs`}
    >
      <Icon className={`w-3.5 h-3.5 ${spinning ? 'animate-spin' : ''}`} />
      {label && <span>{label}</span>}
    </motion.button>
  );
}
TSX
echo "  ✓ components/SeismicCard.tsx"

# Fix the accidental style2 attr (defensive — remove it)
sed -i '/style2={{}}/d' components/SeismicCard.tsx

# ───────────────────────────────────────────────
# 4. Card page — wire modal + refresh
# ───────────────────────────────────────────────
echo "→ 4/4 Wiring card page to modals…"

cat > "app/(app)/card/page.tsx" <<'TSX'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { ArrowDownToLine, ArrowUpRight, ArrowDownLeft } from 'lucide-react';
import { SeismicCard, cardNumberFromAddress } from '@/components/SeismicCard';
import { CardActionModal, type CardAction } from '@/components/CardActionModal';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { NATIVE_SYMBOL } from '@/lib/chain';

function Counter({ value, decimals = 0 }: { value: number; decimals?: number }) {
  const [d, setD] = useState(0);
  useEffect(() => {
    let raf = 0; const start = performance.now(); const from = d;
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

export default function CardPage() {
  const address = useWalletAddress();
  const [events, setEvents] = useState<HistoryEvent[]>([]);
  const [balance, setBalance] = useState<number | null>(null);
  const [action, setAction] = useState<CardAction>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const cardNumber = cardNumberFromAddress(address);

  const loadEvents = async () => {
    if (!address) return;
    try { setEvents(await fetchHistory(address)); } catch { /* ignore */ }
  };

  useEffect(() => {
    loadEvents();
    const id = setInterval(loadEvents, 8000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address]);

  const sent = events.filter((e) => e.type === 'send').length;
  const received = events.filter((e) => e.type === 'receive').length;

  const afterSuccess = () => {
    setRefreshKey((k) => k + 1); // forces card balance refresh
    loadEvents();
  };

  return (
    <div className="relative">
      <div aria-hidden className="absolute inset-0 -z-10"
        style={{ background: 'radial-gradient(60% 50% at 50% 0%, rgba(124,58,237,0.12), transparent 70%)' }} />

      <div className="text-center pt-4 pb-2">
        <div className="text-[11px] uppercase tracking-[0.3em] text-violet-300/70 mb-2">Seismic Shielded Card</div>
        <h1 className="text-3xl md:text-4xl font-light tracking-tight mb-10" style={{ fontFamily: 'var(--font-display), serif' }}>
          Your money, encrypted on-chain.
        </h1>
      </div>

      <div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums">
            {balance === null ? '—' : <Counter value={balance} decimals={2} />}
          </div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Balance ({NATIVE_SYMBOL})</div>
        </div>
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums"><Counter value={sent} /></div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Sent</div>
        </div>
        <div>
          <div className="text-4xl md:text-6xl font-extralight tracking-tight text-white tabular-nums"><Counter value={received} /></div>
          <div className="text-[11px] uppercase tracking-[0.15em] text-zinc-500 mt-2">Received</div>
        </div>
      </div>

      <motion.div
        initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
        className="flex justify-center mb-14"
      >
        <SeismicCard onBalance={setBalance} onAction={setAction} refreshKey={refreshKey} />
      </motion.div>

      <div className="max-w-3xl mx-auto bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur">
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">Recent activity</div>
        {events.length === 0 ? (
          <div className="text-sm text-zinc-500 py-6 text-center">No activity yet. Deposit to your card to get started.</div>
        ) : (
          <div className="space-y-2">
            {events.slice(0, 6).map((e, i) => (
              <motion.div key={`${e.hash}-${i}`} initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.05 }}
                className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-zinc-800/40 transition-colors">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-zinc-800/60 flex items-center justify-center">
                    {e.type === 'deposit' && <ArrowDownToLine className="w-3.5 h-3.5 text-emerald-400" />}
                    {e.type === 'send' && <ArrowUpRight className="w-3.5 h-3.5 text-red-400" />}
                    {e.type === 'receive' && <ArrowDownLeft className="w-3.5 h-3.5 text-violet-400" />}
                    {e.type === 'withdraw' && <ArrowUpRight className="w-3.5 h-3.5 text-amber-400" />}
                  </div>
                  <div>
                    <div className="text-sm text-zinc-200 capitalize">{e.type}</div>
                    <div className="text-[10px] font-mono text-zinc-600">{e.hash ? `${e.hash.slice(0, 10)}…` : ''}</div>
                  </div>
                </div>
                <div className="text-[10px] uppercase tracking-wider text-emerald-400/70">confirmed</div>
              </motion.div>
            ))}
          </div>
        )}
      </div>

      <CardActionModal
        action={action}
        cardNumber={cardNumber}
        onClose={() => setAction(null)}
        onSuccess={afterSuccess}
      />
    </div>
  );
}
TSX
echo "  ✓ card page wired"

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — card-native transaction system"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Ctrl+C npm run dev, then 'npm run dev', hard-refresh."
echo ""
echo "  The Card now has its OWN transaction system (lib/cardTx.ts),"
echo "  separate from the Send/Deposit pages:"
echo "    • Compact buttons under the card: Deposit / Send / Receive / Flip / Refresh"
echo "    • Each opens a card-styled modal (not the old pages)"
echo "    • Send: enter 0x address + amount → real on-chain transfer"
echo "    • Deposit: enter amount → real on-chain deposit"
echo "    • Receive: QR code + copy card address"
echo "    • Loading / success / error states in the modal"
echo "    • Balance + activity auto-refresh after each tx"
echo "    • Flip button does a real 3D rotation to the full back side"
echo "      (security strip, QR, account details, copy button)"
