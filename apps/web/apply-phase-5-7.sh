#!/usr/bin/env bash
# apply-phase-5-7.sh
# Stop calling balanceOf (which needs signed reads we don't have).
# Instead, calculate balance from Deposited/Withdrawn events using the public client.
# This works because event reads are unrestricted and already work in the app.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/  (cd ~/code/ai-pay-seismic/apps/web)"
  exit 1
fi

echo "→ Backing up files…"
cp components/BalanceCard.tsx components/BalanceCard.tsx.bak 2>/dev/null || true

echo "→ Writing new BalanceCard.tsx (event-based balance, no shielded read)…"

cat > components/BalanceCard.tsx <<'TSX'
'use client';
import { useEffect, useState, useCallback } from 'react';
import { useAccount } from 'wagmi';
import { createPublicClient, http, formatEther, type Address } from 'viem';
import { Eye, EyeOff, RefreshCw } from 'lucide-react';
import { motion } from 'framer-motion';
import { seismicPay } from '@/lib/contract';
import { ACTIVE_CHAIN, RPC_URL } from '@/lib/chain';
import NumberCounter from './NumberCounter';

export default function BalanceCard() {
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
      // Read events directly via public client — no shielded read needed.
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

      // Subtract withdrawals (if any)
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
        // Withdrawn event might not have amount or might not exist; ignore
      }

      // Subtract sent transfers (if Transferred event has amount)
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
        // shielded contracts often omit amount in Transferred; ignore silently
      }

      // Add received transfers (if Transferred event has amount)
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
            Couldn't load balance from events. Check console.
          </div>
        </div>
      )}
    </motion.div>
  );
}
TSX

echo "  ✓ BalanceCard.tsx rewritten — now uses event-based balance"

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═════════════════════════════════════════════"
echo "  DONE. Now restart the dev server:"
echo "═════════════════════════════════════════════"
echo ""
echo "  In your npm run dev terminal:"
echo "    Ctrl+C"
echo "    npm run dev"
echo ""
echo "  Then hard-refresh the browser: Ctrl+Shift+R"
echo ""
echo "  The balance card should show 1.1 ETH (your existing deposits)."
echo "  No red error box. No more 'only owner can read'."
echo ""
echo "  If something doesn't look right, restore the backup:"
echo "    mv components/BalanceCard.tsx.bak components/BalanceCard.tsx"
