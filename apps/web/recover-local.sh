#!/usr/bin/env bash
# recover-local.sh
# Sanvil state got wiped. This script:
#   1. Refunds your wallet (0x581F...A70E3) with 10 ETH
#   2. Checks if the contract still exists at the env address
#   3. If not, redeploys + auto-updates .env.local with new address
#
# Run from anywhere. Needs sanvil already running on 127.0.0.1:8545.
set -euo pipefail

USER_WALLET="0x581F8aFBa0Ba7aa93c662e730559b63479BA70E3"
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC="http://127.0.0.1:8545"
CONTRACTS_DIR="$HOME/code/ai-pay-seismic/contracts"
WEB_DIR="$HOME/code/ai-pay-seismic/apps/web"

export PATH="$HOME/.seismic/bin:$PATH"

# Sanity checks
if ! command -v scast &>/dev/null || ! command -v sforge &>/dev/null; then
  echo "ERROR: scast/sforge not on PATH. Run: export PATH=\"\$HOME/.seismic/bin:\$PATH\""
  exit 1
fi

if ! curl -s --max-time 2 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC | grep -q result; then
  echo "ERROR: sanvil isn't running on $RPC"
  echo "Start it first in another terminal: sanvil --state ~/.anvil"
  exit 1
fi

# 1. Refund the user's wallet
echo "→ 1/3 Refunding $USER_WALLET with 10 ETH…"
scast send "$USER_WALLET" \
  --value 10ether \
  --rpc-url "$RPC" \
  --private-key "$ANVIL_KEY" >/dev/null

NEW_BAL=$(scast balance "$USER_WALLET" --rpc-url "$RPC" --ether)
echo "  ✓ wallet balance: $NEW_BAL ETH"

# 2. Check current contract address from env
CURRENT_ADDR=$(grep -E '^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=' "$WEB_DIR/.env.local" 2>/dev/null | sed 's/^[^=]*=//')
if [ -z "$CURRENT_ADDR" ]; then
  echo "  no contract address in env — will deploy fresh"
  CONTRACT_EXISTS=0
else
  echo "→ 2/3 Checking if contract still exists at $CURRENT_ADDR…"
  CODE=$(scast code "$CURRENT_ADDR" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" = "0x" ] || [ -z "$CODE" ]; then
    echo "  ✗ contract is gone (sanvil state wiped). Will redeploy."
    CONTRACT_EXISTS=0
  else
    echo "  ✓ contract still there. No redeploy needed."
    CONTRACT_EXISTS=1
  fi
fi

# 3. Redeploy if needed
if [ "$CONTRACT_EXISTS" = "0" ]; then
  echo "→ 3/3 Redeploying contract…"
  cd "$CONTRACTS_DIR"
  DEPLOY_OUT=$(sforge script script/Deploy.s.sol:DeploySeismicPay \
    --rpc-url "$RPC" \
    --broadcast \
    --skip-simulation \
    --private-key "$ANVIL_KEY" 2>&1)
  echo "$DEPLOY_OUT" | tail -15

  NEW_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "Contract Address: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
  if [ -z "$NEW_ADDR" ]; then
    NEW_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "deployed at: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
  fi
  if [ -z "$NEW_ADDR" ]; then
    echo ""
    echo "ERROR: couldn't extract new contract address. Check the output above and run manually:"
    echo "  sed -i 's|^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=.*|NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=0xYOUR_ADDR|' $WEB_DIR/.env.local"
    exit 1
  fi

  echo "  ✓ new contract address: $NEW_ADDR"
  sed -i "s|^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=.*|NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=$NEW_ADDR|" "$WEB_DIR/.env.local"
  echo "  ✓ .env.local updated"
  rm -rf "$WEB_DIR/.next"
  echo "  ✓ Next.js cache cleared"
else
  echo "→ 3/3 Skipped (contract already deployed)"
fi

echo ""
echo "════════════════════════════════════════════════"
echo "  RECOVERED. Now do these:"
echo "════════════════════════════════════════════════"
echo ""
echo "  1. In your npm run dev terminal: Ctrl+C, then 'npm run dev'"
echo "  2. Browser: Ctrl+Shift+R"
echo "  3. MetaMask should now show 10 ETH on Seismic Local"
echo "  4. Try a 0.1 deposit. Balance card should update."
echo ""
echo "TIP: to prevent this happening again, ALWAYS start sanvil with:"
echo "       sanvil --state ~/.anvil"
echo "     and never close the sanvil terminal."
