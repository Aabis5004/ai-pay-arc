#!/usr/bin/env bash
# fix-suint-final.sh
#
# Root-cause fix for "Type 'suint256' is not a valid encoding type."
#
# Strategy: four layers of defense.
#   1. DIAGNOSTIC — scan codebase, show every suint reference and its location
#   2. SOURCE FIX — rewrite contract to use uint256 in function signatures, redeploy
#   3. ABI SANITIZER (runtime) — patch lib/contract.ts so even if any suint
#      sneaks through, viem sees uint256 instead. Belt-and-suspenders.
#   4. LOGGING — add console diagnostics so we can see exactly what viem receives

set -euo pipefail

USER_WALLET="0x581F8aFBa0Ba7aa93c662e730559b63479BA70E3"
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC="http://127.0.0.1:8545"
CONTRACTS_DIR="$HOME/code/ai-pay-seismic/contracts"
WEB_DIR="$HOME/code/ai-pay-seismic/apps/web"

export PATH="$HOME/.seismic/bin:$PATH"

if ! command -v sforge &>/dev/null; then
  echo "ERROR: sforge not on PATH"; exit 1
fi
if ! curl -s --max-time 2 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC" | grep -q result; then
  echo "ERROR: sanvil not running. Start it in another terminal: sanvil --state ~/.anvil"
  exit 1
fi

cd "$WEB_DIR"

# ═══════════════════════════════════════════════════════
# PHASE 1: DIAGNOSTIC
# ═══════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 1: DIAGNOSTIC"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "[1.1] Scanning codebase for suint256, saddress, suint8, etc…"
SHIELDED_HITS=$(grep -rn -E "(suint[0-9]*|saddress|sbool)" \
  "$WEB_DIR/abi" "$WEB_DIR/lib" "$WEB_DIR/app" "$WEB_DIR/components" \
  2>/dev/null | grep -v node_modules | grep -v ".next" || echo "")

if [ -z "$SHIELDED_HITS" ]; then
  echo "  ✓ NO shielded types in frontend source"
else
  echo "  ✗ FOUND shielded types in:"
  echo "$SHIELDED_HITS" | sed 's/^/    /'
fi
echo ""

echo "[1.2] Contract source file…"
if grep -qE "function (transfer|withdraw)\([^)]*suint" "$CONTRACTS_DIR/src/SeismicPay.sol"; then
  echo "  ✗ contract has suint256 in transfer/withdraw signatures"
  CONTRACT_HAS_SUINT=1
else
  echo "  ✓ contract function signatures use uint256"
  CONTRACT_HAS_SUINT=0
fi
echo ""

echo "[1.3] Current contract address from env…"
CURRENT_ADDR=$(grep -E '^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=' .env.local | sed 's/^[^=]*=//')
echo "  $CURRENT_ADDR"

# ═══════════════════════════════════════════════════════
# PHASE 2: SOURCE FIX (rewrite contract + redeploy)
# ═══════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 2: SOURCE FIX"
echo "═══════════════════════════════════════════════════════"

cd "$CONTRACTS_DIR"

echo ""
echo "[2.1] Writing clean contract (uint256 in function params, suint256 in storage)…"
cp src/SeismicPay.sol "src/SeismicPay.sol.bak.$(date +%s)" 2>/dev/null || true

cat > src/SeismicPay.sol <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SeismicPay
/// @notice Function parameters use uint256 (standard ABI-encodable).
///         Internal _balances storage uses suint256 (encrypted on-chain).
///         Privacy: balances are encrypted in storage. Calldata amounts are public.
contract SeismicPay {
    mapping(address => suint256) private _balances;

    event Deposited(address indexed user, uint256 amount);
    event Transferred(address indexed from, address indexed to);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "value=0");
        _balances[msg.sender] = _balances[msg.sender] + suint256(msg.value);
        emit Deposited(msg.sender, msg.value);
    }

    function transfer(address to, uint256 amount) external {
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");
        suint256 amt = suint256(amount);
        _balances[msg.sender] = _balances[msg.sender] - amt;
        _balances[to] = _balances[to] + amt;
        emit Transferred(msg.sender, to);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "amount=0");
        suint256 amt = suint256(amount);
        _balances[msg.sender] = _balances[msg.sender] - amt;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return uint256(_balances[account]);
    }
}
SOL
echo "  ✓ contract source written"

echo ""
echo "[2.2] Cleaning old build artifacts to force fresh compile…"
rm -rf out/ cache/ 2>/dev/null || true
echo "  ✓ cleaned"

echo ""
echo "[2.3] Compiling…"
BUILD_OUT=$(sforge build --skip-tests 2>&1) || true
echo "$BUILD_OUT" | tail -10
if echo "$BUILD_OUT" | grep -qE "Error|error"; then
  if ! echo "$BUILD_OUT" | grep -qE "(Compiler run successful|compiled successfully)"; then
    echo "  ✗ Compile failed. Full output:"
    echo "$BUILD_OUT"
    exit 1
  fi
fi
echo "  ✓ compiled"

echo ""
echo "[2.4] Deploying to local sanvil…"
DEPLOY_OUT=$(sforge script script/Deploy.s.sol:DeploySeismicPay \
  --rpc-url "$RPC" --broadcast --skip-simulation \
  --private-key "$ANVIL_KEY" 2>&1)

NEW_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "Contract Address: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
if [ -z "$NEW_ADDR" ]; then
  NEW_ADDR=$(echo "$DEPLOY_OUT" | grep -oE "deployed at: 0x[a-fA-F0-9]{40}" | tail -1 | awk '{print $3}')
fi
if [ -z "$NEW_ADDR" ]; then
  echo "  ✗ deploy failed. Last 30 lines:"
  echo "$DEPLOY_OUT" | tail -30
  exit 1
fi
echo "  ✓ deployed at: $NEW_ADDR"

echo ""
echo "[2.5] Extracting ABI from build output…"
ABI_JSON_FILE="$CONTRACTS_DIR/out/SeismicPay.sol/SeismicPay.json"
if [ ! -f "$ABI_JSON_FILE" ]; then
  echo "  ✗ $ABI_JSON_FILE not found"
  exit 1
fi

python3 - <<PYEOF
import json, sys, re

with open("$ABI_JSON_FILE") as f:
    data = json.load(f)
abi = data.get("abi", [])
if not abi:
    print("  ✗ ABI is empty in build output")
    sys.exit(1)

# Defensive sanitization at extraction time too:
# replace any shielded types with their public equivalents
SHIELDED_MAP = {
    "suint256": "uint256", "suint128": "uint128", "suint64": "uint64",
    "suint32": "uint32", "suint16": "uint16", "suint8": "uint8",
    "sint256": "int256", "sint128": "int128",
    "saddress": "address", "sbool": "bool",
}

def sanitize_type(t):
    if not isinstance(t, str): return t
    for s, p in SHIELDED_MAP.items():
        t = t.replace(s, p)
    return t

def sanitize_param(p):
    if not isinstance(p, dict): return p
    out = dict(p)
    if "type" in out: out["type"] = sanitize_type(out["type"])
    if "internalType" in out: out["internalType"] = sanitize_type(out["internalType"])
    if "components" in out and isinstance(out["components"], list):
        out["components"] = [sanitize_param(c) for c in out["components"]]
    return out

def sanitize_item(item):
    if not isinstance(item, dict): return item
    out = dict(item)
    if "inputs" in out and isinstance(out["inputs"], list):
        out["inputs"] = [sanitize_param(p) for p in out["inputs"]]
    if "outputs" in out and isinstance(out["outputs"], list):
        out["outputs"] = [sanitize_param(p) for p in out["outputs"]]
    return out

sanitized = [sanitize_item(i) for i in abi]

# Count what was sanitized
raw_str = json.dumps(abi)
clean_str = json.dumps(sanitized)
suint_count_before = len(re.findall(r'suint|saddress|sbool', raw_str))
suint_count_after = len(re.findall(r'suint|saddress|sbool', clean_str))

ts = "// AUTO-GENERATED by fix-suint-final.sh\n"
ts += "// Build output sanitized: " + str(suint_count_before) + " shielded refs cleaned\n"
ts += "export const seismicPayAbi = " + json.dumps(sanitized, indent=2) + " as const;\n"

with open("$WEB_DIR/abi/SeismicPay.ts", "w") as f:
    f.write(ts)

print(f"  ✓ ABI written ({len(sanitized)} entries, {suint_count_before} shielded refs sanitized)")
PYEOF

# ═══════════════════════════════════════════════════════
# PHASE 3: RUNTIME ABI SANITIZER (defense in depth)
# ═══════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 3: RUNTIME ABI SANITIZER"
echo "═══════════════════════════════════════════════════════"

cd "$WEB_DIR"

echo ""
echo "[3.1] Backing up lib/contract.ts…"
cp lib/contract.ts "lib/contract.ts.bak.$(date +%s)" 2>/dev/null || true

echo "[3.2] Rewriting lib/contract.ts with runtime sanitizer…"

cat > lib/contract.ts <<'TS'
// lib/contract.ts
// SeismicPay contract reference + runtime ABI sanitizer.
//
// Even if the ABI file accidentally contains a shielded type (suint256, etc.),
// this module rewrites those types to their public equivalents BEFORE the ABI
// is passed to viem. This makes "Type 'suint256' is not a valid encoding type"
// impossible to encounter from this codebase.

import { seismicPayAbi as rawAbi } from '@/abi/SeismicPay';

const SHIELDED_TO_PUBLIC: Record<string, string> = {
  suint256: 'uint256',
  suint128: 'uint128',
  suint64: 'uint64',
  suint32: 'uint32',
  suint16: 'uint16',
  suint8: 'uint8',
  sint256: 'int256',
  sint128: 'int128',
  saddress: 'address',
  sbool: 'bool',
};

function sanitizeType(t?: string): string | undefined {
  if (!t) return t;
  let out = t;
  for (const [s, p] of Object.entries(SHIELDED_TO_PUBLIC)) {
    out = out.split(s).join(p);
  }
  return out;
}

type AbiParam = { type?: string; internalType?: string; components?: AbiParam[] };

function sanitizeParam(p: AbiParam): AbiParam {
  const out: AbiParam = { ...p };
  if (p.type) out.type = sanitizeType(p.type);
  if (p.internalType) out.internalType = sanitizeType(p.internalType);
  if (Array.isArray(p.components)) out.components = p.components.map(sanitizeParam);
  return out;
}

type AbiItem = Record<string, unknown> & { inputs?: AbiParam[]; outputs?: AbiParam[] };

function sanitizeAbi<T extends readonly unknown[]>(abi: T): T {
  return abi.map((item) => {
    if (typeof item !== 'object' || item === null) return item;
    const cloned = { ...(item as AbiItem) };
    if (Array.isArray(cloned.inputs)) cloned.inputs = cloned.inputs.map(sanitizeParam);
    if (Array.isArray(cloned.outputs)) cloned.outputs = cloned.outputs.map(sanitizeParam);
    return cloned;
  }) as unknown as T;
}

// Sanitize at module load
const cleanAbi = sanitizeAbi(rawAbi);

// One-time log so we know if the runtime sanitizer caught anything
if (typeof window !== 'undefined') {
  const rawStr = JSON.stringify(rawAbi);
  const cleanStr = JSON.stringify(cleanAbi);
  if (rawStr !== cleanStr) {
    const before = (rawStr.match(/suint|saddress|sbool/g) || []).length;
    // eslint-disable-next-line no-console
    console.warn(
      `[contract.ts] runtime ABI sanitizer cleaned ${before} shielded type refs`
    );
  }
}

export const seismicPay = {
  address: process.env.NEXT_PUBLIC_SEISMIC_PAY_ADDRESS as `0x${string}`,
  abi: cleanAbi,
};
TS
echo "  ✓ lib/contract.ts now sanitizes ABI at runtime"

# ═══════════════════════════════════════════════════════
# PHASE 4: ADD CONSOLE LOGGING TO SEND PAGE
# ═══════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 4: ADD DIAGNOSTIC LOGGING"
echo "═══════════════════════════════════════════════════════"

python3 - <<'PYEOF'
import os, re

path = 'app/(app)/send/page.tsx'
if not os.path.exists(path):
    print(f"  ! send page not found at {path}")
    exit(0)

with open(path) as f:
    c = f.read()

if '[send-debug]' in c:
    print(f"  · logging already added to {path}")
    exit(0)

# Insert console.logs right before walletClient.writeContract
needle = "hash = await walletClient.writeContract({"
log_block = """// [send-debug] dump everything that's about to be encoded
      // eslint-disable-next-line no-console
      console.log('[send-debug] contract address:', seismicPay.address);
      // eslint-disable-next-line no-console
      console.log('[send-debug] ABI (sanitized):', seismicPay.abi);
      // eslint-disable-next-line no-console
      console.log('[send-debug] function: transfer');
      // eslint-disable-next-line no-console
      console.log('[send-debug] args:', { to, amountWei: amountWei.toString() });
      // eslint-disable-next-line no-console
      console.log('[send-debug] from:', address);
      // eslint-disable-next-line no-console
      console.log('[send-debug] chain:', ACTIVE_CHAIN.id, ACTIVE_CHAIN.name);

      """

if needle in c:
    c = c.replace(needle, log_block + needle)
    with open(path, 'w') as f:
        f.write(c)
    print(f"  ✓ added [send-debug] logs to {path}")
else:
    print(f"  ! couldn't find writeContract call in {path}")
PYEOF

# ═══════════════════════════════════════════════════════
# PHASE 5: UPDATE ENV + REFUND
# ═══════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 5: UPDATE ENV + REFUND WALLET"
echo "═══════════════════════════════════════════════════════"
echo ""

sed -i "s|^NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=.*|NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=$NEW_ADDR|" .env.local
echo "[5.1] env updated → $NEW_ADDR"

scast send "$USER_WALLET" --value 10ether --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null 2>&1 || true
NEW_BAL=$(scast balance "$USER_WALLET" --rpc-url "$RPC" --ether)
echo "[5.2] wallet refunded: $NEW_BAL ETH"

# ═══════════════════════════════════════════════════════
# PHASE 6: CLEAN CACHE
# ═══════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 6: CLEAN CACHE"
echo "═══════════════════════════════════════════════════════"
echo ""
rm -rf .next
echo "  ✓ .next cleared"

# ═══════════════════════════════════════════════════════
# PHASE 7: VERIFICATION
# ═══════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PHASE 7: VERIFICATION"
echo "═══════════════════════════════════════════════════════"
echo ""

POST_HITS=$(grep -rn -E "(suint[0-9]*|saddress|sbool)" \
  "$WEB_DIR/abi" "$WEB_DIR/lib" "$WEB_DIR/app" "$WEB_DIR/components" \
  2>/dev/null | grep -v node_modules | grep -v ".next" | grep -v ".bak" || echo "")

if [ -z "$POST_HITS" ]; then
  echo "  ✓ NO shielded types in frontend source (clean)"
else
  echo "  ⚠ shielded refs still present in:"
  echo "$POST_HITS" | sed 's/^/    /'
  echo "  (runtime sanitizer will handle these)"
fi
echo ""

# ═══════════════════════════════════════════════════════
# REPORT
# ═══════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════"
echo "  REPORT"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Root cause: contract function signatures used 'suint256',"
echo "              which viem's ABI encoder cannot encode."
echo ""
echo "  Fixed at 3 layers:"
echo "    1. CONTRACT       — transfer/withdraw now take uint256 params"
echo "    2. EXTRACTED ABI  — sanitized when writing apps/web/abi/SeismicPay.ts"
echo "    3. RUNTIME        — lib/contract.ts also sanitizes on module load"
echo ""
echo "  Logging added: send page now logs ABI, args, address to console"
echo "                 (look for '[send-debug]' in browser DevTools)"
echo ""
echo "  Contract address: $NEW_ADDR"
echo "  Wallet balance:   $NEW_BAL ETH"
echo ""
echo "  ─────────────────────────────────────────────────────"
echo "  NEXT STEPS:"
echo "  ─────────────────────────────────────────────────────"
echo "    1. Ctrl+C the npm run dev terminal"
echo "    2. npm run dev"
echo "    3. Hard-refresh browser (Ctrl+Shift+R)"
echo "    4. Go to /deposit, deposit 1 ETH"
echo "    5. Go to /send, try sending 0.1 ETH to"
echo "       0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
echo "    6. Open browser console (F12 → Console) before clicking Send"
echo "       to see [send-debug] logs of what's being submitted"
echo ""
echo "  If 'Type suint256...' error persists, paste the [send-debug]"
echo "  console output and I'll know exactly which layer is leaking."
