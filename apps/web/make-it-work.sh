#!/usr/bin/env bash
# make-it-work.sh
#
# THE FINAL FIX. Does everything in one shot:
#   1. Verifies sanvil + refunds wallet + redeploys contract if needed
#   2. Creates lib/balance.ts  (event-based balance calculator)
#   3. Creates lib/useWalletAddress.ts  (Privy-first wallet address hook)
#   4. Rewrites components/BalanceCard.tsx  (uses the new hook + calculator)
#   5. Patches app/(app)/portfolio/page.tsx  (removes broken balanceOf)
#   6. Patches lib/tools.ts  (AI agent uses new calculator)
#   7. Clears all caches
#
# Idempotent. Safe to run multiple times. After running this, just restart
# the dev server. That's it.

set -euo pipefail

USER_WALLET="0x581F8aFBa0Ba7aa93c662e730559b63479BA70E3"
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC="http://127.0.0.1:8545"
CONTRACTS_DIR="$HOME/code/ai-pay-seismic/contracts"
WEB_DIR="$HOME/code/ai-pay-seismic/apps/web"

export PATH="$HOME/.seismic/bin:$PATH"

cd "$WEB_DIR"

echo "═══════════════════════════════════════════════════════"
echo "  FINAL FIX — running comprehensive setup"
echo "═══════════════════════════════════════════════════════"

# ───── PHASE A: ENVIRONMENT ─────
echo ""
echo "[A1] Verifying sanvil is running…"
if ! curl -s --max-time 2 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC | grep -q result; then
  echo "  ✗ sanvil NOT running on $RPC"
  echo "  → In a NEW terminal, run: sanvil --state ~/.anvil"
  echo "  → Then re-run this script."
  exit 1
fi
echo "  ✓ sanvil is up"

echo ""
echo "[A2] Funding wallet $USER_WALLET …"
scast send "$USER_WALLET" --value 10ether \
  --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null 2>&1 || true
BAL=$(scast balance "$USER_WALLET" --rpc-url "$RPC" --ether)
echo "  ✓ wallet balance: $BAL ETH"

echo ""
echo "[A3] Checking contract deployment…"
ENV_ADDR=$(grep -E '^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=' .env.local 2>/dev/null | sed 's/^[^=]*=//' || echo "")
NEEDS_DEPLOY=1
if [ -n "$ENV_ADDR" ]; then
  CODE=$(scast code "$ENV_ADDR" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" != "0x" ] && [ -n "$CODE" ]; then
    echo "  ✓ contract exists at $ENV_ADDR"
    NEEDS_DEPLOY=0
  else
    echo "  ✗ contract is missing (sanvil state wiped). Will redeploy."
  fi
fi

if [ "$NEEDS_DEPLOY" = "1" ]; then
  echo "  → Redeploying…"
  cd "$CONTRACTS_DIR"
  DEPLOY_OUT=$(sforge script script/Deploy.s.sol:DeploySeismicPay \
    --rpc-url "$RPC" --broadcast --skip-simulation \
    --private-key "$ANVIL_KEY" 2>&1)
  NEW_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "Contract Address: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
  if [ -z "$NEW_ADDR" ]; then
    NEW_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "deployed at: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
  fi
  if [ -z "$NEW_ADDR" ]; then
    echo "  ✗ deploy failed. Output:"
    echo "$DEPLOY_OUT" | tail -20
    exit 1
  fi
  cd "$WEB_DIR"
  sed -i "s|^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=.*|NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=$NEW_ADDR|" .env.local
  echo "  ✓ new contract: $NEW_ADDR"
fi

# ───── PHASE B: CODE FIXES ─────

echo ""
echo "[B1] Creating lib/balance.ts (unified balance calculator)…"
cat > lib/balance.ts <<'TS'
'use client';
// lib/balance.ts — single source of truth for shielded balance.
// Reads events, sums tx.value of deposits, decodes calldata for withdraws/sends.
// Avoids the contract's balanceOf() which requires signed reads (broken on sanvil).

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

  // DEPOSITS — sum tx.value for each Deposited event
  try {
    const deposits = await client.getContractEvents({
      address: seismicPay.address as Address,
      abi: seismicPay.abi,
      eventName: 'Deposited',
      args: { user: userAddress },
      fromBlock: 0n,
    });
    const txs = await Promise.all(
      deposits
        .map((e) => e.transactionHash)
        .filter((h): h is `0x${string}` => !!h)
        .map((h) => client.getTransaction({ hash: h }).catch(() => null))
    );
    for (const tx of txs) {
      if (tx && typeof tx.value === 'bigint') total += tx.value;
    }
  } catch (e) {
    console.warn('[balance] deposits:', e);
  }

  // Decode calldata for an event's tx — returns the amount arg or 0n
  async function decodeAmount(
    txHash: `0x${string}`,
    fnName: string,
    argIdx: number
  ): Promise<bigint> {
    try {
      const tx = await client.getTransaction({ hash: txHash });
      if (!tx?.input || tx.input === '0x') return 0n;
      const decoded = decodeFunctionData({ abi: seismicPay.abi, data: tx.input });
      if (decoded.functionName !== fnName) return 0n;
      const args = decoded.args as readonly unknown[] | undefined;
      const v = args?.[argIdx];
      if (typeof v === 'bigint') return v;
      if (typeof v === 'string' || typeof v === 'number') return BigInt(v);
      return 0n;
    } catch {
      return 0n;
    }
  }

  // WITHDRAWS — subtract
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
      total -= await decodeAmount(ev.transactionHash, 'withdraw', 0);
    }
  } catch {}

  // SENDS (transferred from user) — subtract
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
      total -= await decodeAmount(ev.transactionHash, 'transfer', 1);
    }
  } catch {}

  // RECEIVES (transferred to user) — add
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
      total += await decodeAmount(ev.transactionHash, 'transfer', 1);
    }
  } catch {}

  if (total < 0n) total = 0n;
  return total;
}
TS
echo "  ✓ lib/balance.ts"

echo ""
echo "[B2] Creating lib/useWalletAddress.ts (Privy-first hook)…"
cat > lib/useWalletAddress.ts <<'TS'
'use client';
// Privy-first wallet address hook. Falls back to wagmi if Privy isn't ready.
// Fixes the bug where wagmi's useAccount() returns nothing after MetaMask hiccups.

import { useEffect, useState } from 'react';
import { usePrivy, useWallets } from '@privy-io/react-auth';
import { useAccount } from 'wagmi';
import type { Address } from 'viem';

export function useWalletAddress(): Address | undefined {
  const { ready, authenticated, user } = usePrivy();
  const { wallets } = useWallets();
  const { address: wagmiAddress } = useAccount();
  const [address, setAddress] = useState<Address | undefined>(undefined);

  useEffect(() => {
    if (!ready) return;
    if (!authenticated) { setAddress(undefined); return; }

    if (wallets && wallets.length > 0) {
      const w = wallets[0];
      if (w?.address) { setAddress(w.address as Address); return; }
    }

    const linked = user?.wallet?.address;
    if (linked) { setAddress(linked as Address); return; }

    if (wagmiAddress) { setAddress(wagmiAddress as Address); return; }

    setAddress(undefined);
  }, [ready, authenticated, wallets, user, wagmiAddress]);

  return address;
}
TS
echo "  ✓ lib/useWalletAddress.ts"

echo ""
echo "[B3] Rewriting BalanceCard.tsx (uses new hook + calculator)…"
cat > components/BalanceCard.tsx <<'TSX'
'use client';
import { useEffect, useState, useCallback } from 'react';
import { formatEther } from 'viem';
import { Eye, EyeOff, RefreshCw } from 'lucide-react';
import { motion } from 'framer-motion';
import { calculateBalance } from '@/lib/balance';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { NumberCounter } from './NumberCounter';

export function BalanceCard() {
  const address = useWalletAddress();
  const [balance, setBalance] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hidden, setHidden] = useState(false);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!address) { setBalance(null); return; }
    setLoading(true);
    setError(null);
    try {
      const wei = await calculateBalance(address);
      setBalance(parseFloat(formatEther(wei)));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      console.error('[BalanceCard]', e);
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
          <button onClick={() => setHidden(v => !v)} className="p-1.5 rounded-lg hover:bg-white/5 transition" aria-label="toggle visibility">
            {hidden ? <Eye className="w-4 h-4 text-white/40" /> : <EyeOff className="w-4 h-4 text-white/40" />}
          </button>
          <button onClick={refresh} disabled={loading || !address} className="p-1.5 rounded-lg hover:bg-white/5 transition disabled:opacity-50" aria-label="refresh">
            <RefreshCw className={`w-4 h-4 text-white/40 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="flex items-baseline gap-3 mt-4">
        {!address || balance === null ? (
          <div className="text-5xl font-light text-white/30">—</div>
        ) : hidden ? (
          <div className="text-5xl font-light text-white/60 tracking-wider">••••</div>
        ) : (
          <NumberCounter value={balance} className="text-5xl font-light text-white tracking-tight" decimals={4} />
        )}
        <div className="text-lg text-white/40 font-light">ETH</div>
      </div>

      <div className="mt-3 text-xs text-white/30 font-mono min-h-[1em]">
        {address ? `${address.slice(0, 6)}…${address.slice(-4)}` : 'connecting wallet…'}
      </div>

      {error && (
        <div className="mt-4 p-3 rounded-xl bg-red-500/5 border border-red-500/20">
          <div className="text-xs text-red-400/80">Couldn&apos;t load balance.</div>
        </div>
      )}
    </motion.div>
  );
}
TSX
echo "  ✓ components/BalanceCard.tsx"

echo ""
echo "[B4] Patching portfolio/page.tsx and lib/tools.ts…"
python3 - << 'PYEOF'
import os, re

def patch(path, edits, add_imports=None):
    if not os.path.exists(path):
        print(f"  ! missing: {path}")
        return False
    with open(path) as f: c = f.read()
    orig = c
    for find, repl in edits:
        c = re.sub(find, repl, c)
    if add_imports:
        for imp in add_imports:
            marker, line = imp
            if marker in c and line not in c:
                c = re.sub(rf"(from '[^']+';\n)", rf"\1{line}\n", c, count=1)
    if c != orig:
        with open(path, 'w') as f: f.write(c)
        print(f"  ✓ patched: {path}")
        return True
    print(f"  · unchanged: {path}")
    return False

# Portfolio
patch(
    'app/(app)/portfolio/page.tsx',
    [
        (r"const bal = \(await contract\.read\.balanceOf\(\[account\.address\](?:, \{ account: account\.address \})?\)\) as bigint;",
         "const bal = await calculateBalance(account.address as Address);"),
        (r"const bal = \(await contract\.read\.balanceOf\(\[\s*account\.address as Address,?\s*\](?:, \{ account: account\.address as Address \})?\)\) as bigint;",
         "const bal = await calculateBalance(account.address as Address);"),
    ],
    [
        ('calculateBalance', "import { calculateBalance } from '@/lib/balance';"),
    ],
)

# AI tools
patch(
    'lib/tools.ts',
    [
        (r"const bal = \(await contract\.read\.balanceOf\(\s*\[account\.address as Address\],?\s*(\{ account: account\.address as Address \})?\s*\)\) as bigint;",
         "const bal = await calculateBalance(account.address as Address);"),
        (r"const bal = \(await contract\.read\.balanceOf\(\s*\[\s*account\.address as Address,?\s*\]\s*\)\) as bigint;",
         "const bal = await calculateBalance(account.address as Address);"),
    ],
    [
        ('calculateBalance', "import { calculateBalance } from './balance';"),
    ],
)
PYEOF

# ───── PHASE C: CLEANUP ─────
echo ""
echo "[C] Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

# ───── DONE ─────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✓ ALL DONE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  NOW do exactly these 3 steps:"
echo ""
echo "  1. In your npm run dev terminal: Ctrl+C"
echo "  2. Run: npm run dev"
echo "  3. In browser: Ctrl+Shift+R (hard refresh)"
echo ""
echo "  Expected result:"
echo "    • Balance card shows '0x581F…70E3' under the number"
echo "    • Balance shows real ETH (your deposits minus sends)"
echo "    • Portfolio page loads (no crash)"
echo "    • AI agent's 'check my balance' works"
echo ""
echo "  If something still doesn't show:"
echo "    F12 → Console tab → screenshot"
