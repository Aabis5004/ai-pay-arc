#!/usr/bin/env bash
# apply-phase-5.sh
# Phase 5 — full functional shielded wallet + premium UX
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Installing dependencies…"
npm install --silent 2>&1 | tail -5 || true

mkdir -p lib components

# =============================================================================
# lib/explorer.ts
# =============================================================================
cat > lib/explorer.ts << '___F_EXPLORER___'
import { sanvil } from 'seismic-viem';

export function explorerTxUrl(hash: string, chainId: number): string | null {
  if (chainId === sanvil.id) return null;
  if (chainId === 5124) return `https://explorer-2.seismicdev.net/tx/${hash}`;
  return null;
}

export function explorerAddressUrl(addr: string, chainId: number): string | null {
  if (chainId === sanvil.id) return null;
  if (chainId === 5124) return `https://explorer-2.seismicdev.net/address/${addr}`;
  return null;
}
___F_EXPLORER___

# =============================================================================
# lib/useShielded.ts — multi-strategy bridge with diagnostics
# =============================================================================
cat > lib/useShielded.ts << '___F_USESHIELDED___'
'use client';

import { useEffect, useState } from 'react';
import { useWallets } from '@privy-io/react-auth';
import { useAccount, useChainId, useWalletClient } from 'wagmi';
import { createShieldedWalletClient, sanvil } from 'seismic-viem';
import { custom, type Address } from 'viem';

/* eslint-disable @typescript-eslint/no-explicit-any */
type ShieldedClient = any;
/* eslint-enable @typescript-eslint/no-explicit-any */

type Diag = {
  isConnected: boolean;
  address?: string;
  chainId?: number;
  expectedChainId: number;
  privyWalletsCount: number;
  hasWagmiClient: boolean;
  strategyUsed?: string;
  error?: string;
};

export function useShielded() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { wallets } = useWallets();
  const { data: wagmiClient } = useWalletClient();

  const [walletClient, setWalletClient] = useState<ShieldedClient | null>(null);
  const [diag, setDiag] = useState<Diag>({
    isConnected: false,
    expectedChainId: sanvil.id,
    privyWalletsCount: 0,
    hasWagmiClient: false,
  });

  useEffect(() => {
    let cancelled = false;
    const base: Diag = {
      isConnected,
      address,
      chainId,
      expectedChainId: sanvil.id,
      privyWalletsCount: wallets.length,
      hasWagmiClient: !!wagmiClient,
    };
    setDiag(base);

    async function init() {
      if (!isConnected || !address) {
        setWalletClient(null);
        return;
      }
      if (chainId !== sanvil.id) {
        setWalletClient(null);
        setDiag((d) => ({ ...d, error: `Wrong chain: ${chainId}` }));
        return;
      }

      const attempts: Array<{
        name: string;
        run: () => Promise<ShieldedClient>;
      }> = [];

      if (wallets.length > 0) {
        attempts.push({
          name: 'privy',
          run: async () => {
            const provider = await wallets[0].getEthereumProvider();
            return createShieldedWalletClient({
              chain: sanvil,
              transport: custom(provider),
              account: address as Address,
            });
          },
        });
      }
      if (wagmiClient) {
        attempts.push({
          name: 'wagmi',
          run: () =>
            createShieldedWalletClient({
              chain: sanvil,
              transport: custom(wagmiClient.transport),
              account: address as Address,
            }),
        });
      }
      if (typeof window !== 'undefined') {
        const eth = (window as { ethereum?: unknown }).ethereum;
        if (eth) {
          attempts.push({
            name: 'window',
            run: () =>
              createShieldedWalletClient({
                chain: sanvil,
                transport: custom(eth as Parameters<typeof custom>[0]),
                account: address as Address,
              }),
          });
        }
      }

      for (const attempt of attempts) {
        if (cancelled) return;
        try {
          console.log(`[useShielded] try ${attempt.name}`);
          const c = await attempt.run();
          if (cancelled) return;
          console.log(`[useShielded] ✓ ${attempt.name} succeeded`);
          setWalletClient(c);
          setDiag((d) => ({
            ...d,
            strategyUsed: attempt.name,
            error: undefined,
          }));
          return;
        } catch (e) {
          console.error(`[useShielded] ${attempt.name} failed:`, e);
          setDiag((d) => ({
            ...d,
            error: `${attempt.name}: ${e instanceof Error ? e.message : String(e)}`,
          }));
        }
      }

      if (!cancelled) setWalletClient(null);
    }

    init();
    return () => {
      cancelled = true;
    };
  }, [address, isConnected, chainId, wallets, wagmiClient]);

  return {
    walletClient,
    account: address ? ({ address: address as Address } as const) : null,
    address: address as Address | undefined,
    ready: !!walletClient,
    chainId,
    diagnostic: diag,
    error: diag.error,
  };
}
___F_USESHIELDED___

# =============================================================================
# lib/history.ts
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

  try {
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
  } catch {
    /* event might not exist yet */
  }

  try {
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
  } catch {
    /* ignore */
  }

  try {
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
  } catch {
    /* ignore */
  }

  try {
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
  } catch {
    /* ignore */
  }

  events.sort((a, b) => Number(b.blockNumber - a.blockNumber));

  const top = events.slice(0, 60);
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

export async function waitForTx(hash: Hash) {
  return publicClient.waitForTransactionReceipt({ hash });
}
___F_HISTORY___

# =============================================================================
# components/Particles.tsx
# =============================================================================
cat > components/Particles.tsx << '___F_PARTICLES___'
'use client';

import { useEffect, useRef } from 'react';

export function Particles({ density = 40 }: { density?: number }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let w = (canvas.width = window.innerWidth);
    let h = (canvas.height = window.innerHeight);
    const dpr = window.devicePixelRatio || 1;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    ctx.scale(dpr, dpr);

    const particles = Array.from({ length: density }, () => ({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: (Math.random() - 0.5) * 0.15,
      vy: (Math.random() - 0.5) * 0.15,
      r: Math.random() * 1.2 + 0.4,
    }));

    let raf = 0;
    const tick = () => {
      ctx.clearRect(0, 0, w, h);

      // connections
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const a = particles[i];
          const b = particles[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const d = Math.sqrt(dx * dx + dy * dy);
          if (d < 120) {
            ctx.beginPath();
            ctx.strokeStyle = `rgba(124, 58, 237, ${0.06 * (1 - d / 120)})`;
            ctx.lineWidth = 0.5;
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }

      // particles
      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0 || p.x > w) p.vx *= -1;
        if (p.y < 0 || p.y > h) p.vy *= -1;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(180, 160, 255, 0.35)';
        ctx.fill();
      }

      raf = requestAnimationFrame(tick);
    };
    tick();

    const onResize = () => {
      w = window.innerWidth;
      h = window.innerHeight;
      canvas.width = w * dpr;
      canvas.height = h * dpr;
      canvas.style.width = `${w}px`;
      canvas.style.height = `${h}px`;
      ctx.scale(dpr, dpr);
    };
    window.addEventListener('resize', onResize);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
    };
  }, [density]);

  return (
    <canvas
      ref={canvasRef}
      className="fixed inset-0 pointer-events-none z-0 opacity-60"
      aria-hidden
    />
  );
}
___F_PARTICLES___

# =============================================================================
# components/BalanceCard.tsx — with error surface + diagnostics
# =============================================================================
cat > components/BalanceCard.tsx << '___F_BAL___'
'use client';

import { motion } from 'framer-motion';
import { useCallback, useEffect, useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { formatEther } from 'viem';
import { RefreshCw, EyeOff, AlertCircle } from 'lucide-react';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { NumberCounter } from './NumberCounter';

export function BalanceCard() {
  const { walletClient, account, ready, error: bridgeError, diagnostic } =
    useShielded();
  const [balance, setBalance] = useState<number | null>(null);
  const [readError, setReadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [hidden, setHidden] = useState(false);

  const refresh = useCallback(async () => {
    if (!walletClient || !account) return;
    setLoading(true);
    setReadError(null);
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      const bal = (await contract.read.balanceOf([account.address])) as bigint;
      setBalance(parseFloat(formatEther(bal)));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('balance read failed:', e);
      setReadError(msg.slice(0, 200));
      setBalance(null);
    } finally {
      setLoading(false);
    }
  }, [walletClient, account]);

  useEffect(() => {
    if (ready) refresh();
  }, [ready, refresh]);

  // Auto-refresh every 10 seconds when ready
  useEffect(() => {
    if (!ready) return;
    const interval = setInterval(refresh, 10000);
    return () => clearInterval(interval);
  }, [ready, refresh]);

  const surfaceError = bridgeError || readError;
  const stateLabel = (() => {
    if (!diagnostic.isConnected) return 'wallet not connected';
    if (diagnostic.chainId !== diagnostic.expectedChainId)
      return `wrong chain · ${diagnostic.chainId ?? '?'}`;
    if (!ready) return 'connecting…';
    return null;
  })();

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
              disabled={loading || !ready}
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

        {stateLabel && !surfaceError && (
          <div className="mt-4 text-[11px] text-amber-400/70">
            · {stateLabel}
          </div>
        )}

        {surfaceError && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            className="mt-4 p-3 bg-red-950/30 border border-red-900/40 rounded-lg"
          >
            <div className="flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-red-400 mt-0.5 shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="text-xs font-medium text-red-300 mb-1">
                  Bridge error — paste this to Claude:
                </div>
                <div className="text-[11px] text-red-200/80 font-mono break-all">
                  {surfaceError}
                </div>
                <div className="text-[10px] text-red-300/50 mt-2">
                  tried: {diagnostic.strategyUsed || 'none'} · chain{' '}
                  {diagnostic.chainId} · wallets{' '}
                  {diagnostic.privyWalletsCount}
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </div>
    </motion.div>
  );
}
___F_BAL___

# =============================================================================
# components/TxStatusModal.tsx — production-grade tx flow modal
# =============================================================================
cat > components/TxStatusModal.tsx << '___F_TXMODAL___'
'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { CheckCircle2, XCircle, Loader2, ExternalLink } from 'lucide-react';
import { useChainId } from 'wagmi';
import { explorerTxUrl } from '@/lib/explorer';

export type TxStatus =
  | { state: 'idle' }
  | { state: 'preparing'; summary: string }
  | { state: 'signing'; summary: string }
  | { state: 'broadcasting'; summary: string }
  | { state: 'confirming'; summary: string; hash: string }
  | { state: 'confirmed'; summary: string; hash: string }
  | { state: 'failed'; summary: string; error: string };

export function TxStatusModal({
  status,
  onClose,
}: {
  status: TxStatus;
  onClose: () => void;
}) {
  const chainId = useChainId();
  const open = status.state !== 'idle';

  const hash =
    'hash' in status && status.hash ? status.hash : null;
  const explorerUrl = hash ? explorerTxUrl(hash, chainId) : null;

  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm"
            onClick={status.state === 'confirmed' || status.state === 'failed' ? onClose : undefined}
          />
          <motion.div
            initial={{ opacity: 0, y: 20, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.96 }}
            transition={{ type: 'spring', stiffness: 320, damping: 28 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none"
          >
            <div className="w-full max-w-md bg-zinc-900 border border-zinc-800 rounded-2xl p-6 pointer-events-auto shadow-2xl">
              <StatusIcon status={status} />
              <div className="text-center mt-4">
                <div className="text-sm font-medium text-zinc-100">
                  {statusTitle(status)}
                </div>
                <div className="text-xs text-zinc-500 mt-1">
                  {'summary' in status ? status.summary : ''}
                </div>
              </div>

              {hash && (
                <div className="mt-5 p-3 bg-zinc-950/60 border border-zinc-800 rounded-lg">
                  <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mb-1">
                    Transaction
                  </div>
                  <div className="text-[11px] font-mono text-zinc-300 break-all">
                    {hash}
                  </div>
                  {explorerUrl && (
                    <a
                      href={explorerUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 mt-2 text-xs text-violet-400 hover:text-violet-300"
                    >
                      View on explorer <ExternalLink className="w-3 h-3" />
                    </a>
                  )}
                </div>
              )}

              {status.state === 'failed' && (
                <div className="mt-4 p-3 bg-red-950/30 border border-red-900/40 rounded-lg">
                  <div className="text-[11px] font-mono text-red-300 break-all">
                    {status.error}
                  </div>
                </div>
              )}

              {(status.state === 'confirmed' || status.state === 'failed') && (
                <button
                  onClick={onClose}
                  className="w-full mt-5 py-2.5 bg-zinc-800 hover:bg-zinc-700 rounded-lg text-sm font-medium transition-colors"
                >
                  Done
                </button>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}

function StatusIcon({ status }: { status: TxStatus }) {
  if (status.state === 'confirmed')
    return (
      <div className="flex justify-center">
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: 'spring', stiffness: 260, damping: 20 }}
          className="w-14 h-14 rounded-full bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center"
        >
          <CheckCircle2 className="w-7 h-7 text-emerald-400" />
        </motion.div>
      </div>
    );
  if (status.state === 'failed')
    return (
      <div className="flex justify-center">
        <div className="w-14 h-14 rounded-full bg-red-500/15 border border-red-500/30 flex items-center justify-center">
          <XCircle className="w-7 h-7 text-red-400" />
        </div>
      </div>
    );
  return (
    <div className="flex justify-center">
      <div className="w-14 h-14 rounded-full bg-violet-500/15 border border-violet-500/30 flex items-center justify-center">
        <Loader2 className="w-7 h-7 text-violet-400 animate-spin" />
      </div>
    </div>
  );
}

function statusTitle(s: TxStatus): string {
  switch (s.state) {
    case 'preparing':
      return 'Preparing transaction';
    case 'signing':
      return 'Confirm in your wallet';
    case 'broadcasting':
      return 'Broadcasting to network';
    case 'confirming':
      return 'Confirming on chain';
    case 'confirmed':
      return 'Transaction confirmed';
    case 'failed':
      return 'Transaction failed';
    default:
      return '';
  }
}
___F_TXMODAL___

# =============================================================================
# components/AllocationDonut.tsx
# =============================================================================
cat > components/AllocationDonut.tsx << '___F_DONUT___'
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
___F_DONUT___

# =============================================================================
# components/Sidebar.tsx — with mobile toggle support
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

export function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { user, logout } = usePrivy();
  const chainId = useChainId();
  const onCorrectChain = chainId === sanvil.id;

  return (
    <aside className="w-60 h-full border-r border-zinc-900 bg-zinc-950/80 backdrop-blur p-5 flex flex-col">
      <div className="mb-8">
        <Link href="/dashboard" className="block" onClick={onNavigate}>
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
            <Link
              key={item.href}
              href={item.href}
              className="block"
              onClick={onNavigate}
            >
              <motion.div
                className={`relative flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                  active ? 'text-white' : 'text-zinc-500 hover:text-zinc-200'
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
            {onCorrectChain ? 'Seismic Local' : `Chain ${chainId || '?'}`}
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
# app/(app)/layout.tsx — responsive with mobile drawer
# =============================================================================
cat > "app/(app)/layout.tsx" << '___F_APPLAYOUT___'
'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter, usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Menu, X } from 'lucide-react';
import { Sidebar } from '@/components/Sidebar';
import { ChatFloater } from '@/components/ChatFloater';
import { NetworkGate } from '@/components/NetworkGate';
import { Particles } from '@/components/Particles';

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { ready, authenticated } = usePrivy();
  const router = useRouter();
  const pathname = usePathname();
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    if (ready && !authenticated) router.replace('/');
  }, [ready, authenticated, router]);

  useEffect(() => {
    setDrawerOpen(false);
  }, [pathname]);

  if (!ready || !authenticated) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <>
      <Particles density={28} />
      <div className="relative z-10 flex min-h-screen">
        {/* Desktop sidebar */}
        <div className="hidden md:block w-60 shrink-0">
          <div className="fixed top-0 left-0 w-60 h-screen">
            <Sidebar />
          </div>
        </div>

        {/* Mobile drawer */}
        <AnimatePresence>
          {drawerOpen && (
            <>
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onClick={() => setDrawerOpen(false)}
                className="fixed inset-0 z-40 bg-black/60 md:hidden"
              />
              <motion.div
                initial={{ x: -240 }}
                animate={{ x: 0 }}
                exit={{ x: -240 }}
                transition={{ type: 'spring', stiffness: 320, damping: 30 }}
                className="fixed top-0 left-0 z-50 h-screen w-60 md:hidden"
              >
                <Sidebar onNavigate={() => setDrawerOpen(false)} />
              </motion.div>
            </>
          )}
        </AnimatePresence>

        <main className="flex-1 overflow-y-auto">
          {/* Mobile menu button */}
          <div className="md:hidden sticky top-0 z-30 bg-zinc-950/80 backdrop-blur border-b border-zinc-900 px-4 py-3 flex items-center gap-3">
            <button
              onClick={() => setDrawerOpen(true)}
              className="p-2 -ml-2 hover:bg-zinc-900 rounded-lg transition-colors"
              aria-label="Open menu"
            >
              {drawerOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
            <h1 className="text-sm tracking-tight">
              AI Pay{' '}
              <span
                className="text-violet-400"
                style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}
              >
                Seismic
              </span>
            </h1>
          </div>

          <div className="max-w-5xl mx-auto px-4 md:px-8 py-6 md:py-10">
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
    </>
  );
}
___F_APPLAYOUT___

# =============================================================================
# app/(app)/send/page.tsx — with tx modal
# =============================================================================
cat > "app/(app)/send/page.tsx" << '___F_SEND___'
'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { parseEther, type Address, isAddress } from 'viem';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { waitForTx } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import { TxStatusModal, type TxStatus } from '@/components/TxStatusModal';
import { Send as SendIcon } from 'lucide-react';

export default function SendPage() {
  const { walletClient, account, ready } = useShielded();
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState<TxStatus>({ state: 'idle' });

  const valid = isAddress(to) && parseFloat(amount) > 0;
  const summary = valid ? `${amount} ETH → ${to.slice(0, 8)}…${to.slice(-6)}` : '';

  const submit = async () => {
    if (!valid || !walletClient || !account) return;
    setStatus({ state: 'preparing', summary });
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      setStatus({ state: 'signing', summary });
      const hash = (await contract.write.transfer([
        to as Address,
        parseEther(amount),
      ])) as string;
      setStatus({ state: 'confirming', summary, hash });
      await waitForTx(hash as `0x${string}`);
      setStatus({ state: 'confirmed', summary, hash });
      setTo('');
      setAmount('');
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'failed';
      setStatus({ state: 'failed', summary, error: msg.slice(0, 200) });
    }
  };

  return (
    <>
      <PageHeader
        title="Send"
        subtitle="Shielded transfer to another address. Amount stays private on-chain."
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
              className={`w-full bg-zinc-800/60 border ${
                to && !isAddress(to)
                  ? 'border-red-800/60'
                  : 'border-zinc-700'
              } rounded-lg px-4 py-3 font-mono text-sm focus:outline-none focus:border-violet-500 transition-colors`}
            />
            {to && !isAddress(to) && (
              <div className="text-[11px] text-red-400 mt-1.5">
                Not a valid 0x-address
              </div>
            )}
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
            disabled={!valid || !ready}
            onClick={submit}
            className="w-full py-3 bg-violet-600 hover:bg-violet-500 disabled:bg-zinc-800 disabled:text-zinc-500 rounded-xl font-medium transition-colors flex items-center justify-center gap-2"
          >
            <SendIcon className="w-4 h-4" />
            Send shielded
          </motion.button>
        </div>
      </motion.div>

      <TxStatusModal
        status={status}
        onClose={() => setStatus({ state: 'idle' })}
      />
    </>
  );
}
___F_SEND___

# =============================================================================
# app/(app)/deposit/page.tsx — with tx modal
# =============================================================================
cat > "app/(app)/deposit/page.tsx" << '___F_DEPOSIT___'
'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { getShieldedContract } from 'seismic-viem';
import { parseEther } from 'viem';
import { seismicPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { waitForTx } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import { TxStatusModal, type TxStatus } from '@/components/TxStatusModal';
import { ArrowDownToLine } from 'lucide-react';

const quickAmounts = ['0.1', '0.5', '1', '5'];

export default function DepositPage() {
  const { walletClient, account, ready } = useShielded();
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState<TxStatus>({ state: 'idle' });

  const valid = parseFloat(amount) > 0;
  const summary = valid ? `Deposit ${amount} ETH to shielded vault` : '';

  const submit = async () => {
    if (!valid || !walletClient || !account) return;
    setStatus({ state: 'preparing', summary });
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      setStatus({ state: 'signing', summary });
      const hash = (await contract.write.deposit({
        value: parseEther(amount),
      })) as string;
      setStatus({ state: 'confirming', summary, hash });
      await waitForTx(hash as `0x${string}`);
      setStatus({ state: 'confirmed', summary, hash });
      setAmount('');
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'failed';
      setStatus({ state: 'failed', summary, error: msg.slice(0, 200) });
    }
  };

  return (
    <>
      <PageHeader
        title="Deposit"
        subtitle="Move native ETH into the shielded vault. After this, your balance is private."
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
            disabled={!valid || !ready}
            onClick={submit}
            className="w-full py-3 bg-violet-600 hover:bg-violet-500 disabled:bg-zinc-800 disabled:text-zinc-500 rounded-xl font-medium transition-colors flex items-center justify-center gap-2"
          >
            <ArrowDownToLine className="w-4 h-4" />
            Deposit to vault
          </motion.button>
        </div>
      </motion.div>

      <TxStatusModal
        status={status}
        onClose={() => setStatus({ state: 'idle' })}
      />
    </>
  );
}
___F_DEPOSIT___

# =============================================================================
# app/(app)/receive/page.tsx — with share
# =============================================================================
cat > "app/(app)/receive/page.tsx" << '___F_RECEIVE___'
'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { useShielded } from '@/lib/useShielded';
import { useToast } from '@/components/Toast';
import { PageHeader } from '@/components/PageHeader';
import { Copy, Check, Share2 } from 'lucide-react';

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

  const share = async () => {
    if (!address) return;
    if (typeof navigator !== 'undefined' && (navigator as Navigator & { share?: (data: ShareData) => Promise<void> }).share) {
      try {
        await (navigator as Navigator & { share: (data: ShareData) => Promise<void> }).share({
          title: 'My AI Pay Seismic address',
          text: `Send me shielded ETH on Seismic: ${address}`,
        });
      } catch {
        /* user cancelled */
      }
    } else {
      copy();
    }
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
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={copy}
                className="py-2.5 bg-zinc-800 hover:bg-zinc-700 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
              >
                {copied ? (
                  <Check className="w-4 h-4 text-emerald-400" />
                ) : (
                  <Copy className="w-4 h-4" />
                )}
                {copied ? 'Copied' : 'Copy'}
              </button>
              <button
                onClick={share}
                className="py-2.5 bg-violet-600 hover:bg-violet-500 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
              >
                <Share2 className="w-4 h-4" />
                Share
              </button>
            </div>
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
___F_RECEIVE___

# =============================================================================
# app/(app)/history/page.tsx — with explorer links + pending
# =============================================================================
cat > "app/(app)/history/page.tsx" << '___F_HISTORY___'
'use client';

import { motion } from 'framer-motion';
import { useCallback, useEffect, useState } from 'react';
import { useChainId } from 'wagmi';
import { useShielded } from '@/lib/useShielded';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { explorerTxUrl } from '@/lib/explorer';
import { PageHeader } from '@/components/PageHeader';
import {
  ArrowDownLeft,
  ArrowUpRight,
  ArrowDownToLine,
  ArrowUpFromLine,
  EyeOff,
  ExternalLink,
  RefreshCw,
} from 'lucide-react';

function timeAgo(ts?: number) {
  if (!ts) return '';
  const diff = (Date.now() - ts) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

const styles: Record<
  HistoryEvent['type'],
  { icon: typeof ArrowDownLeft; colour: string; label: string }
> = {
  deposit: {
    icon: ArrowDownToLine,
    colour: 'text-emerald-400 bg-emerald-950/40 border-emerald-900/40',
    label: 'Deposit',
  },
  withdraw: {
    icon: ArrowUpFromLine,
    colour: 'text-amber-400 bg-amber-950/40 border-amber-900/40',
    label: 'Withdraw',
  },
  send: {
    icon: ArrowUpRight,
    colour: 'text-red-400 bg-red-950/40 border-red-900/40',
    label: 'Sent',
  },
  receive: {
    icon: ArrowDownLeft,
    colour: 'text-violet-400 bg-violet-950/40 border-violet-900/40',
    label: 'Received',
  },
};

export default function HistoryPage() {
  const { address } = useShielded();
  const chainId = useChainId();
  const [events, setEvents] = useState<HistoryEvent[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!address) return;
    setLoading(true);
    try {
      const evts = await fetchHistory(address);
      setEvents(evts);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'fetch failed');
    } finally {
      setLoading(false);
    }
  }, [address]);

  useEffect(() => {
    load();
  }, [load]);

  // Auto-refresh every 15s
  useEffect(() => {
    const id = setInterval(load, 15000);
    return () => clearInterval(id);
  }, [load]);

  return (
    <>
      <PageHeader
        title="Activity"
        subtitle="On-chain events involving your address. Amounts stay private — that's the design."
        action={
          <button
            onClick={load}
            disabled={loading}
            className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-300 transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        }
      />

      <div className="bg-zinc-900/60 border border-zinc-800 rounded-2xl backdrop-blur overflow-hidden">
        {loading && !events ? (
          <div className="p-6 space-y-2">
            {[1, 2, 3, 4].map((i) => (
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
              const url = explorerTxUrl(ev.txHash, chainId);
              return (
                <motion.li
                  key={ev.txHash}
                  variants={{
                    hidden: { opacity: 0, y: 8 },
                    show: { opacity: 1, y: 0 },
                  }}
                  className="flex items-center gap-4 px-5 py-4 hover:bg-zinc-900/40 transition-colors"
                >
                  <div
                    className={`w-9 h-9 rounded-lg border flex items-center justify-center ${s.colour}`}
                  >
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium">{s.label}</div>
                    {ev.counterparty && (
                      <div className="text-xs font-mono text-zinc-500 truncate">
                        {ev.type === 'send' ? '→ ' : '← '}
                        {ev.counterparty.slice(0, 10)}…{ev.counterparty.slice(-6)}
                      </div>
                    )}
                  </div>
                  <div className="text-right shrink-0">
                    <div className="text-xs text-zinc-500">{timeAgo(ev.timestamp)}</div>
                    {url ? (
                      <a
                        href={url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 text-[10px] text-violet-400 hover:text-violet-300 font-mono mt-0.5"
                      >
                        {ev.txHash.slice(0, 10)}…
                        <ExternalLink className="w-2.5 h-2.5" />
                      </a>
                    ) : (
                      <div className="text-[10px] font-mono text-zinc-700 mt-0.5">
                        {ev.txHash.slice(0, 10)}…
                      </div>
                    )}
                  </div>
                </motion.li>
              );
            })}
          </motion.ul>
        )}
      </div>

      <p className="text-xs text-zinc-600 mt-4 leading-relaxed max-w-2xl">
        Privacy note: by design, only the <em>fact</em> that you transferred is
        public. Amounts and balance changes stay encrypted in the Seismic TEE.
      </p>
    </>
  );
}
___F_HISTORY___

# =============================================================================
# app/(app)/portfolio/page.tsx — real allocation chart
# =============================================================================
cat > "app/(app)/portfolio/page.tsx" << '___F_PORTFOLIO___'
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
import { AllocationDonut } from '@/components/AllocationDonut';

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
    withdraws: events.filter((e) => e.type === 'withdraw').length,
    total: events.length,
  };

  // Real allocation: we hold one asset (ETH in shielded vault).
  const allocation = [
    { label: 'Shielded ETH', value: balance ?? 0, color: '#7c3aed' },
  ];

  return (
    <>
      <PageHeader title="Portfolio" subtitle="Your shielded holdings and activity stats." />

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

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <motion.div
          initial={{ opacity: 0, x: -16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4 }}
          className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
        >
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">
            Allocation
          </div>
          {balance !== null && balance > 0 ? (
            <AllocationDonut slices={allocation} size={200} />
          ) : (
            <div className="py-12 text-center text-sm text-zinc-500">
              No holdings yet. Deposit ETH to populate.
            </div>
          )}
          <div className="mt-4 pt-4 border-t border-zinc-800 text-[11px] text-zinc-600 leading-relaxed">
            Only one asset class (shielded ETH) exists in this build. Multi-token
            support requires deploying additional SRC20 contracts on Seismic.
          </div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, x: 16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
        >
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500 mb-4">
            Activity stats
          </div>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Deposits', value: stats.deposits, color: 'text-emerald-400' },
              { label: 'Sent', value: stats.sends, color: 'text-red-400' },
              { label: 'Received', value: stats.receives, color: 'text-violet-400' },
              { label: 'Withdraws', value: stats.withdraws, color: 'text-amber-400' },
            ].map((s) => (
              <div
                key={s.label}
                className="p-3 bg-zinc-950/40 border border-zinc-800 rounded-lg"
              >
                <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-500 mb-1">
                  {s.label}
                </div>
                <div className={`text-2xl font-light ${s.color}`}>
                  {loading ? '…' : s.value}
                </div>
              </div>
            ))}
          </div>
          <div className="mt-4 pt-4 border-t border-zinc-800 flex items-center justify-between text-xs">
            <span className="text-zinc-500">Total events</span>
            <span className="font-mono text-zinc-300">{stats.total}</span>
          </div>
        </motion.div>
      </div>
    </>
  );
}
___F_PORTFOLIO___

# =============================================================================
# app/(app)/trading/page.tsx — AI-driven shielded transfer interface
# =============================================================================
cat > "app/(app)/trading/page.tsx" << '___F_TRADING___'
'use client';

import { motion } from 'framer-motion';
import { PageHeader } from '@/components/PageHeader';
import { ChatPanel } from '@/components/ChatPanel';
import { ArrowLeftRight, Sparkles, Info } from 'lucide-react';

export default function TradingPage() {
  return (
    <>
      <PageHeader
        title="Trade"
        subtitle="AI-driven shielded transfers. Talk to the agent — it executes on-chain."
      />

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="bg-zinc-900/40 border border-zinc-800 rounded-2xl p-5 mb-6 backdrop-blur flex items-start gap-3"
      >
        <Info className="w-4 h-4 text-violet-400 mt-0.5 shrink-0" />
        <div className="text-xs text-zinc-300 leading-relaxed">
          <strong className="text-zinc-100">Honest note:</strong> a real swap UI
          (token A ↔ token B) needs an AMM contract that doesn&apos;t exist on
          our deployment yet. What works today is what most users actually want:
          tell the agent in plain English to move shielded value, and it does.
          For tokens & pools, that&apos;s Phase 6 contract work.
        </div>
      </motion.div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <motion.div
          initial={{ opacity: 0, x: -16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className="lg:col-span-2"
        >
          <ChatPanel />
        </motion.div>

        <motion.div
          initial={{ opacity: 0, x: 16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4, delay: 0.15 }}
          className="space-y-4"
        >
          <div className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-5 backdrop-blur">
            <div className="flex items-center gap-2 mb-3">
              <Sparkles className="w-4 h-4 text-violet-400" />
              <div className="text-xs uppercase tracking-[0.15em] text-zinc-500">
                Try these
              </div>
            </div>
            <div className="space-y-1.5 text-xs text-zinc-300">
              <div className="font-mono text-violet-300">&quot;Send 0.5 to 0x70997…&quot;</div>
              <div className="font-mono text-violet-300">&quot;Deposit 2 ETH&quot;</div>
              <div className="font-mono text-violet-300">&quot;Check my balance&quot;</div>
            </div>
          </div>

          <div className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-5 backdrop-blur">
            <div className="flex items-center gap-2 mb-3">
              <ArrowLeftRight className="w-4 h-4 text-zinc-500" />
              <div className="text-xs uppercase tracking-[0.15em] text-zinc-500">
                Phase 6 roadmap
              </div>
            </div>
            <ul className="text-xs text-zinc-400 space-y-2 leading-relaxed">
              <li>· SimpleSwap.sol AMM contract</li>
              <li>· Two demo SRC20 tokens with shielded balances</li>
              <li>· Add/remove liquidity flows</li>
              <li>· Real swap UI replaces this page</li>
              <li>· AI tools: swap, add_liquidity, get_price</li>
            </ul>
          </div>
        </motion.div>
      </div>
    </>
  );
}
___F_TRADING___

# =============================================================================
# app/(app)/dashboard/page.tsx — with recent activity preview
# =============================================================================
cat > "app/(app)/dashboard/page.tsx" << '___F_DASH___'
'use client';

import { motion } from 'framer-motion';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { useChainId } from 'wagmi';
import { BalanceCard } from '@/components/BalanceCard';
import { PageHeader } from '@/components/PageHeader';
import { useShielded } from '@/lib/useShielded';
import { fetchHistory, type HistoryEvent } from '@/lib/history';
import { explorerTxUrl } from '@/lib/explorer';
import {
  Send,
  ArrowDownToLine,
  QrCode,
  Clock,
  ArrowDownLeft,
  ArrowUpRight,
  ArrowUpFromLine,
  ExternalLink,
} from 'lucide-react';

const quick = [
  { href: '/send', icon: Send, label: 'Send', hint: 'Shielded transfer' },
  { href: '/deposit', icon: ArrowDownToLine, label: 'Deposit', hint: 'Fund your vault' },
  { href: '/receive', icon: QrCode, label: 'Receive', hint: 'Share address' },
  { href: '/history', icon: Clock, label: 'Activity', hint: 'Recent events' },
];

const iconMap = {
  deposit: ArrowDownToLine,
  withdraw: ArrowUpFromLine,
  send: ArrowUpRight,
  receive: ArrowDownLeft,
};

export default function Dashboard() {
  const { address } = useShielded();
  const chainId = useChainId();
  const [recent, setRecent] = useState<HistoryEvent[]>([]);

  useEffect(() => {
    if (!address) return;
    let cancelled = false;
    fetchHistory(address).then((evts) => {
      if (!cancelled) setRecent(evts.slice(0, 4));
    });
    return () => {
      cancelled = true;
    };
  }, [address]);

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
        transition={{ delay: 0.3 }}
        className="mt-8 bg-zinc-900/60 border border-zinc-800 rounded-2xl backdrop-blur overflow-hidden"
      >
        <div className="px-5 py-3 border-b border-zinc-800 flex items-center justify-between">
          <span className="text-xs uppercase tracking-[0.2em] text-zinc-500">
            Recent activity
          </span>
          <Link
            href="/history"
            className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
          >
            View all →
          </Link>
        </div>
        {recent.length === 0 ? (
          <div className="p-8 text-center text-sm text-zinc-500">
            No transactions yet. Try a deposit to get started.
          </div>
        ) : (
          <ul className="divide-y divide-zinc-800/50">
            {recent.map((ev) => {
              const Icon = iconMap[ev.type];
              const url = explorerTxUrl(ev.txHash, chainId);
              return (
                <li
                  key={ev.txHash}
                  className="flex items-center gap-4 px-5 py-3"
                >
                  <div className="w-8 h-8 rounded-lg bg-zinc-800/60 flex items-center justify-center">
                    <Icon className="w-3.5 h-3.5 text-zinc-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm capitalize">{ev.type}</div>
                    {ev.counterparty && (
                      <div className="text-[11px] font-mono text-zinc-500 truncate">
                        {ev.counterparty.slice(0, 10)}…{ev.counterparty.slice(-6)}
                      </div>
                    )}
                  </div>
                  {url ? (
                    <a
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-zinc-500 hover:text-violet-400 transition-colors"
                    >
                      <ExternalLink className="w-3.5 h-3.5" />
                    </a>
                  ) : (
                    <span className="text-[10px] font-mono text-zinc-700">
                      {ev.txHash.slice(0, 8)}…
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </motion.div>
    </>
  );
}
___F_DASH___

# =============================================================================
# app/api/chat/route.ts — extended with history + portfolio tools
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
          "Get the user's own shielded balance. Use whenever they ask about balance, how much they have, etc.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'send_payment',
        description:
          'Propose a shielded transfer. User confirms before execution.',
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
        description: "Deposit native ETH into the shielded vault.",
        parameters: {
          type: Type.OBJECT,
          properties: {
            amount: { type: Type.STRING, description: 'Amount in ETH as decimal' },
          },
          required: ['amount'],
        },
      },
      {
        name: 'get_history',
        description:
          "Get the user's recent on-chain activity (deposits, sends, receives). Returns count + summary.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'get_portfolio',
        description:
          "Get the user's portfolio: shielded balance + transaction counts.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
    ],
  },
];

const systemInstruction = `You are the agent for AI Pay Seismic — a shielded payments app on the Seismic blockchain.

Rules:
- Never see actual balance or amounts; they're encrypted on-chain. Use tools.
- For send/deposit, always call the tool — user confirms before signing.
- Be concise — two sentences max unless asked for detail.
- Never invent transaction hashes, addresses, or balances. Only report tool results.`;

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
# lib/tools.ts — extended with history + portfolio
# =============================================================================
cat > lib/tools.ts << '___F_TOOLS___'
import { getShieldedContract } from 'seismic-viem';
import { parseEther, formatEther, type Address } from 'viem';
import { seismicPay } from './contract';
import { fetchHistory } from './history';

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
    return { ok: false, error: 'Wallet not connected.' };
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
        return { ok: true, data: `Deposited ${tc.args.amount} ETH`, hash: hash as string };
      }
      case 'send_payment': {
        const amount = parseEther(String(tc.args.amount));
        const to = String(tc.args.to) as Address;
        const hash = await contract.write.transfer([to, amount]);
        const short = `${to.slice(0, 6)}…${to.slice(-4)}`;
        return { ok: true, data: `Sent ${tc.args.amount} ETH to ${short}`, hash: hash as string };
      }
      case 'get_history': {
        const events = await fetchHistory(account.address as Address);
        const sends = events.filter((e) => e.type === 'send').length;
        const receives = events.filter((e) => e.type === 'receive').length;
        const deposits = events.filter((e) => e.type === 'deposit').length;
        return {
          ok: true,
          data: `${events.length} total events: ${deposits} deposits, ${sends} sent, ${receives} received.`,
        };
      }
      case 'get_portfolio': {
        const bal = (await contract.read.balanceOf([
          account.address as Address,
        ])) as bigint;
        const events = await fetchHistory(account.address as Address);
        return {
          ok: true,
          data: `Balance: ${formatEther(bal)} ETH · ${events.length} on-chain events.`,
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

echo ""
echo "✓ Phase 5 applied."
echo ""
echo "What's new:"
echo "  · Multi-strategy wallet bridge (3 fallback strategies with console diagnostics)"
echo "  · Visible error states (no more silent '—')"
echo "  · Production tx flow: preparing → signing → confirming → confirmed/failed modal"
echo "  · Auto-refresh balance every 10s"
echo "  · Real allocation donut chart (animated SVG)"
echo "  · Particle background"
echo "  · Mobile-responsive sidebar (hamburger drawer)"
echo "  · Auto-refresh activity feed every 15s"
echo "  · Block explorer links (where supported)"
echo "  · Native share API on receive page"
echo "  · AI tools extended: get_history, get_portfolio"
echo "  · Trade page = AI-driven shielded transfer (honest about AMM)"
echo "  · Address validation with inline errors"
echo ""
echo "Restart: Ctrl+C 'npm run dev', then 'npm run dev'"
echo "Hard-refresh browser: Ctrl+Shift+R"
echo ""
echo "If balance STILL shows '—' after restart:"
echo "  Open F12 → Console → look for [useShielded] logs"
echo "  The red error in the balance card will tell you exactly what failed."
echo "  Paste it to Claude."
