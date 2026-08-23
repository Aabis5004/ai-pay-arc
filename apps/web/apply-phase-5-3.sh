#!/usr/bin/env bash
# apply-phase-5-3.sh
# Migrate from legacy devnet (seismicdev.net) to the REAL public testnet (seismictest.net)
# Both use chain ID 5124 but they're entirely different chains — the Seismic team
# migrated infra and seismic-viem's default chain config still points at the old one.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Updating lib/explorer.ts to use seismic-testnet.socialscan.io…"
cat > lib/explorer.ts << '___F_EXPLORER___'
import { sanvil } from 'seismic-viem';

export function explorerTxUrl(hash: string, chainId: number): string | null {
  if (chainId === sanvil.id) return null;
  if (chainId === 5124) return `https://seismic-testnet.socialscan.io/tx/${hash}`;
  return null;
}

export function explorerAddressUrl(addr: string, chainId: number): string | null {
  if (chainId === sanvil.id) return null;
  if (chainId === 5124) return `https://seismic-testnet.socialscan.io/address/${addr}`;
  return null;
}
___F_EXPLORER___

echo "→ Backing up old .env.local to .env.local.devnet-backup…"
if [ -f ".env.local" ]; then
  cp .env.local .env.local.devnet-backup
fi

echo "→ Writing .env.local pointed at the real testnet (your existing keys preserved)…"
# Preserve PRIVY and GEMINI keys from existing env, overwrite the chain config
PRIVY_ID="$(grep '^NEXT_PUBLIC_PRIVY_APP_ID=' .env.local 2>/dev/null | cut -d'=' -f2- || echo 'cmq4zea0d001v0cjuai9dl5mh')"
GEMINI_KEY="$(grep '^GEMINI_API_KEY=' .env.local 2>/dev/null | cut -d'=' -f2- || echo '')"

cat > .env.local << ___F_ENV___
# === Seismic Public Testnet (the REAL one, per https://docs.seismic.systems) ===
NEXT_PUBLIC_CHAIN_ID=5124
NEXT_PUBLIC_RPC_URL=https://testnet-1.seismictest.net/rpc

# === Contract — UPDATE THIS after redeploying to the new testnet (step 4 below) ===
NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=

# === Auth + AI (preserved from your existing config) ===
NEXT_PUBLIC_PRIVY_APP_ID=${PRIVY_ID}
GEMINI_API_KEY=${GEMINI_KEY}
___F_ENV___

echo ""
echo "✓ Code + env updated."
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  REMAINING STEPS — do these in order"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "1. Update MetaMask network — DELETE the old 'Seismic Testnet' entry"
echo "   (the one pointing at node-2.seismicdev.net) and re-add a fresh one:"
echo ""
echo "     Network name: Seismic Testnet"
echo "     RPC URL:      https://testnet-1.seismictest.net/rpc"
echo "     Chain ID:     5124"
echo "     Symbol:       ETH"
echo "     Explorer:     https://seismic-testnet.socialscan.io"
echo ""
echo "   (Same chain ID as before, but the wallet caches the RPC URL —"
echo "    you'll keep talking to the dead devnet otherwise.)"
echo ""
echo "2. Get NEW testnet ETH from the real faucet"
echo "   Open https://faucet.seismictest.net/"
echo "   Paste 0x581F8aFBa0Ba7aa93c662e730559b63479BA70E3"
echo "   Note: this faucet may require X (Twitter) follower ≥50 OR"
echo "   github follower ≥10 to claim, per the Aabis tweet."
echo ""
echo "3. Verify the new RPC actually answers:"
echo "   curl -s -X POST -H 'Content-Type: application/json' \\"
echo "     --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \\"
echo "     https://testnet-1.seismictest.net/rpc"
echo "   You should see a result with a recent block number (hex)."
echo ""
echo "4. Redeploy the contract to the REAL testnet"
echo "   cd ~/code/ai-pay-seismic/contracts"
echo "   sforge script script/Deploy.s.sol:DeploySeismicPay \\"
echo "     --rpc-url https://testnet-1.seismictest.net/rpc \\"
echo "     --broadcast \\"
echo "     --private-key 0xYOUR_EXPORTED_KEY"
echo ""
echo "   Copy the 'Contract Address: 0x...' line from the output."
echo ""
echo "5. Paste the new contract address into .env.local:"
echo "   nano ~/code/ai-pay-seismic/apps/web/.env.local"
echo "   Set NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=0x<address from step 4>"
echo ""
echo "6. Restart dev server (Ctrl+C, npm run dev) + hard-refresh browser"
echo ""
echo "7. Verify everything:"
echo "   · Balance card loads 0.0000 ETH (no '—', no error box)"
echo "   · Try a 0.1 ETH deposit"
echo "   · Click the explorer link in the tx modal → should open"
echo "     seismic-testnet.socialscan.io with your real tx visible"
echo "   · Search your address 0x581F...70E3 on socialscan.io —"
echo "     should show the deposit"
echo ""
echo "Backup of your old config is at .env.local.devnet-backup if needed."
