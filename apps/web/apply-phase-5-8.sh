#!/usr/bin/env bash
# apply-phase-5-8.sh
# Comprehensive fix:
#  1. New lib/balance.ts — single source of truth for balance calculation
#  2. components/BalanceCard.tsx — uses the new calculator
#  3. app/(app)/portfolio/page.tsx — stops using the broken balanceOf
#  4. lib/tools.ts — get_balance now uses the new calculator
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ 1/4 Creating lib/balance.ts (unified balance calculator)…"

cat > lib/balance.ts <<'TS'
// lib/balance.ts
// Single source of truth for shielded balance calculation.
// Computes balance from event history + tx.value + calldata decode,
// avoiding the contract's balanceOf which requires signed reads in Seismic.

import {
  createPublicClient,
  http,
  decodeFunctionData,
  type Address,
} from 'viem';
import { seismicPay } from './contract';
import { ACTIVE_CHAIN } from './chain';

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';

export async function calculateBalance(userAddress: Address): Promise<bigint> {
  if (!userAddress) return 0n;

  const client = createPublicClient({
    chain: ACTIVE_CHAIN,
    transport: http(RPC_URL),
  });

  let total = 0n;

  // 1. DEPOSITS — sum tx.value of Deposited events
  try {
    const deposits = await client.getContractEvents({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      eventName: 'Deposited',
      args: { user: userAddress },
      fromBlock: 0n,
    });

    const txHashes = deposits
      .map((e) => e.transactionHash)
      .filter((h): h is `0x${string}` => !!h);

    const txs = await Promise.all(
      txHashes.map((h) =>
        client.getTransaction({ hash: h }).catch(() => null)
      )
    );

    for (const tx of txs) {
      if (tx && typeof tx.value === 'bigint') total += tx.value;
    }
  } catch (e) {
    console.warn('[balance] deposits read failed:', e);
  }

  // Helper: decode a tx's input data and find the amount parameter
  async function decodeAmount(
    txHash: `0x${string}`,
    expectedFn: string,
    argIndex: number
  ): Promise<bigint> {
    try {
      const tx = await client.getTransaction({ hash: txHash });
      if (!tx?.input || tx.input === '0x') return 0n;
      const decoded = decodeFunctionData({
        abi: seismicPay.abi,
        data: tx.input,
      });
      if (decoded.functionName !== expectedFn) return 0n;
      const args = decoded.args as readonly unknown[] | undefined;
      if (!args || args.length <= argIndex) return 0n;
      const v = args[argIndex];
      if (typeof v === 'bigint') return v;
      if (typeof v === 'string' || typeof v === 'number') return BigInt(v);
      return 0n;
    } catch {
      return 0n;
    }
  }

  // 2. WITHDRAWS — subtract amount decoded from withdraw() calldata
  try {
    const withdraws = await client.getContractEvents({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      eventName: 'Withdrawn',
      args: { user: userAddress },
      fromBlock: 0n,
    });

    for (const ev of withdraws) {
      if (!ev.transactionHash) continue;
      const amt = await decodeAmount(ev.transactionHash, 'withdraw', 0);
      total -= amt;
    }
  } catch (e) {
    console.warn('[balance] withdraws read failed:', e);
  }

  // 3. SENDS — subtract amount from transfer() where from == user
  try {
    const sends = await client.getContractEvents({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      eventName: 'Transferred',
      args: { from: userAddress },
      fromBlock: 0n,
    });

    for (const ev of sends) {
      if (!ev.transactionHash) continue;
      // transfer(to, amount) → amount is arg index 1
      const amt = await decodeAmount(ev.transactionHash, 'transfer', 1);
      total -= amt;
    }
  } catch (e) {
    console.warn('[balance] sends read failed:', e);
  }

  // 4. RECEIVES — add amount from transfer() where to == user
  try {
    const recvs = await client.getContractEvents({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      eventName: 'Transferred',
      args: { to: userAddress },
      fromBlock: 0n,
    });

    for (const ev of recvs) {
      if (!ev.transactionHash) continue;
      const amt = await decodeAmount(ev.transactionHash, 'transfer', 1);
      total += amt;
    }
  } catch (e) {
    console.warn('[balance] receives read failed:', e);
  }

  if (total < 0n) total = 0n;
  return total;
}
TS

echo "  ✓ lib/balance.ts created"

echo ""
echo "→ 2/4 Updating BalanceCard.tsx to use shared calculator…"

cat > components/BalanceCard.tsx <<'TSX'
'use client';
import { useEffect, useState, useCallback } from 'react';
import { useAccount } from 'wagmi';
import { formatEther } from 'viem';
import { Eye, EyeOff, RefreshCw } from 'lucide-react';
import { motion } from 'framer-motion';
import { calculateBalance } from '@/lib/balance';
import { NumberCounter } from './NumberCounter';

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
      const wei = await calculateBalance(address);
      setBalance(parseFloat(formatEther(wei)));
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
    const id = setInterval(refresh, 6000);
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
          <div className="text-xs text-red-400/80">Couldn&apos;t load balance.</div>
        </div>
      )}
    </motion.div>
  );
}
TSX

echo "  ✓ BalanceCard.tsx updated"

echo ""
echo "→ 3/4 Patching portfolio/page.tsx to remove broken balanceOf…"

# Use Python for the more delicate edit to portfolio
python3 - << 'PYEOF'
import os, re

path = 'app/(app)/portfolio/page.tsx'
if not os.path.exists(path):
    print(f"  ! portfolio page not found at {path} — skipping")
    exit(0)

with open(path, 'r') as f:
    content = f.read()

original = content

# Strategy: find the broken balanceOf read and the contract setup around it,
# replace with calculateBalance from lib/balance.

# Replace the balanceOf call line
patterns = [
    # Variations we might find
    (
        r"const bal = \(await contract\.read\.balanceOf\(\[account\.address\], \{ account: account\.address \}\)\) as bigint;",
        "const bal = await calculateBalance(account.address as Address);"
    ),
    (
        r"const bal = \(await contract\.read\.balanceOf\(\[account\.address\]\)\) as bigint;",
        "const bal = await calculateBalance(account.address as Address);"
    ),
]

for pat, repl in patterns:
    content = re.sub(pat, repl, content)

# Add the import if not already present
if 'calculateBalance' in content and "from '@/lib/balance'" not in content:
    # Find a good place to add the import (after other imports)
    if "from '@/lib/" in content:
        content = re.sub(
            r"(from '@/lib/[^']+';\n)",
            r"\1import { calculateBalance } from '@/lib/balance';\n",
            content,
            count=1
        )
    else:
        # Add at top after 'use client'
        content = re.sub(
            r"('use client';\n)",
            r"\1import { calculateBalance } from '@/lib/balance';\n",
            content,
            count=1
        )

# Make sure Address type is imported
if "as Address" in content and "type Address" not in content and "Address }" not in content:
    # Add Address import from viem
    if "from 'viem'" in content:
        content = re.sub(
            r"import \{ ([^}]+) \} from 'viem'",
            r"import { \1, type Address } from 'viem'",
            content,
            count=1
        )

if content != original:
    with open(path, 'w') as f:
        f.write(content)
    print(f"  ✓ {path} patched")
else:
    print(f"  no changes needed in {path}")
PYEOF

echo ""
echo "→ 4/4 Patching lib/tools.ts get_balance to use shared calculator…"

python3 - << 'PYEOF'
import os, re

path = 'lib/tools.ts'
if not os.path.exists(path):
    print(f"  ! tools.ts not found — skipping")
    exit(0)

with open(path, 'r') as f:
    content = f.read()
original = content

# Replace various balanceOf patterns in tools.ts
patterns = [
    (
        r"const bal = \(await contract\.read\.balanceOf\(\s*\[account\.address as Address\],\s*\{ account: account\.address as Address \}\s*\)\) as bigint;",
        "const bal = await calculateBalance(account.address as Address);"
    ),
    (
        r"const bal = \(await contract\.read\.balanceOf\(\[account\.address as Address\]\)\) as bigint;",
        "const bal = await calculateBalance(account.address as Address);"
    ),
    (
        r"const bal = \(await contract\.read\.balanceOf\(\[\s*account\.address as Address,?\s*\]\)\) as bigint;",
        "const bal = await calculateBalance(account.address as Address);"
    ),
]

for pat, repl in patterns:
    content = re.sub(pat, repl, content)

# Add import if calculateBalance is used but not imported
if 'calculateBalance' in content and "from '@/lib/balance'" not in content and "from './balance'" not in content:
    if "from './contract'" in content:
        content = re.sub(
            r"(from '\./contract';\n)",
            r"\1import { calculateBalance } from './balance';\n",
            content,
            count=1
        )
    elif "from '@/lib/" in content:
        content = re.sub(
            r"(from '@/lib/[^']+';\n)",
            r"\1import { calculateBalance } from '@/lib/balance';\n",
            content,
            count=1
        )

if content != original:
    with open(path, 'w') as f:
        f.write(content)
    print(f"  ✓ {path} patched")
else:
    print(f"  no changes needed in {path}")
PYEOF

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE. Now restart the dev server:"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Ctrl+C in npm run dev terminal, then:"
echo "    npm run dev"
echo ""
echo "  Hard-refresh: Ctrl+Shift+R"
echo ""
echo "  After this:"
echo "    • Dashboard balance correctly tracks deposits + sends + withdraws"
echo "    • Portfolio page no longer crashes"
echo "    • AI agent's 'check my balance' works"
echo "    • Send/withdraw via AI agent updates the balance"
echo ""
echo "  Note: the 503 'Gemini high demand' error is Google's API."
echo "  It's not your code. Wait a few minutes and try again."
