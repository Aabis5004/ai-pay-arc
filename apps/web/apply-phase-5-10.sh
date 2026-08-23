#!/usr/bin/env bash
# apply-phase-5-10.sh
# Switch transfer/withdraw from shielded signed calls (TxSeismic format)
# to plain writeContract. This makes them work on local sanvil.
#
# Deposit stays unchanged (already works).
# Privacy: amounts in transfers/withdraws become visible in calldata, but
# the shielded BALANCE storage on-chain is still private.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Backing up files…"
cp lib/tools.ts lib/tools.ts.bak 2>/dev/null || true
cp "app/(app)/send/page.tsx" "app/(app)/send/page.tsx.bak" 2>/dev/null || true

echo "→ Patching lib/tools.ts and send page to use plain writeContract…"

python3 - << 'PYEOF'
import os, re

def patch_file(path):
    if not os.path.exists(path):
        print(f"  ! missing: {path}")
        return False
    with open(path) as f:
        c = f.read()
    orig = c

    # PATTERN 1: transfer via getShieldedContract → plain writeContract
    # Match the entire block from getShieldedContract to contract.write.transfer
    c = re.sub(
        r"const contract = getShieldedContract\(\{[^}]*\}\);\s*\n(\s+)const hash = (?:\(await \(?)?(?:await )?(?:contract\.write\.transfer|\(contract as any\)\.write\.transfer)\(\s*\[\s*([^,\]]+?)\s*(?:as Address\s*)?,\s*parseEther\(([^)]+)\)\s*\]\s*\)\)?(?:\s*as `?0x\$\{string\}`?)?;?",
        r"""const hash = (await walletClient.writeContract({
\1  address: seismicPay.address as Address,
\1  abi: seismicPay.abi,
\1  functionName: 'transfer',
\1  args: [\2 as Address, parseEther(\3)],
\1})) as `0x${string}`;""",
        c
    )

    # PATTERN 2: withdraw via getShieldedContract → plain writeContract
    c = re.sub(
        r"const contract = getShieldedContract\(\{[^}]*\}\);\s*\n(\s+)const hash = (?:\(await \(?)?(?:await )?(?:contract\.write\.withdraw|\(contract as any\)\.write\.withdraw)\(\s*\[\s*parseEther\(([^)]+)\)\s*\]\s*\)\)?(?:\s*as `?0x\$\{string\}`?)?;?",
        r"""const hash = (await walletClient.writeContract({
\1  address: seismicPay.address as Address,
\1  abi: seismicPay.abi,
\1  functionName: 'withdraw',
\1  args: [parseEther(\2)],
\1})) as `0x${string}`;""",
        c
    )

    if c != orig:
        with open(path, 'w') as f:
            f.write(c)
        print(f"  ✓ patched: {path}")
        return True
    else:
        print(f"  · no match in: {path} (may already be patched or have different pattern)")
        return False

patched_count = 0
if patch_file('lib/tools.ts'):
    patched_count += 1
if patch_file('app/(app)/send/page.tsx'):
    patched_count += 1

if patched_count == 0:
    print("\n  ⚠ No files were patched. The code might use a different pattern.")
    print("  Run this to see the current shape of the send code:")
    print("    grep -n 'getShieldedContract\\|write.transfer\\|write.withdraw' lib/tools.ts app/\\(app\\)/send/page.tsx")
PYEOF

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE. Restart dev server:"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Ctrl+C in npm run dev, then:"
echo "    npm run dev"
echo ""
echo "  Hard-refresh browser: Ctrl+Shift+R"
echo ""
echo "  Now try send via AI agent again. The MetaMask popup will be"
echo "  a NORMAL transaction (with To: contract address, Amount, Gas) —"
echo "  not the 'TxSeismic' signed-data warning."
echo "  Click Confirm. Tx broadcasts to sanvil. Balance updates."
echo ""
echo "  If patching didn't work (no files changed), paste me:"
echo "    grep -n 'getShieldedContract' lib/tools.ts"
echo "  and I'll do it by hand."
