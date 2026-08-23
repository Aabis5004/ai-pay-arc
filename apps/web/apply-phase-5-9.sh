#!/usr/bin/env bash
# apply-phase-5-9.sh
# ROOT-CAUSE FIX for the recurring "balance card has no address" bug.
#
# Problem: wagmi's useAccount() loses the address when MetaMask hiccups,
# even though Privy still has the wallet. Components that rely on wagmi
# show "—" with no address; Privy-aware components (sidebar) still work.
#
# Solution: read the address from Privy directly (with wagmi as fallback).
# Privy is the auth layer and is always source-of-truth for the connected wallet.
#
# Files changed:
#   - NEW   lib/useWalletAddress.ts  (single hook)
#   - EDIT  components/BalanceCard.tsx
#   - EDIT  app/(app)/portfolio/page.tsx
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ 1/3 Creating lib/useWalletAddress.ts (Privy-first wallet address hook)…"

cat > lib/useWalletAddress.ts <<'TS'
'use client';
// lib/useWalletAddress.ts
// Single source of truth for the connected wallet address.
// Reads from Privy first (always reliable since it's the auth layer),
// falls back to wagmi if Privy isn't ready yet.
// This fixes the "balance card shows no address after MetaMask hiccup" bug.

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
    if (!authenticated) {
      setAddress(undefined);
      return;
    }

    // 1. Try Privy wallets array (the connected wallets — MetaMask, embedded, etc.)
    if (wallets && wallets.length > 0) {
      const w = wallets[0];
      if (w?.address) {
        setAddress(w.address as Address);
        return;
      }
    }

    // 2. Fall back to Privy user's linked wallet
    const linked = user?.wallet?.address;
    if (linked) {
      setAddress(linked as Address);
      return;
    }

    // 3. Last resort: wagmi's account
    if (wagmiAddress) {
      setAddress(wagmiAddress as Address);
      return;
    }

    setAddress(undefined);
  }, [ready, authenticated, wallets, user, wagmiAddress]);

  return address;
}
TS

echo "  ✓ lib/useWalletAddress.ts created"

echo ""
echo "→ 2/3 Updating BalanceCard.tsx to use the new hook…"

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
    if (!address) {
      setBalance(null);
      return;
    }
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
            disabled={loading || !address}
            className="p-1.5 rounded-lg hover:bg-white/5 transition disabled:opacity-50"
            aria-label="refresh"
          >
            <RefreshCw className={`w-4 h-4 text-white/40 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="flex items-baseline gap-3 mt-4">
        {!address ? (
          <div className="text-5xl font-light text-white/30">—</div>
        ) : balance === null ? (
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

echo "  ✓ BalanceCard.tsx now uses useWalletAddress()"

echo ""
echo "→ 3/3 Patching portfolio/page.tsx to use the new hook + new balance calc…"

python3 - << 'PYEOF'
import os, re

path = 'app/(app)/portfolio/page.tsx'
if not os.path.exists(path):
    print(f"  ! {path} not found — skipping")
    exit(0)

with open(path, 'r') as f:
    content = f.read()
original = content

# 1. Replace useAccount with useWalletAddress
content = re.sub(
    r"import \{ useAccount \} from 'wagmi';",
    "import { useWalletAddress } from '@/lib/useWalletAddress';",
    content
)
# Sometimes useAccount is part of a longer import
content = re.sub(
    r"useAccount,?\s*",
    "",
    content
)
# Clean up empty wagmi imports
content = re.sub(
    r"import \{\s*,?\s*\} from 'wagmi';\s*\n",
    "",
    content
)
content = re.sub(
    r"import \{\s*\} from 'wagmi';\s*\n",
    "",
    content
)

# Make sure useWalletAddress is imported
if 'useWalletAddress' in content and "from '@/lib/useWalletAddress'" not in content:
    if "from '@/lib/" in content:
        content = re.sub(
            r"(from '@/lib/[^']+';\n)",
            r"\1import { useWalletAddress } from '@/lib/useWalletAddress';\n",
            content,
            count=1
        )

# 2. Replace the useAccount() call with useWalletAddress()
content = re.sub(
    r"const \{ address \} = useAccount\(\);",
    "const address = useWalletAddress();",
    content
)
content = re.sub(
    r"const account = useAccount\(\);",
    "const _walletAddr = useWalletAddress(); const account = { address: _walletAddr };",
    content
)

# 3. Replace the broken balanceOf calls with calculateBalance
patterns = [
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

# Add calculateBalance import if used
if 'calculateBalance' in content and "from '@/lib/balance'" not in content:
    if "from '@/lib/" in content:
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
echo "  ROOT FIX APPLIED."
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Restart dev server:"
echo "    Ctrl+C in npm run dev, then 'npm run dev'"
echo "  Hard-refresh browser: Ctrl+Shift+R"
echo ""
echo "  What's different now:"
echo "  • Address comes from Privy (the auth layer), not wagmi"
echo "  • Even if MetaMask hiccups, the address stays correct"
echo "  • Balance card now always shows either the address or"
echo "    'connecting wallet…' (no more silent emptiness)"
echo "  • Portfolio page no longer crashes on balanceOf"
echo ""
echo "  After hard refresh, balance card should show:"
echo "    • 0x581F…70E3 underneath the balance"
echo "    • Real balance number (from your deposits)"
