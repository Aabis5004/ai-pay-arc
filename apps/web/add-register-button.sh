#!/usr/bin/env bash
# add-register-button.sh
# Adds a "Register card" button + registration status banner to the Card page.
# Shows whether your card number is registered on-chain; lets you register it.
#
# Run from ~/code/ai-pay-seismic/apps/web/ AFTER add-card-registry.sh
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

if [ ! -f lib/cardRegistry.ts ]; then
  echo "ERROR: run add-card-registry.sh first (lib/cardRegistry.ts missing)"; exit 1
fi

echo "→ Creating components/CardRegisterBanner.tsx…"
cat > components/CardRegisterBanner.tsx <<'TSX'
'use client';

import { useEffect, useState, useCallback } from 'react';
import { motion } from 'framer-motion';
import { BadgeCheck, Loader2, CreditCard } from 'lucide-react';
import { useWallets } from '@privy-io/react-auth';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { cardOf, registerCard, cardToBigInt, isRegistryConfigured } from '@/lib/cardRegistry';
import type { Address } from 'viem';

export function CardRegisterBanner({ cardNumber }: { cardNumber: string }) {
  const address = useWalletAddress();
  const { wallets } = useWallets();
  const [registered, setRegistered] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const check = useCallback(async () => {
    if (!address || !isRegistryConfigured()) { setRegistered(null); return; }
    try {
      const onchain = await cardOf(address as Address);
      const mine = cardToBigInt(cardNumber);
      setRegistered(onchain !== 0n && onchain === mine);
    } catch {
      setRegistered(null);
    }
  }, [address, cardNumber]);

  useEffect(() => { check(); }, [check]);

  async function getProvider() {
    if (wallets && wallets.length > 0) {
      try { return await wallets[0].getEthereumProvider(); } catch { /* */ }
    }
    if (typeof window !== 'undefined' && (window as { ethereum?: unknown }).ethereum)
      return (window as { ethereum?: unknown }).ethereum;
    return null;
  }

  const register = async () => {
    if (!address) return;
    setErr(null); setBusy(true);
    try {
      const provider = await getProvider();
      if (!provider) throw new Error('No wallet provider found.');
      await registerCard(provider as never, address as Address, cardNumber);
      await check();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Registration failed.');
    } finally {
      setBusy(false);
    }
  };

  if (!isRegistryConfigured()) return null;
  if (registered === null) return null;

  if (registered) {
    return (
      <div className="max-w-3xl mx-auto mb-6 flex items-center justify-center gap-2 text-xs text-emerald-400/80">
        <BadgeCheck className="w-4 h-4" />
        Your card is registered on-chain — others can pay you by card number.
      </div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}
      className="max-w-3xl mx-auto mb-6 rounded-2xl border border-violet-800/40 bg-violet-600/10 backdrop-blur p-4 flex items-center justify-between gap-4"
    >
      <div className="flex items-center gap-3">
        <CreditCard className="w-5 h-5 text-violet-300 shrink-0" />
        <div>
          <div className="text-sm text-white">Register your card on-chain</div>
          <div className="text-[11px] text-zinc-400">
            Required so people can send to your card number. One transaction.
          </div>
          {err && <div className="text-[11px] text-red-400 mt-1">{err}</div>}
        </div>
      </div>
      <button
        onClick={register}
        disabled={busy}
        className="shrink-0 px-4 py-2 rounded-xl bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium flex items-center gap-2 transition-colors disabled:opacity-60"
      >
        {busy && <Loader2 className="w-4 h-4 animate-spin" />}
        {busy ? 'Registering…' : 'Register card'}
      </button>
    </motion.div>
  );
}
TSX
echo "  ✓ CardRegisterBanner.tsx"

echo "→ Inserting banner into the card page…"
python3 - <<'PYEOF'
p = 'app/(app)/card/page.tsx'
with open(p) as f: c = f.read()
orig = c

# import
if 'CardRegisterBanner' not in c:
    c = c.replace(
        "import { CardActionModal, type CardAction } from '@/components/CardActionModal';",
        "import { CardActionModal, type CardAction } from '@/components/CardActionModal';\nimport { CardRegisterBanner } from '@/components/CardRegisterBanner';"
    )

# place banner right above the stat row (after the heading block)
if '<CardRegisterBanner' not in c:
    c = c.replace(
        '<div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">',
        '<CardRegisterBanner cardNumber={cardNumber} />\n\n      <div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">'
    )

if c != orig:
    with open(p,'w') as f: f.write(c)
    print("  ✓ banner wired into card page")
else:
    print("  · card page unchanged (already wired?)")
PYEOF

echo ""
echo "→ Clearing cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — Register card button added"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Ctrl+C npm run dev, then 'npm run dev', hard-refresh."
echo ""
echo "  On the Card page you'll now see a 'Register your card' banner."
echo "  Click 'Register card' (one tx) → your card number goes on-chain."
echo "  After that the banner turns into a green 'registered' confirmation."
echo ""
echo "  Then Send → enter a recipient CARD NUMBER (try a seeded test card)"
echo "  → amount → it resolves the address on-chain and sends for real."
