#!/usr/bin/env bash
# finish-card-registry.sh
# Completes the card-number system (everything the crashed script skipped):
#   1. Seeds 3 test cards into the registry
#   2. Creates lib/cardRegistry.ts
#   3. Adds cardSendByNumber to lib/cardTx.ts
#   4. Patches CardActionModal to send by card number
#   5. Creates CardRegisterBanner + wires it into the card page
#
# Registry is already deployed + in env. Requires sanvil running.
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

REG="0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6"
RPC="http://127.0.0.1:8545"

export PATH="$HOME/.seismic/bin:$PATH"

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi
if ! command -v scast &>/dev/null; then echo "ERROR: scast not on PATH"; exit 1; fi

# ───────────────────────────────────────────────
# 1. Seed 3 test cards
# ───────────────────────────────────────────────
echo "→ 1/5 Seeding test cards…"

seed_one() {
  local ADDR="$1" KEY="$2"
  local CARD
  CARD=$(python3 -c "
addr='$ADDR'.lower().replace('0x','')
d=''
for ch in addr:
    try: v=int(ch,16)
    except: continue
    d+=str(v%10)
    if len(d)>=16: break
d=(d+'4242424242424242')[:16]
print(d)
")
  echo "    $ADDR -> $CARD"
  scast send "$REG" "register(uint256)" "$CARD" \
    --rpc-url "$RPC" --private-key "$KEY" >/dev/null 2>&1 \
    && echo "      ✓ registered" \
    || echo "      (already registered or skipped)"
}

seed_one "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
seed_one "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
seed_one "0x90F79bf6EB2c4f870365E785982E1f101E93b906" "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

echo ""
echo "  Seeded cards (send to these for testing):"
echo "    7099 7970 2518 1232"
echo "    3244 2333 1609 0050"
echo "    9057 9156 4122 4587"

# ───────────────────────────────────────────────
# 2. lib/cardRegistry.ts
# ───────────────────────────────────────────────
echo ""
echo "→ 2/5 Creating lib/cardRegistry.ts…"
cat > lib/cardRegistry.ts <<'TS'
'use client';
import {
  createPublicClient, createWalletClient, custom, http, type Address,
} from 'viem';
import { ACTIVE_CHAIN } from './chain';
import { cardRegistryAbi } from '@/abi/CardRegistry';

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';
const REGISTRY = process.env.NEXT_PUBLIC_CARD_REGISTRY as Address | undefined;

type Provider = { request: (a: { method: string; params?: unknown }) => Promise<unknown> };

function pub() {
  return createPublicClient({ chain: ACTIVE_CHAIN, transport: http(RPC_URL) });
}

export function cardToBigInt(card: string): bigint {
  const digits = card.replace(/\D/g, '');
  if (!digits) return 0n;
  return BigInt(digits);
}

export function isRegistryConfigured(): boolean {
  return !!REGISTRY;
}

export async function resolveCard(card: string): Promise<Address | null> {
  if (!REGISTRY) throw new Error('Card registry not configured.');
  const num = cardToBigInt(card);
  if (num === 0n) return null;
  const addr = (await pub().readContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'addressOf', args: [num],
  })) as Address;
  if (!addr || addr === '0x0000000000000000000000000000000000000000') return null;
  return addr;
}

export async function cardOf(addr: Address): Promise<bigint> {
  if (!REGISTRY) return 0n;
  return (await pub().readContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'cardOf', args: [addr],
  })) as bigint;
}

export async function registerCard(
  provider: Provider, account: Address, card: string,
): Promise<`0x${string}`> {
  if (!REGISTRY) throw new Error('Card registry not configured.');
  const num = cardToBigInt(card);
  if (num === 0n) throw new Error('Invalid card number.');
  const wc = createWalletClient({
    account, chain: ACTIVE_CHAIN, transport: custom(provider as Parameters<typeof custom>[0]),
  });
  const hash = await wc.writeContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'register', args: [num], chain: ACTIVE_CHAIN,
  });
  await pub().waitForTransactionReceipt({ hash, timeout: 30_000 });
  return hash;
}
TS
echo "  ✓ lib/cardRegistry.ts"

# ───────────────────────────────────────────────
# 3. cardSendByNumber in cardTx.ts
# ───────────────────────────────────────────────
echo "→ 3/5 Adding cardSendByNumber to lib/cardTx.ts…"
python3 - <<'PYEOF'
p = 'lib/cardTx.ts'
with open(p) as f: c = f.read()
if 'cardSendByNumber' not in c:
    if "import { resolveCard }" not in c:
        c = c.replace(
            "import { ACTIVE_CHAIN } from './chain';",
            "import { ACTIVE_CHAIN } from './chain';\nimport { resolveCard } from './cardRegistry';"
        )
    c += '''

export async function cardSendByNumber(
  provider: Provider, account: Address, cardNumber: string, amount: string,
): Promise<`0x${string}`> {
  const to = await resolveCard(cardNumber);
  if (!to) throw new Error('That card number is not registered on-chain.');
  return cardSend(provider, account, to, amount);
}
'''
    with open(p,'w') as f: f.write(c)
    print("  ✓ cardSendByNumber added")
else:
    print("  · already present")
PYEOF

# ───────────────────────────────────────────────
# 4. Patch modal to send by card number
# ───────────────────────────────────────────────
echo "→ 4/5 Patching CardActionModal for card-number sends…"
python3 - <<'PYEOF'
p = 'components/CardActionModal.tsx'
with open(p) as f: c = f.read()
orig = c

if 'cardSendByNumber' not in c:
    c = c.replace(
        "import { cardDeposit, cardSend } from '@/lib/cardTx';",
        "import { cardDeposit, cardSendByNumber } from '@/lib/cardTx';"
    )
    # in case it was imported differently
    c = c.replace(
        "import { cardDeposit, cardSendByNumber } from '@/lib/cardTx';\nimport { cardSend }",
        "import { cardDeposit, cardSendByNumber } from '@/lib/cardTx';"
    )

c = c.replace(
    "const hash = await cardSend(provider as never, address as Address, to, amount);",
    "const hash = await cardSendByNumber(provider as never, address as Address, to, amount);"
)
c = c.replace(
    'placeholder="0x…"',
    'placeholder="5815 8051 0010 7009"'
)
c = c.replace(
    '>Recipient address<',
    '>Recipient card number<'
)
c = c.replace(
    "if (!to) { setPhase({ s: 'error', msg: 'Enter a recipient address.' }); return; }",
    "if (!to.replace(/\\\\D/g,'')) { setPhase({ s: 'error', msg: 'Enter a recipient card number.' }); return; }"
)

if c != orig:
    with open(p,'w') as f: f.write(c)
    print("  ✓ modal patched for card numbers")
else:
    print("  · modal unchanged (verify manually)")
PYEOF

# ───────────────────────────────────────────────
# 5. Register banner + wire into card page
# ───────────────────────────────────────────────
echo "→ 5/5 Adding Register-card banner…"
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
      setRegistered(onchain !== 0n && onchain === cardToBigInt(cardNumber));
    } catch { setRegistered(null); }
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
    } finally { setBusy(false); }
  };

  if (!isRegistryConfigured() || registered === null) return null;

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
          <div className="text-[11px] text-zinc-400">Required so people can pay your card number. One transaction.</div>
          {err && <div className="text-[11px] text-red-400 mt-1">{err}</div>}
        </div>
      </div>
      <button
        onClick={register} disabled={busy}
        className="shrink-0 px-4 py-2 rounded-xl bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium flex items-center gap-2 transition-colors disabled:opacity-60"
      >
        {busy && <Loader2 className="w-4 h-4 animate-spin" />}
        {busy ? 'Registering…' : 'Register card'}
      </button>
    </motion.div>
  );
}
TSX

python3 - <<'PYEOF'
p = 'app/(app)/card/page.tsx'
with open(p) as f: c = f.read()
orig = c
if 'CardRegisterBanner' not in c:
    c = c.replace(
        "import { CardActionModal, type CardAction } from '@/components/CardActionModal';",
        "import { CardActionModal, type CardAction } from '@/components/CardActionModal';\nimport { CardRegisterBanner } from '@/components/CardRegisterBanner';"
    )
    c = c.replace(
        '<div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">',
        '<CardRegisterBanner cardNumber={cardNumber} />\n\n      <div className="grid grid-cols-3 gap-6 md:gap-12 max-w-3xl mx-auto mb-12 text-center">'
    )
    with open(p,'w') as f: f.write(c)
    print("  ✓ banner wired into card page")
else:
    print("  · already wired")
PYEOF

echo ""
echo "→ Clearing cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — card-number payments fully wired"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Ctrl+C npm run dev, then 'npm run dev', hard-refresh."
echo ""
echo "  1. Card page shows 'Register your card' → click it (one tx)."
echo "  2. Click Send → enter a RECIPIENT CARD NUMBER:"
echo "        7099 7970 2518 1232"
echo "        3244 2333 1609 0050"
echo "        9057 9156 4122 4587"
echo "     → amount → it resolves the address on-chain & sends for real."
echo ""
echo "  (Deposit first so you have balance to send.)"
