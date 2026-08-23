#!/usr/bin/env bash
# apply-phase-5-4.sh
# Phase 5.4 — Replace ETH labels with SIZE (the actual native currency on Seismic Testnet)
# The seismic-viem package's seismicTestnet chain definition uses symbol "ETH" by mistake.
# The real chain on testnet-1.seismictest.net uses "SIZE". Override locally + propagate.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ lib/chain.ts — override symbol to SIZE, expose NATIVE_SYMBOL…"
cat > lib/chain.ts << '___F_CHAIN___'
import { sanvil, seismicTestnet } from 'seismic-viem';
import type { Chain } from 'viem';

const CHAIN_ID = parseInt(process.env.NEXT_PUBLIC_CHAIN_ID || '31337', 10);

// seismic-viem's seismicTestnet has nativeCurrency.symbol = "ETH", which is wrong
// for the live testnet at testnet-1.seismictest.net. The chain itself uses SIZE.
// We override locally so MetaMask, our UI, and viem all agree.
const seismicTestnetReal: Chain = {
  ...seismicTestnet,
  name: 'Seismic Testnet',
  nativeCurrency: {
    name: 'Seismic',
    symbol: 'SIZE',
    decimals: 18,
  },
  rpcUrls: {
    default: { http: ['https://testnet-1.seismictest.net/rpc'] },
    public: { http: ['https://testnet-1.seismictest.net/rpc'] },
  },
  blockExplorers: {
    default: {
      name: 'SocialScan',
      url: 'https://seismic-testnet.socialscan.io',
    },
  },
};

export const ACTIVE_CHAIN: Chain =
  CHAIN_ID === 5124 ? seismicTestnetReal : sanvil;
export const IS_TESTNET = ACTIVE_CHAIN.id === 5124;
export const NATIVE_SYMBOL = ACTIVE_CHAIN.nativeCurrency.symbol;
___F_CHAIN___

echo "→ Patch UI files — replace hardcoded ETH labels with {NATIVE_SYMBOL}…"

# Use Python for reliable file rewriting (sed gets messy with JSX/quotes)
python3 - << 'PYEOF'
import os
import re

def patch_file(path, edits):
    if not os.path.exists(path):
        print(f"  skip (missing): {path}")
        return
    with open(path, 'r') as f:
        content = f.read()
    original = content
    for find, replace in edits:
        content = content.replace(find, replace)
    if content != original:
        with open(path, 'w') as f:
            f.write(content)
        print(f"  patched: {path}")
    else:
        print(f"  unchanged: {path}")

# ─── BalanceCard.tsx ────────────────────────────────────────────────────
patch_file('components/BalanceCard.tsx', [
    (
        "import { seismicPay } from '@/lib/contract';",
        "import { seismicPay } from '@/lib/contract';\nimport { NATIVE_SYMBOL } from '@/lib/chain';",
    ),
    (
        '<span className="text-xl text-zinc-500 font-normal ml-2">ETH</span>',
        '<span className="text-xl text-zinc-500 font-normal ml-2">{NATIVE_SYMBOL}</span>',
    ),
])

# ─── send/page.tsx ──────────────────────────────────────────────────────
patch_file('app/(app)/send/page.tsx', [
    (
        "import { seismicPay } from '@/lib/contract';",
        "import { seismicPay } from '@/lib/contract';\nimport { NATIVE_SYMBOL } from '@/lib/chain';",
    ),
    (
        'const summary = valid ? `${amount} ETH → ${to.slice(0, 8)}…${to.slice(-6)}` : \'\';',
        "const summary = valid ? `${amount} ${NATIVE_SYMBOL} → ${to.slice(0, 8)}…${to.slice(-6)}` : '';",
    ),
    (
        'Amount (ETH)',
        'Amount ({NATIVE_SYMBOL})',
    ),
])
# Re-fix JSX label (Amount ({NATIVE_SYMBOL}) needs braces in JSX text)
patch_file('app/(app)/send/page.tsx', [
    (
        'Amount ({NATIVE_SYMBOL})',
        'Amount ({`(${NATIVE_SYMBOL})`})',
    ),
])
# Simpler: just use a template via expression
patch_file('app/(app)/send/page.tsx', [
    (
        'Amount ({`(${NATIVE_SYMBOL})`})',
        '{`Amount (${NATIVE_SYMBOL})`}',
    ),
])

# ─── deposit/page.tsx ───────────────────────────────────────────────────
patch_file('app/(app)/deposit/page.tsx', [
    (
        "import { seismicPay } from '@/lib/contract';",
        "import { seismicPay } from '@/lib/contract';\nimport { NATIVE_SYMBOL } from '@/lib/chain';",
    ),
    (
        "const summary = valid ? `Deposit ${amount} ETH to shielded vault` : '';",
        "const summary = valid ? `Deposit ${amount} ${NATIVE_SYMBOL} to shielded vault` : '';",
    ),
    (
        'Amount (ETH)',
        '{`Amount (${NATIVE_SYMBOL})`}',
    ),
    (
        "const quickAmounts = ['0.1', '0.5', '1', '5'];",
        "const quickAmounts = ['0.1', '0.5', '1', '5'];",
    ),
    (
        '{a} ETH',
        '{a} {NATIVE_SYMBOL}',
    ),
])

# ─── portfolio/page.tsx ────────────────────────────────────────────────
patch_file('app/(app)/portfolio/page.tsx', [
    (
        "import { AllocationDonut } from '@/components/AllocationDonut';",
        "import { AllocationDonut } from '@/components/AllocationDonut';\nimport { NATIVE_SYMBOL } from '@/lib/chain';",
    ),
    (
        '<span className="text-2xl text-zinc-500 ml-2">ETH</span>',
        '<span className="text-2xl text-zinc-500 ml-2">{NATIVE_SYMBOL}</span>',
    ),
    (
        "{ label: 'Shielded ETH', value: balance ?? 0, color: '#7c3aed' },",
        "{ label: `Shielded ${NATIVE_SYMBOL}`, value: balance ?? 0, color: '#7c3aed' },",
    ),
    (
        'Only one asset class (shielded ETH) exists in this build.',
        'Only one asset class (shielded native currency) exists in this build.',
    ),
])

# ─── dashboard/page.tsx ────────────────────────────────────────────────
patch_file('app/(app)/dashboard/page.tsx', [
    (
        'try a deposit',
        'try a deposit',  # placeholder, no-op
    ),
])

# ─── trading/page.tsx (chat examples) ──────────────────────────────────
patch_file('app/(app)/trading/page.tsx', [
    (
        '&quot;Send 0.5 to 0x70997…&quot;',
        '&quot;Send 0.5 to 0x70997…&quot;',  # symbol-free already
    ),
    (
        '&quot;Deposit 2 ETH&quot;',
        '&quot;Deposit 2&quot;',
    ),
])

# ─── api/chat/route.ts (AI agent prompt) ───────────────────────────────
patch_file('app/api/chat/route.ts', [
    (
        "description: 'Amount in ETH as decimal'",
        "description: 'Amount in native units (SIZE on testnet) as a decimal string'",
    ),
])

# ─── lib/tools.ts (executor result strings) ────────────────────────────
patch_file('lib/tools.ts', [
    (
        "import { fetchHistory } from './history';",
        "import { fetchHistory } from './history';\nimport { NATIVE_SYMBOL } from './chain';",
    ),
    (
        "return { ok: true, data: `${formatEther(bal)} ETH` };",
        "return { ok: true, data: `${formatEther(bal)} ${NATIVE_SYMBOL}` };",
    ),
    (
        "return { ok: true, data: `Deposited ${tc.args.amount} ETH`, hash: hash as string };",
        "return { ok: true, data: `Deposited ${tc.args.amount} ${NATIVE_SYMBOL}`, hash: hash as string };",
    ),
    (
        "return { ok: true, data: `Sent ${tc.args.amount} ETH to ${short}`, hash: hash as string };",
        "return { ok: true, data: `Sent ${tc.args.amount} ${NATIVE_SYMBOL} to ${short}`, hash: hash as string };",
    ),
    (
        "data: `Balance: ${formatEther(bal)} ETH · ${events.length} on-chain events.`,",
        "data: `Balance: ${formatEther(bal)} ${NATIVE_SYMBOL} · ${events.length} on-chain events.`,",
    ),
])

print("\nDone patching UI files.")
PYEOF

echo ""
echo "✓ Code updated to use SIZE as the native currency symbol."
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  REMAINING STEPS for your fresh wallet 0x8f6B8b1Edcb7Ed05de952Db976b3430C32A5A888"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "1. Cancel the pending 'Contract deployment' tx in MetaMask if it's"
echo "   still there. We'll do a clean redeploy with sforge."
echo ""
echo "2. Export your NEW wallet's private key:"
echo "   MetaMask → 3 dots → Account details → Show private key → copy"
echo ""
echo "3. Deploy SeismicPay.sol to the real testnet:"
echo ""
echo "   cd ~/code/ai-pay-seismic/contracts"
echo "   sforge script script/Deploy.s.sol:DeploySeismicPay \\"
echo "     --rpc-url https://testnet-1.seismictest.net/rpc \\"
echo "     --broadcast \\"
echo "     --private-key 0xYOUR_NEW_WALLET_KEY"
echo ""
echo "   Note the 'Contract Address: 0x...' line."
echo ""
echo "4. Update .env.local:"
echo "   nano ~/code/ai-pay-seismic/apps/web/.env.local"
echo ""
echo "   Set:"
echo "     NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=0x<address from step 3>"
echo "     NEXT_PUBLIC_CHAIN_ID=5124"
echo "     NEXT_PUBLIC_RPC_URL=https://testnet-1.seismictest.net/rpc"
echo "     NEXT_PUBLIC_PRIVY_APP_ID=<your existing>"
echo "     GEMINI_API_KEY=<your existing>"
echo ""
echo "5. Restart dev server (Ctrl+C, npm run dev) + hard-refresh browser"
echo ""
echo "6. Sign in with your NEW wallet (the 0x8f6B… one). All UI labels"
echo "   should now say SIZE instead of ETH."
echo ""
echo "7. Deposit 0.1 SIZE. MetaMask popup should say SIZE/SIZW (no more"
echo "   confusing ETH price). Tx should land. Balance ticks up."
echo ""
echo "8. Verify on the explorer:"
echo "   https://seismic-testnet.socialscan.io/address/0x8f6B8b1Edcb7Ed05de952Db976b3430C32A5A888"
echo "   Should show the deposit tx."
