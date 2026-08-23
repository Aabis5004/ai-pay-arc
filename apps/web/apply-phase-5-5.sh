#!/usr/bin/env bash
# apply-phase-5-5.sh
# Fix shielded balanceOf reads — pass { account } option so viem includes 'from'
# in the eth_call. Without this, msg.sender = 0x0, fails the "only owner" check.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Patching balanceOf reads to include account option…"

python3 - << 'PYEOF'
import os, re

def patch_file(path, edits):
    if not os.path.exists(path):
        print(f"  skip (missing): {path}")
        return
    with open(path, 'r') as f:
        content = f.read()
    original = content
    for find, replace in edits:
        if find in content:
            content = content.replace(find, replace)
    if content != original:
        with open(path, 'w') as f:
            f.write(content)
        print(f"  patched: {path}")
    else:
        print(f"  no change: {path}")

# components/BalanceCard.tsx
patch_file('components/BalanceCard.tsx', [
    (
        "const bal = (await contract.read.balanceOf([account.address])) as bigint;",
        "const bal = (await contract.read.balanceOf([account.address], { account: account.address })) as bigint;",
    ),
])

# app/(app)/portfolio/page.tsx
patch_file('app/(app)/portfolio/page.tsx', [
    (
        "const bal = (await contract.read.balanceOf([account.address])) as bigint;",
        "const bal = (await contract.read.balanceOf([account.address], { account: account.address })) as bigint;",
    ),
])

# lib/tools.ts (AI agent's get_balance + get_portfolio)
patch_file('lib/tools.ts', [
    (
        "const bal = (await contract.read.balanceOf([\n          account.address as Address,\n        ])) as bigint;",
        "const bal = (await contract.read.balanceOf(\n          [account.address as Address],\n          { account: account.address as Address }\n        )) as bigint;",
    ),
])

# Alternative tools.ts pattern (in case formatting differs)
patch_file('lib/tools.ts', [
    (
        "const bal = (await contract.read.balanceOf([account.address as Address])) as bigint;",
        "const bal = (await contract.read.balanceOf([account.address as Address], { account: account.address as Address })) as bigint;",
    ),
])

print("Done.")
PYEOF

echo ""
echo "✓ Patches applied. Now restart the dev server:"
echo ""
echo "  Ctrl+C in your npm run dev terminal, then:"
echo "  rm -rf .next && npm run dev"
echo ""
echo "Then hard-refresh the browser (Ctrl+Shift+R). Balance should load."
