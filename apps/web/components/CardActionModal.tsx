'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { QRCodeSVG } from 'qrcode.react';
import { X, Loader2, CheckCircle2, XCircle, Copy, Check } from 'lucide-react';
import { useWallets } from '@privy-io/react-auth';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { cardDeposit, cardSendByNumber } from '@/lib/cardTx';
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

  const tokenSymbol = 'USDC';

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
        if (!to.replace(/\D/g,'')) { setPhase({ s: 'error', msg: 'Enter a recipient card number.' }); return; }
        if (!(parseFloat(amount) > 0)) { setPhase({ s: 'error', msg: 'Enter an amount greater than 0.' }); return; }
        setPhase({ s: 'working', label: 'Sending from card…' });
        const hash = await cardSendByNumber(provider as never, address as Address, to, amount);
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
              background: 'linear-gradient(135deg, #0f172a 0%, #020617 60%, #172554 100%)',
              border: '1px solid rgba(56,189,248,0.4)',
              boxShadow: '0 40px 90px -25px rgba(14,165,233,0.5)',
            }}
          >
            <button onClick={close} className="absolute top-5 right-5 text-zinc-500 hover:text-white">
              <X className="w-5 h-5" />
            </button>

            <div className="text-[10px] uppercase tracking-[0.25em] text-sky-300/70 mb-1">
              ArcPay Card
            </div>
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
                  className="w-full py-3 rounded-xl bg-sky-600 hover:bg-sky-500 text-white text-sm font-medium flex items-center justify-center gap-2 transition-colors"
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
                    <label className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1.5 block">Recipient card number</label>
                    <input
                      value={to} onChange={(e) => setTo(e.target.value.trim())} placeholder="5815 8051 0010 7009"
                      className="w-full bg-black/30 border border-zinc-800 rounded-xl px-4 py-3 font-mono text-sm text-white placeholder-zinc-600 outline-none focus:border-sky-500/60 transition"
                    />
                  </div>
                )}
                <div>
                  <label className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1.5 block">Amount ({tokenSymbol})</label>
                  <input
                    value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.0" type="number" step="0.001" min="0"
                    className="w-full bg-black/30 border border-zinc-800 rounded-xl px-4 py-3 text-lg text-white placeholder-zinc-600 outline-none focus:border-sky-500/60 transition"
                  />
                </div>
                <button
                  onClick={run}
                  className="w-full py-3 rounded-xl bg-sky-600 hover:bg-sky-500 text-white text-sm font-medium transition-colors"
                >
                  {action === 'send' ? 'Send' : 'Deposit'}
                </button>
              </div>
            )}

            {/* WORKING */}
            {phase.s === 'working' && (
              <div className="py-8 flex flex-col items-center gap-3">
                <Loader2 className="w-8 h-8 text-sky-400 animate-spin" />
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
