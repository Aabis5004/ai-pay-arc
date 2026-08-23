#!/usr/bin/env bash
# add-card-registry.sh
# Adds a real on-chain card-number → wallet-address registry, so the Card can
# send by CARD NUMBER (not 0x address).
#
#   1. contracts/src/CardRegistry.sol  — register(cardNumber) + addressOf(cardNumber)
#   2. deploy it to local sanvil, extract ABI, add address to .env.local
#   3. SEED 3 anvil test accounts with card numbers (so you have cards to send to)
#   4. lib/cardRegistry.ts  — register + lookup helpers
#   5. wire Card UI: 'Register card' button + Send modal takes a CARD NUMBER
#
# Requires sanvil running. Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC="http://127.0.0.1:8545"
CONTRACTS_DIR="$HOME/code/ai-pay-seismic/contracts"
WEB_DIR="$HOME/code/ai-pay-seismic/apps/web"

export PATH="$HOME/.seismic/bin:$PATH"
cd "$WEB_DIR"

if ! command -v sforge &>/dev/null; then echo "ERROR: sforge not on PATH"; exit 1; fi
if ! curl -s --max-time 2 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC" | grep -q result; then
  echo "ERROR: sanvil not running. Start it: sanvil --state ~/.anvil"; exit 1
fi

# Card-number derivation MUST match the frontend (cardNumberFromAddress).
# We compute it in bash/python for seeding so seeded cards match what the UI shows.
card_number_for() {
  python3 - "$1" <<'PYEOF'
import sys
addr = sys.argv[1].lower().replace('0x','')
digits = ''
for ch in addr:
    try: v = int(ch, 16)
    except ValueError: continue
    digits += str(v % 10)
    if len(digits) >= 16: break
digits = (digits + '4242424242424242')[:16]
print(digits)  # raw 16-digit, no spaces (registry stores the number)
PYEOF
}

# ───────────────────────────────────────────────
# 1. Contract
# ───────────────────────────────────────────────
echo "→ 1/5 Writing CardRegistry.sol…"
cat > "$CONTRACTS_DIR/src/CardRegistry.sol" <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CardRegistry
/// @notice Maps a 16-digit card number to a wallet address.
///         Each wallet registers its own card number; lookups resolve a card
///         number back to the owning address so payments can route by card.
contract CardRegistry {
    mapping(uint256 => address) private _cardToAddr;
    mapping(address => uint256) private _addrToCard;

    event Registered(address indexed owner, uint256 indexed cardNumber);

    /// @notice Register the caller's card number. Overwrites caller's prior card.
    function register(uint256 cardNumber) external {
        require(cardNumber != 0, "card=0");
        address existing = _cardToAddr[cardNumber];
        require(existing == address(0) || existing == msg.sender, "card taken");

        // clear old mapping if caller re-registers a different number
        uint256 prev = _addrToCard[msg.sender];
        if (prev != 0 && prev != cardNumber) {
            delete _cardToAddr[prev];
        }

        _cardToAddr[cardNumber] = msg.sender;
        _addrToCard[msg.sender] = cardNumber;
        emit Registered(msg.sender, cardNumber);
    }

    /// @notice Resolve a card number to its owner address (address(0) if unset).
    function addressOf(uint256 cardNumber) external view returns (address) {
        return _cardToAddr[cardNumber];
    }

    /// @notice Get the card number registered by an address (0 if none).
    function cardOf(address owner) external view returns (uint256) {
        return _addrToCard[owner];
    }
}
SOL
echo "  ✓ CardRegistry.sol"

# Deploy script
cat > "$CONTRACTS_DIR/script/DeployRegistry.s.sol" <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CardRegistry} from "../src/CardRegistry.sol";

contract DeployRegistry is Script {
    function run() external returns (CardRegistry reg) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        reg = new CardRegistry();
        console.log("CardRegistry deployed at:", address(reg));
        vm.stopBroadcast();
    }
}
SOL

# ───────────────────────────────────────────────
# 2. Compile + deploy
# ───────────────────────────────────────────────
echo "→ 2/5 Compiling + deploying registry…"
cd "$CONTRACTS_DIR"
sforge build --skip-tests 2>&1 | tail -3

DEPLOY_OUT=$(PRIVATE_KEY="$ANVIL_KEY" sforge script script/DeployRegistry.s.sol:DeployRegistry \
  --rpc-url "$RPC" --broadcast --skip-simulation 2>&1)
REG_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "CardRegistry deployed at: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $4}')
if [ -z "$REG_ADDR" ]; then
  REG_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "Contract Address: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
fi
if [ -z "$REG_ADDR" ]; then
  echo "  ✗ registry deploy failed:"; echo "$DEPLOY_OUT" | tail -20; exit 1
fi
echo "  ✓ CardRegistry at $REG_ADDR"

# Extract ABI
python3 - <<PYEOF
import json
d = json.load(open("$CONTRACTS_DIR/out/CardRegistry.sol/CardRegistry.json"))
abi = d["abi"]
open("$WEB_DIR/abi/CardRegistry.ts","w").write(
  "export const cardRegistryAbi = " + json.dumps(abi, indent=2) + " as const;\n")
print("  ✓ ABI → abi/CardRegistry.ts")
PYEOF

# env
cd "$WEB_DIR"
if grep -q '^NEXT_PUBLIC_CARD_REGISTRY=' .env.local; then
  sed -i "s|^NEXT_PUBLIC_CARD_REGISTRY=.*|NEXT_PUBLIC_CARD_REGISTRY=$REG_ADDR|" .env.local
else
  echo "NEXT_PUBLIC_CARD_REGISTRY=$REG_ADDR" >> .env.local
fi
echo "  ✓ env: NEXT_PUBLIC_CARD_REGISTRY=$REG_ADDR"

# ───────────────────────────────────────────────
# 3. Seed test accounts (anvil accounts 1,2,3)
# ───────────────────────────────────────────────
echo "→ 3/5 Seeding test cards…"
# anvil deterministic accounts 1,2,3
declare -A SEED
SEED["0x70997970C51812dc3A010C7d01b50e0d17dc79C8"]="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
SEED["0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"]="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
SEED["0x90F79bf6EB2c4f870365E785982E1f101E93b906"]="0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

for ADDR in "${!SEED[@]}"; do
  KEY="${SEED[$ADDR]}"
  CARD=$(card_number_for "$ADDR")
  echo "    registering $ADDR → card $CARD"
  scast send "$REG_ADDR" "register(uint256)" "$CARD" \
    --rpc-url "$RPC" --private-key "$KEY" >/dev/null 2>&1 || echo "      (skip: maybe already registered)"
done
echo "  ✓ seeded 3 test cards"

# Print the seeded card numbers (grouped) so the user can send to them
echo ""
echo "  Test cards you can send to:"
for ADDR in "${!SEED[@]}"; do
  CARD=$(card_number_for "$ADDR")
  GROUPED=$(echo "$CARD" | sed 's/\(....\)/\1 /g')
  echo "    $GROUPED   (→ ${ADDR:0:6}…${ADDR: -4})"
done

# ───────────────────────────────────────────────
# 4. lib/cardRegistry.ts
# ───────────────────────────────────────────────
echo ""
echo "→ 4/5 Creating lib/cardRegistry.ts…"
cat > lib/cardRegistry.ts <<'TS'
'use client';
// lib/cardRegistry.ts — register a card number on-chain + resolve card → address.

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

// raw 16-digit string → bigint
export function cardToBigInt(card: string): bigint {
  const digits = card.replace(/\D/g, '');
  if (!digits) return 0n;
  return BigInt(digits);
}

export function isRegistryConfigured(): boolean {
  return !!REGISTRY;
}

/** Resolve a card number (any format) to the owning wallet address, or null. */
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

/** Get the card number an address has registered (0n if none). */
export async function cardOf(addr: Address): Promise<bigint> {
  if (!REGISTRY) return 0n;
  return (await pub().readContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'cardOf', args: [addr],
  })) as bigint;
}

/** Register the caller's own card number on-chain. */
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
# 5. Patch cardTx + modal to send by card number
# ───────────────────────────────────────────────
echo "→ 5/5 Wiring Send modal to resolve card numbers…"

# Add a cardSendByNumber to cardTx.ts
python3 - <<'PYEOF'
p = 'lib/cardTx.ts'
with open(p) as f: c = f.read()
if 'cardSendByNumber' not in c:
    c = c.replace(
        "import { ACTIVE_CHAIN } from './chain';",
        "import { ACTIVE_CHAIN } from './chain';\nimport { resolveCard } from './cardRegistry';"
    )
    c += '''

// Send by CARD NUMBER: resolve to address via on-chain registry, then transfer.
export async function cardSendByNumber(
  provider: Provider, account: Address, cardNumber: string, amount: string,
): Promise<`0x${string}`> {
  const to = await resolveCard(cardNumber);
  if (!to) throw new Error('That card number is not registered on-chain.');
  return cardSend(provider, account, to, amount);
}
'''
    with open(p,'w') as f: f.write(c)
    print("  ✓ cardSendByNumber added to lib/cardTx.ts")
else:
    print("  · cardSendByNumber already present")
PYEOF

# Patch the modal: Send now takes a card number; add Register handling
python3 - <<'PYEOF'
p = 'components/CardActionModal.tsx'
with open(p) as f: c = f.read()
orig = c

# import the new helpers
if 'cardSendByNumber' not in c:
    c = c.replace(
        "import { cardDeposit, cardSend } from '@/lib/cardTx';",
        "import { cardDeposit, cardSendByNumber } from '@/lib/cardTx';\nimport { registerCard } from '@/lib/cardRegistry';"
    )

# change the send state var label & input from address → card number
c = c.replace(
    'const [to, setTo] = useState(\'\');',
    "const [to, setTo] = useState(''); // recipient CARD NUMBER now"
)

# Replace the send branch to call cardSendByNumber
c = c.replace(
    """        setPhase({ s: 'working', label: 'Sending from card…' });
        const hash = await cardSend(provider as never, address as Address, to, amount);
        setPhase({ s: 'done', hash });""",
    """        setPhase({ s: 'working', label: 'Sending from card…' });
        const hash = await cardSendByNumber(provider as never, address as Address, to, amount);
        setPhase({ s: 'done', hash });"""
)

# Update the recipient input label + placeholder to card number
c = c.replace(
    '<label className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1.5 block">Recipient address</label>',
    '<label className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1.5 block">Recipient card number</label>'
)
c = c.replace(
    'value={to} onChange={(e) => setTo(e.target.value.trim())} placeholder="0x…"',
    'value={to} onChange={(e) => setTo(e.target.value)} placeholder="5815 8051 0010 7009"'
)
# validation msg
c = c.replace(
    "if (!to) { setPhase({ s: 'error', msg: 'Enter a recipient address.' }); return; }",
    "if (!to.replace(/\\\\D/g,'')) { setPhase({ s: 'error', msg: 'Enter a recipient card number.' }); return; }"
)

if c != orig:
    with open(p,'w') as f: f.write(c)
    print("  ✓ Send modal now uses card numbers")
else:
    print("  · modal unchanged (check patterns)")
PYEOF

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — on-chain card registry live"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Registry: $REG_ADDR"
echo ""
echo "  Ctrl+C npm run dev, then 'npm run dev', hard-refresh."
echo ""
echo "  HOW TO USE:"
echo "    1. On the Card page, click 'Register card' (one tx) so your"
echo "       own card number is registered → others can pay you by card."
echo "    2. Click Send → enter a RECIPIENT CARD NUMBER → amount → send."
echo "       The app looks up the card's address on-chain and transfers."
echo ""
echo "  Pre-seeded test cards (shown above) are ready to receive."
echo "  Try sending to one of them to confirm card-number routing works."
echo ""
echo "  NOTE: a 'Register card' button is added in the next step — if you"
echo "  don't see it, tell me and I'll wire the button onto the card page."
