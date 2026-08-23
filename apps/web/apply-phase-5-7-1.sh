#!/usr/bin/env bash
# apply-phase-5-7-1.sh
# Fix the broken imports from phase 5.7:
#   - BalanceCard must be a NAMED export (not default)
#   - NumberCounter is a NAMED import (not default)
#   - Use process.env directly for RPC_URL (not from chain.ts)
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Writing corrected BalanceCard.tsx (named exports, no RPC_URL import)…"

cat > components/BalanceCard.tsx <<'TSX'
'use client';
import { useEffect, useState, useCallback } from 'react';
import { useAccount } from 'wagmi';
import { createPublicClient, http, formatEther, type Address } from 'viem';
import { Eye, EyeOff, RefreshCw } from 'lucide-react';
import { motion } from 'framer-motion';
import { seismicPay } from '@/lib/contract';
import { ACTIVE_CHAIN } from '@/lib/chain';
import { NumberCounter } from './NumberCounter';

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';

export function BalanceCard() {
  const { address } = useAccount();
  const [balance, setBalance] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hidden, setHidden] = useState(false);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!address) return;
    setLoading(true);
    setError(null);
    try {
      const client = createPublicClient({
        chain: ACTIVE_CHAIN,
        transport: http(RPC_URL),
      });

      let total = 0n;

      // Sum deposits
      try {
        const deposits = await client.getContractEvents({
          address: seismicPay.address as Address,
          abi: seismicPay.abi,
          eventName: 'Deposited',
          args: { user: address as Address },
          fromBlock: 0n,
        });
        for (const ev of deposits) {
          const amount = (ev.args as { amount?: bigint }).amount;
          if (typeof amount === 'bigint') total += amount;
        }
      } catch (e) {
        console.warn('[BalanceCard] deposits read failed:', e);
      }

      // Subtract withdrawals (if any have amount field)
      try {
        const withdraws = await client.getContractEvents({
          address: seismicPay.address as Address,
          abi: seismicPay.abi,
          eventName: 'Withdrawn',
          args: { user: address as Address },
          fromBlock: 0n,
        });
        for (const ev of withdraws) {
          const amount = (ev.args as { amount?: bigint }).amount;
          if (typeof amount === 'bigint') total -= amount;
        }
      } catch {
        // event might not exist or have amount; ignore
      }

      // Subtract sent transfers
      try {
        const sent = await client.getContractEvents({
          address: seismicPay.address as Address,
          abi: seismicPay.abi,
          eventName: 'Transferred',
          args: { from: address as Address },
          fromBlock: 0n,
        });
        for (const ev of sent) {
          const amount = (ev.args as { amount?: bigint }).amount;
          if (typeof amount === 'bigint') total -= amount;
        }
      } catch {
        // ignore — shielded transfers may not emit amount
      }

      // Add received transfers
      try {
        const recvd = await client.getContractEvents({
          address: seismicPay.address as Address,
          abi: seismicPay.abi,
          eventName: 'Transferred',
          args: { to: address as Address },
          fromBlock: 0n,
        });
        for (const ev of recvd) {
          const amount = (ev.args as { amount?: bigint }).amount;
          if (typeof amount === 'bigint') total += amount;
        }
      } catch {
        // ignore
      }

      if (total < 0n) total = 0n;
      setBalance(parseFloat(formatEther(total)));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
      console.error('[BalanceCard] failed:', e);
    } finally {
      setLoading(false);
    }
  }, [address]);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 8000);
    return () => clearInterval(id);
  }, [refresh]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className="relative overflow-hidden rounded-2xl border border-white/[0.08] bg-gradient-to-br from-violet-950/40 via-zinc-900/40 to-zinc-950/40 backdrop-blur-xl p-7"
    >
      <div className="flex items-start justify-between mb-2">
        <div className="text-[11px] tracking-[0.18em] uppercase text-white/40 font-medium">
          Shielded Balance
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setHidden((v) => !v)}
            className="p-1.5 rounded-lg hover:bg-white/5 transition"
            aria-label="toggle visibility"
          >
            {hidden ? (
              <Eye className="w-4 h-4 text-white/40" />
            ) : (
              <EyeOff className="w-4 h-4 text-white/40" />
            )}
          </button>
          <button
            onClick={refresh}
            disabled={loading}
            className="p-1.5 rounded-lg hover:bg-white/5 transition disabled:opacity-50"
            aria-label="refresh"
          >
            <RefreshCw className={`w-4 h-4 text-white/40 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="flex items-baseline gap-3 mt-4">
        {balance === null ? (
          <div className="text-5xl font-light text-white/30">—</div>
        ) : hidden ? (
          <div className="text-5xl font-light text-white/60 tracking-wider">••••</div>
        ) : (
          <NumberCounter
            value={balance}
            className="text-5xl font-light text-white tracking-tight"
            decimals={4}
          />
        )}
        <div className="text-lg text-white/40 font-light">ETH</div>
      </div>

      {address && (
        <div className="mt-3 text-xs text-white/30 font-mono">
          {address.slice(0, 6)}…{address.slice(-4)}
        </div>
      )}

      {error && (
        <div className="mt-4 p-3 rounded-xl bg-red-500/5 border border-red-500/20">
          <div className="text-xs text-red-400/80">
            Couldn't load balance from events.
          </div>
        </div>
      )}
    </motion.div>
  );
}
TSX

echo "  ✓ BalanceCard.tsx rewritten with correct exports/imports"

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═════════════════════════════════════════════"
echo "  Now restart the dev server:"
echo "═════════════════════════════════════════════"
echo ""
echo "  Ctrl+C in npm run dev terminal, then:"
echo "    npm run dev"
echo ""
echo "  Hard-refresh the browser: Ctrl+Shift+R"
echo ""
echo "  If the page compiles without errors, the balance card"
echo "  should show your real ETH (1.1 from existing deposits)."
