#!/usr/bin/env bash
# apply-phase-4.sh
# Phase 4 — Multi-page premium UI for AI Pay Seismic.
# Run from inside ~/code/ai-pay-seismic/apps/web/
#   cd ~/code/ai-pay-seismic/apps/web && bash apply-phase-4.sh
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/ (where Next.js package.json lives)."
  exit 1
fi

echo "→ Installing new dependencies (lucide-react, qrcode.react)…"
npm install lucide-react qrcode.react >/dev/null 2>&1 || npm install lucide-react qrcode.react

echo "→ Cleaning old single-page structure…"
rm -rf app/dashboard

echo "→ Creating directory tree…"
mkdir -p lib components abi
mkdir -p "app/(app)/dashboard"
mkdir -p "app/(app)/send"
mkdir -p "app/(app)/deposit"
mkdir -p "app/(app)/receive"
mkdir -p "app/(app)/history"
mkdir -p "app/(app)/portfolio"
mkdir -p "app/(app)/trading"
mkdir -p "app/(app)/settings"
mkdir -p app/api/chat

# Ensure ABI exists
if [ ! -f "abi/SeismicPay.ts" ] && [ -f "../../contracts/out/SeismicPay.sol/SeismicPay.json" ]; then
  node -e "const j=require('../../contracts/out/SeismicPay.sol/SeismicPay.json'); require('fs').writeFileSync('abi/SeismicPay.ts', 'export const seismicPayAbi = ' + JSON.stringify(j.abi) + ' as const;');"
fi

# =============================================================================
# lib/contract.ts
# =============================================================================
cat > lib/contract.ts << '___F_CONTRACT___'
import { seismicPayAbi } from '@/abi/SeismicPay';
import { sanvil } from 'seismic-viem';

export const SEISMIC_PAY_ADDRESS = process.env
  .NEXT_PUBLIC_SEISMIC_PAY_ADDRESS as `0x${string}`;

export const CHAIN = sanvil;

export const seismicPay = {
  address: SEISMIC_PAY_ADDRESS,
  abi: seismicPayAbi,
} as const;
___F_CONTRACT___

# =============================================================================
# lib/wagmi.ts
# =============================================================================
cat > lib/wagmi.ts << '___F_WAGMI___'
import { http } from 'viem';
import { sanvil } from 'seismic-viem';
import { createConfig } from '@privy-io/wagmi';

export const wagmiConfig = createConfig({
  chains: [sanvil],
  transports: {
    [sanvil.id]: http(
      process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545',
    ),
  },
});
___F_WAGMI___

# =============================================================================
# lib/useShielded.ts — THE WALLET BRIDGE FIX
# Bypasses seismic-react's hook (which doesn't bind to Privy reliably)
# and constructs the shielded client directly from Privy's wallet provider.
# =============================================================================
cat > lib/useShielded.ts << '___F_USESHIELDED___'
'use client';

import { useEffect, useState } from 'react';
import { useWallets } from '@privy-io/react-auth';
import { useAccount, useChainId } from 'wagmi';
import { createShieldedWalletClient, sanvil } from 'seismic-viem';
import { custom, type Address } from 'viem';

/* eslint-disable @typescript-eslint/no-explicit-any */
type ShieldedClient = any;
/* eslint-enable @typescript-eslint/no-explicit-any */

export function useShielded() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { wallets } = useWallets();
  const [walletClient, setWalletClient] = useState<ShieldedClient | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function init() {
      if (!isConnected || !address || wallets.length === 0) {
        setWalletClient(null);
        return;
      }
      if (chainId !== sanvil.id) {
        setWalletClient(null);
        return;
      }
      setLoading(true);
      try {
        const wallet = wallets[0];
        const provider = await wallet.getEthereumProvider();
        const c = await createShieldedWalletClient({
          chain: sanvil,
          transport: custom(provider),
          account: address as Address,
        });
        if (!cancelled) {
          setWalletClient(c);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : String(e));
          setWalletClient(null);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    init();
    return () => {
      cancelled = true;
    };
  }, [address, isConnected, chainId, wallets]);

  return {
    walletClient,
    account: address ? ({ address: address as Address } as const) : null,
    address: address as Address | undefined,
    ready: !!walletClient,
    loading,
    error,
  };
}
___F_USESHIELDED___

# =============================================================================
# lib/tools.ts
# =============================================================================
cat > lib/tools.ts << '___F_TOOLS___'
import { getShieldedContract } from 'seismic-viem';
import { parseEther, formatEther, type Address } from 'viem';
import { seismicPay } from './contract';

export type ToolCall = { name: string; args: Record<string, unknown> };
export type ToolResult =
  | { ok: true; data: string; hash?: string }
  | { ok: false; error: string };

/* eslint-disable @typescript-eslint/no-explicit-any */
type WalletClient = any;
type Account = any;
/* eslint-enable @typescript-eslint/no-explicit-any */

export async function executeTool(
  tc: ToolCall,
  walletClient: WalletClient,
  account: Account,
): Promise<ToolResult> {
  if (!walletClient || !account) {
    return {
      ok: false,
      error: 'Wallet not connected. Make sure you are on Seismic Local.',
    };
  }

  const contract = getShieldedContract({ ...seismicPay, client: walletClient });

  try {
    switch (tc.name) {
      case 'get_balance': {
        const bal = (await contract.read.balanceOf([
          account.address as Address,
        ])) as bigint;
        return { ok: true, data: `${formatEther(bal)} ETH` };
      }
      case 'deposit': {
        const amount = parseEther(String(tc.args.amount));
        const hash = await contract.write.deposit({ value: amount });
        return {
          ok: true,
          data: `Deposited ${tc.args.amount} ETH`,
          hash: hash as string,
        };
      }
      case 'send_payment': {
        const amount = parseEther(String(tc.args.amount));
        const to = String(tc.args.to) as Address;
        const hash = await contract.write.transfer([to, amount]);
        const short = `${to.slice(0, 6)}…${to.slice(-4)}`;
        return {
          ok: true,
          data: `Sent ${tc.args.amount} ETH to ${short}`,
          hash: hash as string,
        };
      }
      default:
        return { ok: false, error: `Unknown tool: ${tc.name}` };
    }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'unknown error';
    return { ok: false, error: msg.slice(0, 240) };
  }
}
___F_TOOLS___

# =============================================================================
# lib/history.ts — On-chain event fetching
# =============================================================================
cat > lib/history.ts << '___F_HISTORY___'
import { createPublicClient, http, type Address, type Hash } from 'viem';
import { sanvil } from 'seismic-viem';
import { seismicPay } from './contract';

export type HistoryEvent = {
  type: 'deposit' | 'send' | 'receive' | 'withdraw';
  txHash: Hash;
  blockNumber: bigint;
  counterparty?: Address;
  timestamp?: number;
};

const publicClient = createPublicClient({
  chain: sanvil,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545',
  ),
});

export async function fetchHistory(user: Address): Promise<HistoryEvent[]> {
  const events: HistoryEvent[] = [];

  // Deposits by the user
  const deposits = await publicClient.getContractEvents({
    address: seismicPay.address,
    abi: seismicPay.abi,
    eventName: 'Deposited',
    args: { user },
    fromBlock: 0n,
  });
  for (const e of deposits) {
    events.push({
      type: 'deposit',
      txHash: e.transactionHash!,
      blockNumber: e.blockNumber!,
    });
  }

  // Transfers FROM the user (outgoing sends)
  const sends = await publicClient.getContractEvents({
    address: seismicPay.address,
    abi: seismicPay.abi,
    eventName: 'Transferred',
    args: { from: user },
    fromBlock: 0n,
  });
  for (const e of sends) {
    const args = e.args as { from: Address; to: Address };
    events.push({
      type: 'send',
      txHash: e.transactionHash!,
      blockNumber: e.blockNumber!,
      counterparty: args.to,
    });
  }

  // Transfers TO the user (incoming receives)
  const receives = await publicClient.getContractEvents({
    address: seismicPay.address,
    abi: seismicPay.abi,
    eventName: 'Transferred',
    args: { to: user },
    fromBlock: 0n,
  });
  for (const e of receives) {
    const args = e.args as { from: Address; to: Address };
    events.push({
      type: 'receive',
      txHash: e.transactionHash!,
      blockNumber: e.blockNumber!,
      counterparty: args.from,
    });
  }

  // Withdrawals
  const withdraws = await publicClient.getContractEvents({
    address: seismicPay.address,
    abi: seismicPay.abi,
    eventName: 'Withdrawn',
    args: { user },
    fromBlock: 0n,
  });
  for (const e of withdraws) {
    events.push({
      type: 'withdraw',
      txHash: e.transactionHash!,
      blockNumber: e.blockNumber!,
    });
  }

  // Sort most recent first, then attach timestamps
  events.sort((a, b) => Number(b.blockNumber - a.blockNumber));

  // Fetch block timestamps in parallel (capped to 50 most recent)
  const top = events.slice(0, 50);
  await Promise.all(
    top.map(async (ev) => {
      try {
        const block = await publicClient.getBlock({
          blockNumber: ev.blockNumber,
        });
        ev.timestamp = Number(block.timestamp) * 1000;
      } catch {
        /* ignore */
      }
    }),
  );

  return events;
}
___F_HISTORY___

# =============================================================================
# components/Toast.tsx + ToastProvider
# =============================================================================
cat > components/Toast.tsx << '___F_TOAST___'
'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { CheckCircle2, XCircle, Info } from 'lucide-react';

type ToastKind = 'success' | 'error' | 'info';
type Toast = { id: number; kind: ToastKind; title: string; body?: string };

type ToastCtx = {
  push: (t: Omit<Toast, 'id'>) => void;
};

const Ctx = createContext<ToastCtx | null>(null);

export function useToast() {
  const c = useContext(Ctx);
  if (!c) throw new Error('useToast outside ToastProvider');
  return c;
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const push = useCallback((t: Omit<Toast, 'id'>) => {
    const id = Date.now() + Math.random();
    setToasts((arr) => [...arr, { id, ...t }]);
    setTimeout(() => {
      setToasts((arr) => arr.filter((x) => x.id !== id));
    }, 5000);
  }, []);

  return (
    <Ctx.Provider value={{ push }}>
      {children}
      <div className="fixed top-4 right-4 z-[100] flex flex-col gap-2 pointer-events-none">
        <AnimatePresence initial={false}>
          {toasts.map((t) => (
            <ToastItem key={t.id} toast={t} />
          ))}
        </AnimatePresence>
      </div>
    </Ctx.Provider>
  );
}

function ToastItem({ toast }: { toast: Toast }) {
  const Icon =
    toast.kind === 'success'
      ? CheckCircle2
      : toast.kind === 'error'
        ? XCircle
        : Info;
  const colour =
    toast.kind === 'success'
      ? 'text-emerald-400 border-emerald-900/40 bg-emerald-950/40'
      : toast.kind === 'error'
        ? 'text-red-400 border-red-900/40 bg-red-950/40'
        : 'text-violet-400 border-violet-900/40 bg-violet-950/40';

  return (
    <motion.div
      initial={{ opacity: 0, x: 24, scale: 0.95 }}
      animate={{ opacity: 1, x: 0, scale: 1 }}
      exit={{ opacity: 0, x: 24, transition: { duration: 0.15 } }}
      transition={{ type: 'spring', stiffness: 350, damping: 28 }}
      className={`pointer-events-auto min-w-[280px] max-w-sm px-4 py-3 rounded-xl border backdrop-blur ${colour}`}
    >
      <div className="flex items-start gap-3">
        <Icon className="w-4 h-4 mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium text-zinc-100">{toast.title}</div>
          {toast.body && (
            <div className="text-xs text-zinc-400 mt-0.5 break-all">
              {toast.body}
            </div>
          )}
        </div>
      </div>
    </motion.div>
  );
}
___F_TOAST___

# =============================================================================
# components/NetworkGate.tsx
# =============================================================================
cat > components/NetworkGate.tsx << '___F_NETGATE___'
'use client';

import { motion } from 'framer-motion';
import { useChainId, useSwitchChain } from 'wagmi';
import { sanvil } from 'seismic-viem';
import { AlertTriangle } from 'lucide-react';

export function NetworkGate({ children }: { children: React.ReactNode }) {
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  if (chainId === sanvil.id) return <>{children}</>;

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-amber-950/30 border border-amber-900/50 rounded-2xl p-6 mb-6"
    >
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
        <div className="flex-1">
          <div className="text-sm font-medium text-amber-200 mb-1">
            Wrong network
          </div>
          <div className="text-xs text-amber-300/70 mb-4">
            Your wallet is on chain {chainId || 'unknown'}. AI Pay Seismic runs
            on Seismic Local (31337).
          </div>
          <button
            onClick={() => switchChain({ chainId: sanvil.id })}
            disabled={isPending}
            className="px-4 py-2 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 rounded-lg text-sm font-medium text-amber-50 transition-colors"
          >
            {isPending ? 'Switching…' : 'Switch to Seismic Local'}
          </button>
          <div className="text-xs text-amber-300/50 mt-3 leading-relaxed">
            If MetaMask says network doesn&apos;t exist, add manually: RPC{' '}
            <code className="bg-black/40 px-1 rounded">
              http://127.0.0.1:8545
            </code>
            , Chain ID <code className="bg-black/40 px-1 rounded">31337</code>,
            Symbol <code className="bg-black/40 px-1 rounded">ETH</code>.
          </div>
        </div>
      </div>
    </motion.div>
  );
}
___F_NETGATE___

# =============================================================================
# components/NumberCounter.tsx
# =============================================================================
cat > components/NumberCounter.tsx << '___F_COUNTER___'
'use client';

import { useEffect, useRef, useState } from 'react';

export function NumberCounter({
  value,
  decimals = 4,
}: {
  value: number;
  decimals?: number;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);

  useEffect(() => {
    const start = prevRef.current;
    const end = value;
    const duration = 700;
    const t0 = performance.now();
    let raf = 0;
    const tick = (t: number) => {
      const elapsed = t - t0;
      const k = Math.min(1, elapsed / duration);
      const eased = 1 - Math.pow(1 - k, 3);
      setDisplay(start + (end - start) * eased);
      if (k < 1) raf = requestAnimationFrame(tick);
      else prevRef.current = end;
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return <span>{display.toFixed(decimals)}</span>;
}
___F_COUNTER___

# =============================================================================
# components/Card.tsx — reusable glass card with hover tilt
# =============================================================================
cat > components/Card.tsx << '___F_CARD___'
'use client';

import { motion, type HTMLMotionProps } from 'framer-motion';
import { forwardRef } from 'react';

type Props = HTMLMotionProps<'div'> & { tilt?: boolean };

export const Card = forwardRef<HTMLDivElement, Props>(function Card(
  { tilt, className = '', children, ...rest },
  ref,
) {
  return (
    <motion.div
      ref={ref}
      whileHover={
        tilt
          ? { y: -2, transition: { duration: 0.2 } }
          : undefined
      }
      className={`bg-zinc-900/60 border border-zinc-800/80 rounded-2xl backdrop-blur transition-colors hover:border-zinc-700/80 ${className}`}
      {...rest}
    >
      {children}
    </motion.div>
  );
});
___F_CARD___

# =============================================================================
# components/BalanceCard.tsx
# =============================================================================
cat > components/BalanceCard.tsx << '___F_BALCARD___'
'use client';

import { motion } from 'framer-motion';
import { useCallback, useEffect, useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { formatEther } from 'viem';
import { RefreshCw, EyeOff } from 'lucide-react';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { NumberCounter } from './NumberCounter';

export function BalanceCard() {
  const { walletClient, account, ready } = useShielded();
  const [balance, setBalance] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [hidden, setHidden] = useState(false);

  const refresh = useCallback(async () => {
    if (!walletClient || !account) return;
    setLoading(true);
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      const bal = (await contract.read.balanceOf([account.address])) as bigint;
      setBalance(parseFloat(formatEther(bal)));
    } catch (e) {
      console.error('balance read failed', e);
      setBalance(null);
    } finally {
      setLoading(false);
    }
  }, [walletClient, account]);

  useEffect(() => {
    if (ready) refresh();
  }, [ready, refresh]);

  return (
    <motion.div
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
      className="relative overflow-hidden bg-gradient-to-br from-violet-950/30 via-zinc-900/60 to-zinc-900/60 border border-violet-900/30 rounded-2xl p-7 backdrop-blur"
    >
      <div
        className="absolute -top-20 -right-20 w-60 h-60 bg-violet-500/10 rounded-full blur-3xl pointer-events-none"
        aria-hidden
      />
      <div className="relative">
        <div className="flex items-center justify-between mb-3">
          <span className="text-xs uppercase tracking-[0.2em] text-zinc-500">
            Shielded balance
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setHidden((h) => !h)}
              className="text-zinc-500 hover:text-zinc-300 transition-colors"
              aria-label="Toggle hide"
            >
              <EyeOff className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={refresh}
              disabled={loading}
              className="text-zinc-500 hover:text-zinc-300 transition-colors disabled:opacity-40"
              aria-label="Refresh"
            >
              <RefreshCw
                className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`}
              />
            </button>
          </div>
        </div>
        <div className="text-5xl font-light tracking-tight">
          {hidden ? (
            <span className="text-zinc-600">••••••</span>
          ) : balance === null ? (
            <span className="text-zinc-600">—</span>
          ) : (
            <NumberCounter value={balance} decimals={4} />
          )}
          <span className="text-xl text-zinc-500 font-normal ml-2">ETH</span>
        </div>
        <div className="text-[11px] text-zinc-600 mt-4 font-mono">
          {account?.address
            ? `${account.address.slice(0, 6)}…${account.address.slice(-4)}`
            : 'wallet not connected'}
        </div>
      </div>
    </motion.div>
  );
}
___F_BALCARD___

# =============================================================================
# components/ToolConfirmation.tsx
# =============================================================================
cat > components/ToolConfirmation.tsx << '___F_TOOLCONFIRM___'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useRef, useState } from 'react';
import { useShielded } from '@/lib/useShielded';
import { executeTool, type ToolCall, type ToolResult } from '@/lib/tools';
import { useToast } from './Toast';

export function ToolConfirmation({
  call,
  onResult,
}: {
  call: ToolCall;
  onResult: (r: ToolResult) => void;
}) {
  const { walletClient, account } = useShielded();
  const [status, setStatus] = useState<'idle' | 'running' | 'done'>('idle');
  const startedRef = useRef(false);
  const toast = useToast();

  const isReadOnly = call.name === 'get_balance';

  const run = async () => {
    if (startedRef.current) return;
    startedRef.current = true;
    setStatus('running');
    const result = await executeTool(call, walletClient, account);
    setStatus('done');
    onResult(result);
    if (result.ok) {
      toast.push({
        kind: 'success',
        title: result.data,
        body: result.hash ? `Tx: ${result.hash.slice(0, 18)}…` : undefined,
      });
    } else if (call.name !== 'get_balance') {
      toast.push({ kind: 'error', title: 'Action failed', body: result.error });
    }
  };

  useEffect(() => {
    if (isReadOnly && status === 'idle' && walletClient && account) {
      run();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isReadOnly, walletClient, account]);

  const summary = (() => {
    if (call.name === 'send_payment')
      return `Send ${call.args.amount} ETH to ${String(call.args.to).slice(0, 8)}…`;
    if (call.name === 'deposit')
      return `Deposit ${call.args.amount} ETH to shielded vault`;
    if (call.name === 'get_balance') return 'Reading shielded balance';
    return call.name;
  })();

  if (isReadOnly) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: 1, y: 0 }}
        className="mt-2 text-xs text-zinc-500 italic"
      >
        → {summary}
        {status === 'running' ? '…' : ''}
      </motion.div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      className="mt-3 p-3 bg-zinc-950/60 border border-violet-900/50 rounded-lg"
    >
      <div className="text-[10px] uppercase tracking-[0.15em] text-violet-400 mb-1">
        Proposed action
      </div>
      <div className="text-sm mb-3 break-words">{summary}</div>
      {status === 'idle' && (
        <div className="flex gap-2">
          <button
            onClick={run}
            className="flex-1 px-3 py-2 bg-violet-600 hover:bg-violet-500 rounded-md text-xs font-medium transition-colors"
          >
            Confirm &amp; sign
          </button>
          <button
            onClick={() => onResult({ ok: false, error: 'Cancelled' })}
            className="px-3 py-2 bg-zinc-800 hover:bg-zinc-700 rounded-md text-xs font-medium transition-colors"
          >
            Cancel
          </button>
        </div>
      )}
      {status === 'running' && (
        <div className="text-xs text-zinc-400 flex items-center gap-2">
          <span className="w-2 h-2 bg-violet-500 rounded-full animate-pulse" />
          Signing &amp; broadcasting…
        </div>
      )}
    </motion.div>
  );
}
___F_TOOLCONFIRM___

# =============================================================================
# components/ChatPanel.tsx
# =============================================================================
cat > components/ChatPanel.tsx << '___F_CHATPANEL___'
'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { useState, useRef, useEffect } from 'react';
import { ToolConfirmation } from './ToolConfirmation';
import type { ToolCall, ToolResult } from '@/lib/tools';
import { Sparkles } from 'lucide-react';

type Msg = {
  role: 'user' | 'assistant';
  content: string;
  toolCall?: ToolCall;
  toolResult?: ToolResult;
};

const EXAMPLES = [
  'What is my balance?',
  'Deposit 1 ETH',
  'Send 0.5 ETH to 0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
];

export function ChatPanel({
  onTxComplete,
  embedded = true,
}: {
  onTxComplete?: () => void;
  embedded?: boolean;
}) {
  const [messages, setMessages] = useState<Msg[]>([
    {
      role: 'assistant',
      content:
        'I can check your balance, deposit, or send shielded payments. Try one of the examples or type your own.',
    },
  ]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const send = async (text?: string) => {
    const content = (text ?? input).trim();
    if (!content || busy) return;
    const next: Msg[] = [...messages, { role: 'user', content }];
    setMessages(next);
    setInput('');
    setBusy(true);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: next }),
      });
      const data = await res.json();

      if (data.error) {
        setMessages((m) => [
          ...m,
          { role: 'assistant', content: `Error: ${data.error}` },
        ]);
      } else if (data.functionCalls?.length > 0) {
        const fc = data.functionCalls[0] as ToolCall;
        setMessages((m) => [
          ...m,
          {
            role: 'assistant',
            content: data.text || `Let me ${fc.name.replace('_', ' ')}.`,
            toolCall: fc,
          },
        ]);
      } else {
        setMessages((m) => [
          ...m,
          { role: 'assistant', content: data.text || '(no response)' },
        ]);
      }
    } catch (e) {
      setMessages((m) => [
        ...m,
        { role: 'assistant', content: `Network error: ${e}` },
      ]);
    } finally {
      setBusy(false);
    }
  };

  const handleToolResult = (idx: number, result: ToolResult) => {
    setMessages((m) =>
      m.map((msg, i) => (i === idx ? { ...msg, toolResult: result } : msg)),
    );
    if (result.ok && onTxComplete) onTxComplete();
  };

  return (
    <div
      className={`bg-zinc-900/60 border border-zinc-800 rounded-2xl overflow-hidden backdrop-blur flex flex-col ${embedded ? 'h-[560px]' : 'h-full'}`}
    >
      <div className="px-5 py-3 border-b border-zinc-800 flex items-center justify-between">
        <div className="flex items-center gap-2 text-xs uppercase tracking-[0.2em] text-zinc-500">
          <Sparkles className="w-3.5 h-3.5 text-violet-400" />
          AI agent
        </div>
        {busy && (
          <span className="text-xs text-violet-400 flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-pulse" />
            thinking
          </span>
        )}
      </div>

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3">
        <AnimatePresence initial={false}>
          {messages.map((m, i) => (
            <motion.div
              key={`m-${i}`}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.25 }}
              className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-[85%] px-4 py-2.5 rounded-2xl text-sm ${
                  m.role === 'user'
                    ? 'bg-violet-600 text-white rounded-br-md'
                    : 'bg-zinc-800 text-zinc-100 rounded-bl-md'
                }`}
              >
                <div>{m.content}</div>
                {m.toolCall && !m.toolResult && (
                  <ToolConfirmation
                    call={m.toolCall}
                    onResult={(r) => handleToolResult(i, r)}
                  />
                )}
                {m.toolResult && (
                  <div
                    className={`mt-2 pt-2 border-t border-zinc-700/50 text-xs break-all ${
                      m.toolResult.ok ? 'text-emerald-400' : 'text-red-400'
                    }`}
                  >
                    {m.toolResult.ok
                      ? `✓ ${m.toolResult.data}`
                      : `✗ ${m.toolResult.error}`}
                  </div>
                )}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
        <div ref={endRef} />

        {messages.length === 1 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.4 }}
            className="pt-2 space-y-2"
          >
            <div className="text-[10px] text-zinc-600 uppercase tracking-[0.2em]">
              Try
            </div>
            {EXAMPLES.map((ex) => (
              <button
                key={ex}
                onClick={() => send(ex)}
                className="block w-full text-left text-xs px-3 py-2 bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 hover:border-zinc-700 rounded-lg transition-colors text-zinc-400 hover:text-zinc-200"
              >
                {ex}
              </button>
            ))}
          </motion.div>
        )}
      </div>

      <div className="border-t border-zinc-800 p-3 flex gap-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && send()}
          placeholder="Tell the agent what to do…"
          disabled={busy}
          className="flex-1 bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-violet-500 transition-colors"
        />
        <button
          onClick={() => send()}
          disabled={busy || !input.trim()}
          className="px-4 py-2 bg-violet-600 hover:bg-violet-500 disabled:bg-zinc-700 disabled:text-zinc-500 rounded-lg text-sm font-medium transition-colors"
        >
          {busy ? '…' : 'Send'}
        </button>
      </div>
    </div>
  );
}
___F_CHATPANEL___

# =============================================================================
# components/ChatFloater.tsx
# =============================================================================
cat > components/ChatFloater.tsx << '___F_FLOATER___'
'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { useState } from 'react';
import { Sparkles, X } from 'lucide-react';
import { ChatPanel } from './ChatPanel';

export function ChatFloater() {
  const [open, setOpen] = useState(false);

  return (
    <>
      <motion.button
        onClick={() => setOpen((o) => !o)}
        initial={{ scale: 0, rotate: -45 }}
        animate={{ scale: 1, rotate: 0 }}
        transition={{ delay: 0.6, type: 'spring', stiffness: 260, damping: 20 }}
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        className="fixed bottom-6 right-6 z-50 w-14 h-14 rounded-full bg-violet-600 hover:bg-violet-500 shadow-lg shadow-violet-900/40 flex items-center justify-center text-white"
        aria-label="Open AI agent"
      >
        <AnimatePresence mode="wait">
          {open ? (
            <motion.div
              key="x"
              initial={{ opacity: 0, rotate: -90 }}
              animate={{ opacity: 1, rotate: 0 }}
              exit={{ opacity: 0, rotate: 90 }}
              transition={{ duration: 0.15 }}
            >
              <X className="w-5 h-5" />
            </motion.div>
          ) : (
            <motion.div
              key="s"
              initial={{ opacity: 0, rotate: -90 }}
              animate={{ opacity: 1, rotate: 0 }}
              exit={{ opacity: 0, rotate: 90 }}
              transition={{ duration: 0.15 }}
            >
              <Sparkles className="w-5 h-5" />
            </motion.div>
          )}
        </AnimatePresence>
      </motion.button>

      <AnimatePresence>
        {open && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              onClick={() => setOpen(false)}
              className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm"
            />
            <motion.div
              initial={{ opacity: 0, y: 20, scale: 0.96 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 20, scale: 0.96 }}
              transition={{ type: 'spring', stiffness: 320, damping: 28 }}
              className="fixed bottom-24 right-6 z-50 w-[min(420px,calc(100vw-3rem))] h-[600px] max-h-[80vh]"
            >
              <ChatPanel embedded={false} />
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
___F_FLOATER___

# =============================================================================
# components/Sidebar.tsx
# =============================================================================
cat > components/Sidebar.tsx << '___F_SIDEBAR___'
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { motion } from 'framer-motion';
import { usePrivy } from '@privy-io/react-auth';
import { useChainId } from 'wagmi';
import { sanvil } from 'seismic-viem';
import {
  LayoutDashboard,
  Send,
  ArrowDownToLine,
  QrCode,
  Clock,
  PieChart,
  ArrowLeftRight,
  Settings,
  LogOut,
} from 'lucide-react';

const nav = [
  { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/send', label: 'Send', icon: Send },
  { href: '/deposit', label: 'Deposit', icon: ArrowDownToLine },
  { href: '/receive', label: 'Receive', icon: QrCode },
  { href: '/history', label: 'Activity', icon: Clock },
  { href: '/portfolio', label: 'Portfolio', icon: PieChart },
  { href: '/trading', label: 'Trade', icon: ArrowLeftRight },
  { href: '/settings', label: 'Settings', icon: Settings },
];

export function Sidebar() {
  const pathname = usePathname();
  const { user, logout } = usePrivy();
  const chainId = useChainId();
  const onCorrectChain = chainId === sanvil.id;

  return (
    <aside className="w-60 shrink-0 border-r border-zinc-900 bg-zinc-950/60 backdrop-blur p-5 flex flex-col">
      <div className="mb-8">
        <Link href="/dashboard" className="block">
          <h1 className="text-lg tracking-tight">
            AI Pay{' '}
            <span
              className="text-violet-400"
              style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}
            >
              Seismic
            </span>
          </h1>
          <div className="text-[10px] uppercase tracking-[0.2em] text-zinc-600 mt-1">
            Shielded payments
          </div>
        </Link>
      </div>

      <nav className="flex-1 space-y-1">
        {nav.map((item) => {
          const active = pathname === item.href;
          const Icon = item.icon;
          return (
            <Link key={item.href} href={item.href} className="block">
              <motion.div
                className={`relative flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                  active
                    ? 'text-white'
                    : 'text-zinc-500 hover:text-zinc-200'
                }`}
              >
                {active && (
                  <motion.div
                    layoutId="sidebar-active"
                    className="absolute inset-0 bg-violet-600/15 border border-violet-800/50 rounded-lg"
                    transition={{ type: 'spring', stiffness: 380, damping: 30 }}
                  />
                )}
                <Icon className="w-4 h-4 relative" />
                <span className="relative">{item.label}</span>
              </motion.div>
            </Link>
          );
        })}
      </nav>

      <div className="pt-4 border-t border-zinc-900 space-y-3">
        <div className="px-3 flex items-center gap-2 text-[11px]">
          <span
            className={`w-1.5 h-1.5 rounded-full ${onCorrectChain ? 'bg-emerald-500' : 'bg-amber-500'}`}
          />
          <span className="text-zinc-500">
            {onCorrectChain ? 'Seismic Local' : 'Wrong chain'}
          </span>
        </div>
        <div className="px-3">
          <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-600 mb-1">
            Signed in
          </div>
          <div className="text-xs font-mono text-zinc-400 truncate">
            {user?.wallet?.address
              ? `${user.wallet.address.slice(0, 6)}…${user.wallet.address.slice(-4)}`
              : user?.email?.address || '—'}
          </div>
        </div>
        <button
          onClick={logout}
          className="w-full flex items-center gap-2 px-3 py-2 text-xs text-zinc-500 hover:text-red-400 hover:bg-zinc-900/60 rounded-lg transition-colors"
        >
          <LogOut className="w-3.5 h-3.5" />
          Sign out
        </button>
      </div>
    </aside>
  );
}
___F_SIDEBAR___

# =============================================================================
# components/PageHeader.tsx
# =============================================================================
cat > components/PageHeader.tsx << '___F_PAGEHEAD___'
'use client';

import { motion } from 'framer-motion';

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35 }}
      className="flex items-end justify-between mb-8"
    >
      <div>
        <h1 className="text-3xl tracking-tight">{title}</h1>
        {subtitle && (
          <p className="text-sm text-zinc-500 mt-1.5">{subtitle}</p>
        )}
      </div>
      {action && <div>{action}</div>}
    </motion.div>
  );
}
___F_PAGEHEAD___

# =============================================================================
# app/api/chat/route.ts
# =============================================================================
cat > app/api/chat/route.ts << '___F_CHATROUTE___'
import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenAI, Type } from '@google/genai';

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const tools = [
  {
    functionDeclarations: [
      {
        name: 'get_balance',
        description:
          "Get the user's own shielded SeismicPay balance. Use whenever they ask about balance, how much they have, etc.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'send_payment',
        description:
          'Propose a shielded transfer to a recipient address. The user confirms before it executes.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            to: { type: Type.STRING, description: 'Recipient 0x-address' },
            amount: { type: Type.STRING, description: 'Amount in ETH as decimal' },
          },
          required: ['to', 'amount'],
        },
      },
      {
        name: 'deposit',
        description:
          "Deposit native ETH from the user's wallet into the shielded vault.",
        parameters: {
          type: Type.OBJECT,
          properties: {
            amount: { type: Type.STRING, description: 'Amount in ETH as decimal' },
          },
          required: ['amount'],
        },
      },
    ],
  },
];

const systemInstruction = `You are the assistant for AI Pay Seismic, a privacy-preserving payments app on the Seismic blockchain.

Rules:
- You never see the user's actual balance or transaction amounts. They live encrypted on-chain.
- For any action, call the appropriate tool. Do not invent results or hashes.
- Be concise — two sentences max unless asked for detail.
- When the user mentions "send 0.5 to <addr>", call send_payment with the parsed amount/address.`;

export async function POST(req: NextRequest) {
  try {
    const { messages } = await req.json();
    const contents = messages.map((m: { role: string; content: string }) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents,
      config: { tools, systemInstruction },
    });

    return NextResponse.json({
      text: response.text || '',
      functionCalls: (response.functionCalls || []).map((fc) => ({
        name: fc.name,
        args: fc.args,
      })),
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'unknown error';
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
___F_CHATROUTE___

# =============================================================================
# app/providers.tsx
# =============================================================================
cat > app/providers.tsx << '___F_PROVIDERS___'
'use client';

import { PrivyProvider } from '@privy-io/react-auth';
import { WagmiProvider } from '@privy-io/wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { sanvil } from 'seismic-viem';
import { wagmiConfig } from '@/lib/wagmi';
import { ToastProvider } from '@/components/Toast';
import { useState } from 'react';

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID || ''}
      config={{
        loginMethods: ['email', 'wallet'],
        appearance: { theme: 'dark', accentColor: '#7c3aed' },
        embeddedWallets: { createOnLogin: 'users-without-wallets' },
        defaultChain: sanvil,
        supportedChains: [sanvil],
      }}
    >
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>
          <ToastProvider>{children}</ToastProvider>
        </WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
___F_PROVIDERS___

# =============================================================================
# app/layout.tsx — root with custom fonts
# =============================================================================
cat > app/layout.tsx << '___F_LAYOUT___'
import type { Metadata } from 'next';
import { Instrument_Serif, Geist, JetBrains_Mono } from 'next/font/google';
import { Providers } from './providers';
import './globals.css';

const display = Instrument_Serif({
  weight: '400',
  subsets: ['latin'],
  variable: '--font-display',
});

const sans = Geist({
  subsets: ['latin'],
  variable: '--font-sans',
});

const mono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
});

export const metadata: Metadata = {
  title: 'AI Pay Seismic',
  description: 'Shielded payments with natural language',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`dark ${sans.variable} ${display.variable} ${mono.variable}`}
    >
      <body className="bg-zinc-950 text-zinc-100 antialiased font-sans">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
___F_LAYOUT___

# =============================================================================
# app/globals.css
# =============================================================================
cat > app/globals.css << '___F_GLOBALS___'
@import "tailwindcss";

:root {
  --background: #0a0a0f;
  --foreground: #f5f5f7;
}

html, body {
  background: var(--background);
  color: var(--foreground);
}

body {
  font-family: var(--font-sans), system-ui, sans-serif;
}

.font-display {
  font-family: var(--font-display), serif;
}

.font-mono {
  font-family: var(--font-mono), monospace;
}

::selection {
  background: rgba(124, 58, 237, 0.4);
}

/* subtle ambient grid background */
.bg-grid {
  background-image:
    linear-gradient(rgba(255,255,255,0.02) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255,255,255,0.02) 1px, transparent 1px);
  background-size: 64px 64px;
}

/* shimmer skeleton */
@keyframes shimmer {
  0% { background-position: -400px 0; }
  100% { background-position: 400px 0; }
}
.shimmer {
  background: linear-gradient(90deg, #1f1f27 0px, #2a2a35 200px, #1f1f27 400px);
  background-size: 800px 100%;
  animation: shimmer 1.4s linear infinite;
}

/* scrollbar */
::-webkit-scrollbar { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #27272a; border-radius: 8px; }
::-webkit-scrollbar-thumb:hover { background: #3f3f46; }
___F_GLOBALS___

# =============================================================================
# app/page.tsx — premium landing page
# =============================================================================
cat > app/page.tsx << '___F_HOME___'
'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { motion } from 'framer-motion';
import { Shield, Sparkles, Lock, Zap } from 'lucide-react';

const features = [
  {
    icon: Shield,
    title: 'Shielded by default',
    body: 'Balances and amounts stay encrypted on-chain via Seismic TEE.',
  },
  {
    icon: Sparkles,
    title: 'Just tell the agent',
    body: 'Natural language for sends, deposits, balance checks.',
  },
  {
    icon: Lock,
    title: 'Yours alone',
    body: 'Signed reads ensure only you can see your own balance.',
  },
  {
    icon: Zap,
    title: 'Sub-second finality',
    body: 'Built on Seismic for fast settlement.',
  },
];

export default function Home() {
  const { ready, authenticated, login } = usePrivy();
  const router = useRouter();

  useEffect(() => {
    if (ready && authenticated) router.replace('/dashboard');
  }, [ready, authenticated, router]);

  if (!ready) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <main className="min-h-screen relative overflow-hidden bg-grid">
      <div
        aria-hidden
        className="absolute top-0 left-1/2 -translate-x-1/2 w-[800px] h-[400px] bg-violet-600/20 rounded-full blur-3xl pointer-events-none"
      />
      <div
        aria-hidden
        className="absolute bottom-0 right-0 w-[500px] h-[500px] bg-cyan-500/10 rounded-full blur-3xl pointer-events-none"
      />

      <div className="relative max-w-5xl mx-auto px-6 py-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <div className="inline-flex items-center gap-2 px-3 py-1 mb-6 bg-violet-950/40 border border-violet-900/50 rounded-full text-xs text-violet-300">
            <span className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-pulse" />
            Built on Seismic
          </div>
          <h1 className="text-6xl md:text-7xl tracking-tight leading-[1.05] mb-6">
            Shielded payments,
            <br />
            <span className="font-display italic text-violet-300">spoken plainly.</span>
          </h1>
          <p className="text-lg text-zinc-400 max-w-xl mx-auto mb-10 leading-relaxed">
            Tell the agent what to do. Send, deposit, check balances — all
            encrypted, all on-chain, all without leaving the conversation.
          </p>
          <motion.button
            whileHover={{ scale: 1.03 }}
            whileTap={{ scale: 0.97 }}
            onClick={login}
            className="px-7 py-3.5 bg-violet-600 hover:bg-violet-500 transition-colors rounded-xl text-base font-medium shadow-lg shadow-violet-900/40"
          >
            Sign in to begin
          </motion.button>
        </motion.div>

        <motion.div
          initial="hidden"
          animate="show"
          variants={{
            hidden: {},
            show: { transition: { staggerChildren: 0.08, delayChildren: 0.4 } },
          }}
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-12"
        >
          {features.map((f) => {
            const Icon = f.icon;
            return (
              <motion.div
                key={f.title}
                variants={{
                  hidden: { opacity: 0, y: 16 },
                  show: { opacity: 1, y: 0 },
                }}
                whileHover={{ y: -3 }}
                className="bg-zinc-900/40 border border-zinc-800/80 backdrop-blur rounded-2xl p-5 transition-colors hover:border-zinc-700"
              >
                <Icon className="w-5 h-5 text-violet-400 mb-3" />
                <div className="text-sm font-medium mb-1.5">{f.title}</div>
                <div className="text-xs text-zinc-500 leading-relaxed">
                  {f.body}
                </div>
              </motion.div>
            );
          })}
        </motion.div>

        <div className="text-center mt-20 text-xs text-zinc-600">
          Phase 4 build · Local sanvil · Gemini agent
        </div>
      </div>
    </main>
  );
}
___F_HOME___

# =============================================================================
# app/(app)/layout.tsx — app layout with sidebar + chat + page transitions
# =============================================================================
cat > "app/(app)/layout.tsx" << '___F_APPLAYOUT___'
'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter, usePathname } from 'next/navigation';
import { useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Sidebar } from '@/components/Sidebar';
import { ChatFloater } from '@/components/ChatFloater';
import { NetworkGate } from '@/components/NetworkGate';

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { ready, authenticated } = usePrivy();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (ready && !authenticated) router.replace('/');
  }, [ready, authenticated, router]);

  if (!ready || !authenticated) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 overflow-y-auto">
        <div className="max-w-5xl mx-auto px-8 py-10">
          <NetworkGate>
            <AnimatePresence mode="wait">
              <motion.div
                key={pathname}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
              >
                {children}
              </motion.div>
            </AnimatePresence>
          </NetworkGate>
        </div>
      </main>
      <ChatFloater />
    </div>
  );
}
___F_APPLAYOUT___

# =============================================================================
# app/(app)/dashboard/page.tsx
# =============================================================================
cat > "app/(app)/dashboard/page.tsx" << '___F_PAGE_DASH___'
'use client';

import { motion } from 'framer-motion';
import Link from 'next/link';
import { BalanceCard } from '@/components/BalanceCard';
import { PageHeader } from '@/components/PageHeader';
import { Send, ArrowDownToLine, QrCode, Clock } from 'lucide-react';

const quick = [
  { href: '/send', icon: Send, label: 'Send', hint: 'Shielded transfer' },
  { href: '/deposit', icon: ArrowDownToLine, label: 'Deposit', hint: 'Fund your vault' },
  { href: '/receive', icon: QrCode, label: 'Receive', hint: 'Share address' },
  { href: '/history', icon: Clock, label: 'Activity', hint: 'Recent events' },
];

export default function Dashboard() {
  return (
    <>
      <PageHeader title="Dashboard" subtitle="Welcome back." />

      <BalanceCard />

      <motion.div
        initial="hidden"
        animate="show"
        variants={{
          hidden: {},
          show: { transition: { staggerChildren: 0.06, delayChildren: 0.15 } },
        }}
        className="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-6"
      >
        {quick.map((q) => {
          const Icon = q.icon;
          return (
            <motion.div
              key={q.href}
              variants={{
                hidden: { opacity: 0, y: 12 },
                show: { opacity: 1, y: 0 },
              }}
            >
              <Link href={q.href} className="block">
                <motion.div
                  whileHover={{ y: -3 }}
                  className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-5 hover:border-zinc-700 transition-colors cursor-pointer h-full"
                >
                  <Icon className="w-5 h-5 text-violet-400 mb-3" />
                  <div className="text-sm font-medium">{q.label}</div>
                  <div className="text-xs text-zinc-500 mt-1">{q.hint}</div>
                </motion.div>
              </Link>
            </motion.div>
          );
        })}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.4 }}
        className="mt-8 p-6 bg-zinc-900/40 border border-zinc-800 rounded-2xl"
      >
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-2">
          Tip
        </div>
        <p className="text-sm text-zinc-300 leading-relaxed">
          Tap the violet button bottom-right to talk to the agent from anywhere.
          Try{' '}
          <span className="text-violet-300 font-mono text-xs">
            &quot;deposit 1 ETH&quot;
          </span>{' '}
          or{' '}
          <span className="text-violet-300 font-mono text-xs">
            &quot;what is my balance?&quot;
          </span>
        </p>
      </motion.div>
    </>
  );
}
___F_PAGE_DASH___

# =============================================================================
# app/(app)/send/page.tsx
# =============================================================================
cat > "app/(app)/send/page.tsx" << '___F_PAGE_SEND___'
'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { parseEther, type Address, isAddress } from 'viem';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { useToast } from '@/components/Toast';
import { PageHeader } from '@/components/PageHeader';
import { Send as SendIcon } from 'lucide-react';

export default function SendPage() {
  const { walletClient, account, ready } = useShielded();
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [sending, setSending] = useState(false);
  const [lastHash, setLastHash] = useState<string | null>(null);
  const toast = useToast();

  const valid = isAddress(to) && parseFloat(amount) > 0;

  const submit = async () => {
    if (!valid || !walletClient || !account) return;
    setSending(true);
    setLastHash(null);
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      const hash = await contract.write.transfer([
        to as Address,
        parseEther(amount),
      ]);
      setLastHash(hash as string);
      toast.push({
        kind: 'success',
        title: `Sent ${amount} ETH`,
        body: `to ${to.slice(0, 6)}…${to.slice(-4)}`,
      });
      setTo('');
      setAmount('');
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'failed';
      toast.push({ kind: 'error', title: 'Send failed', body: msg.slice(0, 120) });
    } finally {
      setSending(false);
    }
  };

  return (
    <>
      <PageHeader
        title="Send"
        subtitle="Shielded transfer to another address. Amount stays private."
      />

      <motion.div
        initial={{ opacity: 0, x: 16 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="max-w-lg bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
      >
        <div className="space-y-5">
          <div>
            <label className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-2 block">
              Recipient
            </label>
            <input
              value={to}
              onChange={(e) => setTo(e.target.value)}
              placeholder="0x…"
              className="w-full bg-zinc-800/60 border border-zinc-700 rounded-lg px-4 py-3 font-mono text-sm focus:outline-none focus:border-violet-500 transition-colors"
            />
          </div>
          <div>
            <label className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-2 block">
              Amount (ETH)
            </label>
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.0"
              type="number"
              step="0.0001"
              className="w-full bg-zinc-800/60 border border-zinc-700 rounded-lg px-4 py-3 text-2xl font-light focus:outline-none focus:border-violet-500 transition-colors"
            />
          </div>
          <motion.button
            whileHover={{ scale: valid && ready ? 1.01 : 1 }}
            whileTap={{ scale: valid && ready ? 0.99 : 1 }}
            disabled={!valid || !ready || sending}
            onClick={submit}
            className="w-full py-3 bg-violet-600 hover:bg-violet-500 disabled:bg-zinc-800 disabled:text-zinc-500 rounded-xl font-medium transition-colors flex items-center justify-center gap-2"
          >
            <SendIcon className="w-4 h-4" />
            {sending ? 'Sending…' : 'Send shielded'}
          </motion.button>
          {lastHash && (
            <motion.div
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              className="text-xs text-emerald-400 break-all"
            >
              ✓ Confirmed: <span className="font-mono">{lastHash}</span>
            </motion.div>
          )}
        </div>
      </motion.div>
    </>
  );
}
___F_PAGE_SEND___

# =============================================================================
# app/(app)/deposit/page.tsx
# =============================================================================
cat > "app/(app)/deposit/page.tsx" << '___F_PAGE_DEPOSIT___'
'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { parseEther } from 'viem';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { useToast } from '@/components/Toast';
import { PageHeader } from '@/components/PageHeader';
import { ArrowDownToLine } from 'lucide-react';

const quickAmounts = ['0.1', '0.5', '1', '5'];

export default function DepositPage() {
  const { walletClient, account, ready } = useShielded();
  const [amount, setAmount] = useState('');
  const [depositing, setDepositing] = useState(false);
  const toast = useToast();

  const valid = parseFloat(amount) > 0;

  const submit = async () => {
    if (!valid || !walletClient || !account) return;
    setDepositing(true);
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      const hash = await contract.write.deposit({
        value: parseEther(amount),
      });
      toast.push({
        kind: 'success',
        title: `Deposited ${amount} ETH`,
        body: `Tx: ${(hash as string).slice(0, 18)}…`,
      });
      setAmount('');
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'failed';
      toast.push({ kind: 'error', title: 'Deposit failed', body: msg.slice(0, 120) });
    } finally {
      setDepositing(false);
    }
  };

  return (
    <>
      <PageHeader
        title="Deposit"
        subtitle="Move native ETH into the shielded vault. Amount becomes private."
      />

      <motion.div
        initial={{ opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="max-w-lg bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
      >
        <div className="space-y-5">
          <div>
            <label className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-2 block">
              Amount (ETH)
            </label>
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.0"
              type="number"
              step="0.0001"
              className="w-full bg-zinc-800/60 border border-zinc-700 rounded-lg px-4 py-3 text-2xl font-light focus:outline-none focus:border-violet-500 transition-colors"
            />
          </div>
          <div className="flex gap-2">
            {quickAmounts.map((a) => (
              <button
                key={a}
                onClick={() => setAmount(a)}
                className="flex-1 py-2 text-xs bg-zinc-800/60 hover:bg-zinc-800 border border-zinc-800 rounded-lg transition-colors"
              >
                {a} ETH
              </button>
            ))}
          </div>
          <motion.button
            whileHover={{ scale: valid && ready ? 1.01 : 1 }}
            whileTap={{ scale: valid && ready ? 0.99 : 1 }}
            disabled={!valid || !ready || depositing}
            onClick={submit}
            className="w-full py-3 bg-violet-600 hover:bg-violet-500 disabled:bg-zinc-800 disabled:text-zinc-500 rounded-xl font-medium transition-colors flex items-center justify-center gap-2"
          >
            <ArrowDownToLine className="w-4 h-4" />
            {depositing ? 'Depositing…' : 'Deposit to vault'}
          </motion.button>
          <p className="text-xs text-zinc-500 leading-relaxed">
            The deposit transaction is public (one-time) but afterwards your
            balance and outgoing transfers are encrypted on-chain.
          </p>
        </div>
      </motion.div>
    </>
  );
}
___F_PAGE_DEPOSIT___

# =============================================================================
# app/(app)/receive/page.tsx
# =============================================================================
cat > "app/(app)/receive/page.tsx" << '___F_PAGE_RECEIVE___'
'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { useShielded } from '@/lib/useShielded';
import { useToast } from '@/components/Toast';
import { PageHeader } from '@/components/PageHeader';
import { Copy, Check } from 'lucide-react';

export default function ReceivePage() {
  const { address } = useShielded();
  const toast = useToast();
  const [copied, setCopied] = useState(false);

  const copy = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true);
    toast.push({ kind: 'info', title: 'Address copied' });
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <>
      <PageHeader
        title="Receive"
        subtitle="Share your address to receive shielded transfers."
      />

      <motion.div
        initial={{ opacity: 0, scale: 0.9, rotateY: 8 }}
        animate={{ opacity: 1, scale: 1, rotateY: 0 }}
        transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
        className="max-w-md bg-zinc-900/60 border border-zinc-800 rounded-2xl p-8 backdrop-blur"
      >
        {address ? (
          <>
            <div className="flex justify-center mb-6">
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.2 }}
                className="p-4 bg-white rounded-2xl"
              >
                <QRCodeSVG value={address} size={200} level="H" />
              </motion.div>
            </div>
            <div className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-2">
              Your address
            </div>
            <div className="font-mono text-xs break-all text-zinc-200 bg-zinc-950/60 border border-zinc-800 rounded-lg p-3 mb-3">
              {address}
            </div>
            <button
              onClick={copy}
              className="w-full py-2.5 bg-zinc-800 hover:bg-zinc-700 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
            >
              {copied ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              {copied ? 'Copied' : 'Copy address'}
            </button>
          </>
        ) : (
          <div className="text-zinc-500 text-sm text-center py-12">
            Wallet not connected yet.
          </div>
        )}
      </motion.div>
    </>
  );
}
___F_PAGE_RECEIVE___

# =============================================================================
# app/(app)/history/page.tsx
# =============================================================================
cat > "app/(app)/history/page.tsx" << '___F_PAGE_HISTORY___'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { useShielded } from '@/lib/useShielded';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import {
  ArrowDownLeft,
  ArrowUpRight,
  ArrowDownToLine,
  ArrowUpFromLine,
  EyeOff,
} from 'lucide-react';

function timeAgo(ts?: number) {
  if (!ts) return '';
  const diff = (Date.now() - ts) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

const styles: Record<HistoryEvent['type'], { icon: typeof ArrowDownLeft; colour: string; label: string }> = {
  deposit: { icon: ArrowDownToLine, colour: 'text-emerald-400 bg-emerald-950/40 border-emerald-900/40', label: 'Deposit' },
  withdraw: { icon: ArrowUpFromLine, colour: 'text-amber-400 bg-amber-950/40 border-amber-900/40', label: 'Withdraw' },
  send: { icon: ArrowUpRight, colour: 'text-red-400 bg-red-950/40 border-red-900/40', label: 'Sent' },
  receive: { icon: ArrowDownLeft, colour: 'text-violet-400 bg-violet-950/40 border-violet-900/40', label: 'Received' },
};

export default function HistoryPage() {
  const { address } = useShielded();
  const [events, setEvents] = useState<HistoryEvent[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!address) return;
      setLoading(true);
      try {
        const evts = await fetchHistory(address);
        if (!cancelled) {
          setEvents(evts);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'fetch failed');
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [address]);

  return (
    <>
      <PageHeader
        title="Activity"
        subtitle="On-chain events involving your address. Amounts stay hidden — that's the whole point."
      />

      <div className="bg-zinc-900/60 border border-zinc-800 rounded-2xl backdrop-blur overflow-hidden">
        {loading ? (
          <div className="p-6 space-y-2">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-14 shimmer rounded-lg" />
            ))}
          </div>
        ) : error ? (
          <div className="p-8 text-sm text-red-400">Error: {error}</div>
        ) : !events || events.length === 0 ? (
          <div className="p-12 text-center">
            <EyeOff className="w-8 h-8 text-zinc-700 mx-auto mb-3" />
            <div className="text-sm text-zinc-500">No activity yet.</div>
            <div className="text-xs text-zinc-600 mt-1">
              Deposits and transfers will appear here.
            </div>
          </div>
        ) : (
          <motion.ul
            initial="hidden"
            animate="show"
            variants={{
              hidden: {},
              show: { transition: { staggerChildren: 0.04 } },
            }}
            className="divide-y divide-zinc-800/50"
          >
            {events.map((ev) => {
              const s = styles[ev.type];
              const Icon = s.icon;
              return (
                <motion.li
                  key={ev.txHash}
                  variants={{
                    hidden: { opacity: 0, y: 8 },
                    show: { opacity: 1, y: 0 },
                  }}
                  className="flex items-center gap-4 px-5 py-4 hover:bg-zinc-900/40 transition-colors"
                >
                  <div className={`w-9 h-9 rounded-lg border flex items-center justify-center ${s.colour}`}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium">{s.label}</div>
                    {ev.counterparty && (
                      <div className="text-xs font-mono text-zinc-500 truncate">
                        {ev.type === 'send' ? '→ ' : '← '}
                        {ev.counterparty.slice(0, 8)}…{ev.counterparty.slice(-6)}
                      </div>
                    )}
                  </div>
                  <div className="text-right">
                    <div className="text-xs text-zinc-500">
                      {timeAgo(ev.timestamp)}
                    </div>
                    <div className="text-[10px] font-mono text-zinc-700 mt-0.5">
                      {ev.txHash.slice(0, 10)}…
                    </div>
                  </div>
                </motion.li>
              );
            })}
          </motion.ul>
        )}
      </div>
    </>
  );
}
___F_PAGE_HISTORY___

# =============================================================================
# app/(app)/portfolio/page.tsx
# =============================================================================
cat > "app/(app)/portfolio/page.tsx" << '___F_PAGE_PORTFOLIO___'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { formatEther } from 'viem';
import { useShielded } from '@/lib/useShielded';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { seismicPay } from '@/lib/contract';
import { PageHeader } from '@/components/PageHeader';
import { NumberCounter } from '@/components/NumberCounter';

export default function PortfolioPage() {
  const { walletClient, account, address, ready } = useShielded();
  const [balance, setBalance] = useState<number | null>(null);
  const [events, setEvents] = useState<HistoryEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!ready || !walletClient || !account || !address) return;
      setLoading(true);
      try {
        const contract = getShieldedContract({
          ...seismicPay,
          client: walletClient,
        });
        const bal = (await contract.read.balanceOf([account.address])) as bigint;
        const evts = await fetchHistory(address);
        if (!cancelled) {
          setBalance(parseFloat(formatEther(bal)));
          setEvents(evts);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [ready, walletClient, account, address]);

  const stats = {
    deposits: events.filter((e) => e.type === 'deposit').length,
    sends: events.filter((e) => e.type === 'send').length,
    receives: events.filter((e) => e.type === 'receive').length,
    total: events.length,
  };

  return (
    <>
      <PageHeader
        title="Portfolio"
        subtitle="Overview of your shielded position."
      />

      <motion.div
        initial={{ opacity: 0, rotate: -1, scale: 0.98 }}
        animate={{ opacity: 1, rotate: 0, scale: 1 }}
        transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
        className="bg-gradient-to-br from-violet-950/40 via-zinc-900/60 to-zinc-900/60 border border-violet-900/30 rounded-2xl p-8 mb-6"
      >
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-2">
          Total shielded value
        </div>
        <div className="text-5xl font-light tracking-tight">
          {balance === null ? '—' : <NumberCounter value={balance} decimals={4} />}
          <span className="text-2xl text-zinc-500 ml-2">ETH</span>
        </div>
      </motion.div>

      <motion.div
        initial="hidden"
        animate="show"
        variants={{
          hidden: {},
          show: { transition: { staggerChildren: 0.06, delayChildren: 0.2 } },
        }}
        className="grid grid-cols-2 md:grid-cols-4 gap-3"
      >
        {[
          { label: 'Deposits', value: stats.deposits, color: 'text-emerald-400' },
          { label: 'Sent', value: stats.sends, color: 'text-red-400' },
          { label: 'Received', value: stats.receives, color: 'text-violet-400' },
          { label: 'Total events', value: stats.total, color: 'text-zinc-300' },
        ].map((s) => (
          <motion.div
            key={s.label}
            variants={{
              hidden: { opacity: 0, y: 12 },
              show: { opacity: 1, y: 0 },
            }}
            className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-5"
          >
            <div className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-1.5">
              {s.label}
            </div>
            <div className={`text-3xl font-light ${s.color}`}>
              {loading ? '…' : s.value}
            </div>
          </motion.div>
        ))}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
        className="mt-8 p-6 bg-zinc-900/40 border border-zinc-800 rounded-2xl"
      >
        <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-2">
          Privacy notice
        </div>
        <p className="text-sm text-zinc-400 leading-relaxed">
          Counts above are derived from public on-chain events. Amounts per
          transaction are encrypted and only visible to you. This is the
          Seismic privacy model: <em>fact of transaction is public, value is not</em>.
        </p>
      </motion.div>
    </>
  );
}
___F_PAGE_PORTFOLIO___

# =============================================================================
# app/(app)/trading/page.tsx — honest stub
# =============================================================================
cat > "app/(app)/trading/page.tsx" << '___F_PAGE_TRADING___'
'use client';

import { motion } from 'framer-motion';
import { PageHeader } from '@/components/PageHeader';
import { ArrowLeftRight, GitBranch } from 'lucide-react';

export default function TradingPage() {
  return (
    <>
      <PageHeader
        title="Trade"
        subtitle="Shielded swaps — landing in the next phase."
      />

      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-8 backdrop-blur max-w-2xl"
      >
        <div className="w-12 h-12 rounded-xl bg-violet-950/50 border border-violet-900/50 flex items-center justify-center mb-5">
          <ArrowLeftRight className="w-5 h-5 text-violet-400" />
        </div>
        <h2 className="text-2xl mb-2">Honest status</h2>
        <p className="text-sm text-zinc-400 leading-relaxed mb-6">
          A real swap UI needs a real AMM contract on Seismic. We have a
          SeismicPay vault (deposit / transfer / balance) — that&apos;s it.
          A token pair + constant-product pool with shielded reserves is the next
          piece of contract work.
        </p>

        <div className="border-t border-zinc-800 pt-5 mb-5">
          <div className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-3">
            What ships in Phase 5
          </div>
          <ul className="space-y-2 text-sm text-zinc-300">
            <li className="flex items-start gap-2">
              <GitBranch className="w-3.5 h-3.5 text-violet-400 mt-1 shrink-0" />
              <span>SimpleSwap.sol — Uniswap-V2-style AMM with shielded reserves</span>
            </li>
            <li className="flex items-start gap-2">
              <GitBranch className="w-3.5 h-3.5 text-violet-400 mt-1 shrink-0" />
              <span>Two demo SRC20 tokens to swap between</span>
            </li>
            <li className="flex items-start gap-2">
              <GitBranch className="w-3.5 h-3.5 text-violet-400 mt-1 shrink-0" />
              <span>AI tools: <code className="text-xs font-mono text-violet-300">swap</code>, <code className="text-xs font-mono text-violet-300">add_liquidity</code>, <code className="text-xs font-mono text-violet-300">get_price</code></span>
            </li>
            <li className="flex items-start gap-2">
              <GitBranch className="w-3.5 h-3.5 text-violet-400 mt-1 shrink-0" />
              <span>This page becomes the trade form, wired to those contracts</span>
            </li>
          </ul>
        </div>

        <p className="text-xs text-zinc-600 leading-relaxed">
          I&apos;m not faking the UI in the meantime — a swap form that doesn&apos;t
          actually swap is worse than no swap form.
        </p>
      </motion.div>
    </>
  );
}
___F_PAGE_TRADING___

# =============================================================================
# app/(app)/settings/page.tsx
# =============================================================================
cat > "app/(app)/settings/page.tsx" << '___F_PAGE_SETTINGS___'
'use client';

import { motion } from 'framer-motion';
import { usePrivy } from '@privy-io/react-auth';
import { useChainId } from 'wagmi';
import { sanvil } from 'seismic-viem';
import { PageHeader } from '@/components/PageHeader';
import { LogOut } from 'lucide-react';

export default function SettingsPage() {
  const { user, logout } = usePrivy();
  const chainId = useChainId();

  const rows = [
    {
      label: 'Email',
      value: user?.email?.address || 'not linked',
    },
    {
      label: 'Wallet',
      value: user?.wallet?.address || '—',
      mono: true,
    },
    {
      label: 'Network',
      value: chainId === sanvil.id ? 'Seismic Local (31337)' : `Chain ${chainId}`,
    },
    {
      label: 'Account created',
      value: user?.createdAt
        ? new Date(user.createdAt).toLocaleDateString()
        : '—',
    },
  ];

  return (
    <>
      <PageHeader title="Settings" subtitle="Your account and connection." />

      <motion.div
        initial={{ opacity: 0, x: -16 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="max-w-2xl space-y-4"
      >
        <div className="bg-zinc-900/60 border border-zinc-800 rounded-2xl backdrop-blur overflow-hidden">
          {rows.map((r, i) => (
            <div
              key={r.label}
              className={`px-6 py-4 ${i > 0 ? 'border-t border-zinc-800/60' : ''} flex items-center justify-between`}
            >
              <div className="text-xs uppercase tracking-[0.15em] text-zinc-500">
                {r.label}
              </div>
              <div
                className={`text-sm text-zinc-200 break-all text-right max-w-[60%] ${r.mono ? 'font-mono text-xs' : ''}`}
              >
                {r.value}
              </div>
            </div>
          ))}
        </div>

        <motion.button
          whileHover={{ scale: 1.01 }}
          whileTap={{ scale: 0.99 }}
          onClick={logout}
          className="w-full px-6 py-3.5 bg-red-950/40 hover:bg-red-950/60 border border-red-900/50 rounded-2xl text-red-300 text-sm font-medium transition-colors flex items-center justify-center gap-2"
        >
          <LogOut className="w-4 h-4" />
          Sign out
        </motion.button>
      </motion.div>
    </>
  );
}
___F_PAGE_SETTINGS___

echo ""
echo "✓ All Phase 4 files written."
echo ""
echo "What's new:"
echo "  · Multi-page app with sidebar nav"
echo "  · Routes: /dashboard /send /deposit /receive /history /portfolio /trading /settings"
echo "  · Custom shielded wallet hook (bridges Privy → seismic-viem directly)"
echo "  · Floating AI chat button on every page"
echo "  · Real on-chain event history"
echo "  · Toast notifications on tx success/failure"
echo "  · Premium typography: Instrument Serif + Geist + JetBrains Mono"
echo "  · Per-route entrance animations"
echo ""
echo "Restart: Ctrl+C the 'npm run dev' terminal, then 'npm run dev'"
echo "Then open: http://localhost:3000/dashboard"
