#!/usr/bin/env bash
# apply-phase-5-2.sh
# Switch the app from local sanvil to Seismic Testnet (chain 5124).
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"
  exit 1
fi

echo "→ Adding lib/chain.ts (chain selector based on env var)…"
cat > lib/chain.ts << '___F_CHAIN___'
import { sanvil, seismicDevnet } from 'seismic-viem';

const CHAIN_ID = parseInt(process.env.NEXT_PUBLIC_CHAIN_ID || '31337', 10);

export const ACTIVE_CHAIN = CHAIN_ID === 5124 ? seismicDevnet : sanvil;
export const IS_TESTNET = ACTIVE_CHAIN.id === 5124;
___F_CHAIN___

echo "→ Updating lib/wagmi.ts…"
cat > lib/wagmi.ts << '___F_WAGMI___'
import { http } from 'viem';
import { createConfig } from '@privy-io/wagmi';
import { ACTIVE_CHAIN } from './chain';

export const wagmiConfig = createConfig({
  chains: [ACTIVE_CHAIN],
  transports: {
    [ACTIVE_CHAIN.id]: http(
      process.env.NEXT_PUBLIC_RPC_URL ||
        ACTIVE_CHAIN.rpcUrls.default.http[0],
    ),
  },
});
___F_WAGMI___

echo "→ Updating lib/contract.ts…"
cat > lib/contract.ts << '___F_CONTRACT___'
import { seismicPayAbi } from '@/abi/SeismicPay';
import { ACTIVE_CHAIN } from './chain';

export const SEISMIC_PAY_ADDRESS = process.env
  .NEXT_PUBLIC_SEISMIC_PAY_ADDRESS as `0x${string}`;

export const CHAIN = ACTIVE_CHAIN;

export const seismicPay = {
  address: SEISMIC_PAY_ADDRESS,
  abi: seismicPayAbi,
} as const;
___F_CONTRACT___

echo "→ Updating lib/useShielded.ts to use ACTIVE_CHAIN…"
cat > lib/useShielded.ts << '___F_USESHIELDED___'
'use client';

import { useEffect, useState } from 'react';
import { useWallets, type ConnectedWallet } from '@privy-io/react-auth';
import { useAccount, useChainId, useWalletClient } from 'wagmi';
import { createShieldedWalletClient } from 'seismic-viem';
import { custom, type Address } from 'viem';
import { ACTIVE_CHAIN } from './chain';

/* eslint-disable @typescript-eslint/no-explicit-any */
type ShieldedClient = any;
type EthereumProvider = { request: (args: { method: string; params?: any[] }) => Promise<any> };
/* eslint-enable @typescript-eslint/no-explicit-any */

type Diag = {
  isConnected: boolean;
  address?: string;
  chainId?: number;
  expectedChainId: number;
  privyWalletsCount: number;
  hasWagmiClient: boolean;
  strategyUsed?: string;
  error?: string;
};

const RPC_URL =
  process.env.NEXT_PUBLIC_RPC_URL ||
  ACTIVE_CHAIN.rpcUrls.default.http[0];

const WALLET_METHODS = new Set([
  'eth_sign',
  'eth_signTransaction',
  'eth_sendTransaction',
  'eth_sendRawTransaction',
  'eth_signTypedData_v4',
  'eth_signTypedData_v3',
  'personal_sign',
  'eth_requestAccounts',
  'eth_accounts',
  'wallet_switchEthereumChain',
  'wallet_addEthereumChain',
  'wallet_watchAsset',
  'wallet_requestPermissions',
]);

function makeSplitProvider(wallet: EthereumProvider): EthereumProvider {
  return {
    async request({ method, params }) {
      if (WALLET_METHODS.has(method)) {
        return wallet.request({ method, params });
      }
      try {
        const res = await fetch(RPC_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            jsonrpc: '2.0',
            method,
            params: params || [],
            id: Math.floor(Math.random() * 1e9),
          }),
        });
        const json = await res.json();
        if (json.error) {
          if (method.startsWith('seismic_')) {
            throw new Error(`${json.error.message || 'rpc error'} (method=${method})`);
          }
          throw json.error;
        }
        return json.result;
      } catch (e) {
        if (method.startsWith('seismic_')) throw e;
        return wallet.request({ method, params });
      }
    },
  };
}

export function useShielded() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { wallets } = useWallets();
  const { data: wagmiClient } = useWalletClient();

  const [walletClient, setWalletClient] = useState<ShieldedClient | null>(null);
  const [diag, setDiag] = useState<Diag>({
    isConnected: false,
    expectedChainId: ACTIVE_CHAIN.id,
    privyWalletsCount: 0,
    hasWagmiClient: false,
  });

  useEffect(() => {
    let cancelled = false;
    const base: Diag = {
      isConnected,
      address,
      chainId,
      expectedChainId: ACTIVE_CHAIN.id,
      privyWalletsCount: wallets.length,
      hasWagmiClient: !!wagmiClient,
    };
    setDiag(base);

    async function init() {
      if (!isConnected || !address) {
        setWalletClient(null);
        return;
      }
      if (chainId !== ACTIVE_CHAIN.id) {
        setWalletClient(null);
        setDiag((d) => ({ ...d, error: `Wrong chain: ${chainId} (expected ${ACTIVE_CHAIN.id})` }));
        return;
      }

      let walletProvider: EthereumProvider | null = null;
      let providerSource = '';

      if (wallets.length > 0) {
        try {
          const w = wallets[0] as ConnectedWallet;
          walletProvider = await w.getEthereumProvider();
          providerSource = 'privy';
        } catch (e) {
          console.error('[useShielded] privy provider failed:', e);
        }
      }

      if (!walletProvider && typeof window !== 'undefined') {
        const eth = (window as { ethereum?: EthereumProvider }).ethereum;
        if (eth) {
          walletProvider = eth;
          providerSource = 'window';
        }
      }

      if (!walletProvider) {
        if (!cancelled)
          setDiag((d) => ({ ...d, error: 'No wallet provider available' }));
        return;
      }

      const splitProvider = makeSplitProvider(walletProvider);

      try {
        console.log(`[useShielded] creating shielded client via ${providerSource} + split transport on ${ACTIVE_CHAIN.name}`);
        const c = await createShieldedWalletClient({
          chain: ACTIVE_CHAIN,
          transport: custom(splitProvider),
          account: address as Address,
        });
        if (!cancelled) {
          console.log('[useShielded] ✓ shielded client ready');
          setWalletClient(c);
          setDiag((d) => ({
            ...d,
            strategyUsed: `split:${providerSource}`,
            error: undefined,
          }));
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error('[useShielded] shielded client creation failed:', e);
        if (!cancelled) {
          setWalletClient(null);
          setDiag((d) => ({ ...d, error: msg, strategyUsed: providerSource }));
        }
      }
    }

    init();
    return () => {
      cancelled = true;
    };
  }, [address, isConnected, chainId, wallets, wagmiClient]);

  return {
    walletClient,
    account: address ? ({ address: address as Address } as const) : null,
    address: address as Address | undefined,
    ready: !!walletClient,
    chainId,
    diagnostic: diag,
    error: diag.error,
  };
}
___F_USESHIELDED___

echo "→ Updating lib/history.ts to use ACTIVE_CHAIN…"
cat > lib/history.ts << '___F_HISTORY___'
import { createPublicClient, http, type Address, type Hash } from 'viem';
import { seismicPay } from './contract';
import { ACTIVE_CHAIN } from './chain';

export type HistoryEvent = {
  type: 'deposit' | 'send' | 'receive' | 'withdraw';
  txHash: Hash;
  blockNumber: bigint;
  counterparty?: Address;
  timestamp?: number;
};

const publicClient = createPublicClient({
  chain: ACTIVE_CHAIN,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL || ACTIVE_CHAIN.rpcUrls.default.http[0],
  ),
});

export async function fetchHistory(user: Address): Promise<HistoryEvent[]> {
  const events: HistoryEvent[] = [];
  const queries = [
    { name: 'Deposited' as const, args: { user }, type: 'deposit' as const },
    { name: 'Transferred' as const, args: { from: user }, type: 'send' as const },
    { name: 'Transferred' as const, args: { to: user }, type: 'receive' as const },
    { name: 'Withdrawn' as const, args: { user }, type: 'withdraw' as const },
  ];

  for (const q of queries) {
    try {
      const evts = await publicClient.getContractEvents({
        address: seismicPay.address,
        abi: seismicPay.abi,
        eventName: q.name,
        args: q.args,
        fromBlock: 0n,
      });
      for (const e of evts) {
        const args = e.args as { from?: Address; to?: Address };
        events.push({
          type: q.type,
          txHash: e.transactionHash!,
          blockNumber: e.blockNumber!,
          counterparty:
            q.type === 'send' ? args.to : q.type === 'receive' ? args.from : undefined,
        });
      }
    } catch {
      /* ignore */
    }
  }

  events.sort((a, b) => Number(b.blockNumber - a.blockNumber));

  const top = events.slice(0, 60);
  await Promise.all(
    top.map(async (ev) => {
      try {
        const block = await publicClient.getBlock({ blockNumber: ev.blockNumber });
        ev.timestamp = Number(block.timestamp) * 1000;
      } catch {
        /* ignore */
      }
    }),
  );

  return events;
}

export async function waitForTx(hash: Hash) {
  return publicClient.waitForTransactionReceipt({ hash });
}
___F_HISTORY___

echo "→ Updating components/NetworkGate.tsx to use ACTIVE_CHAIN…"
cat > components/NetworkGate.tsx << '___F_NETGATE___'
'use client';

import { motion } from 'framer-motion';
import { useChainId, useSwitchChain } from 'wagmi';
import { AlertTriangle } from 'lucide-react';
import { ACTIVE_CHAIN } from '@/lib/chain';

export function NetworkGate({ children }: { children: React.ReactNode }) {
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  if (chainId === ACTIVE_CHAIN.id) return <>{children}</>;

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-amber-950/30 border border-amber-900/50 rounded-2xl p-6 mb-6"
    >
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
        <div className="flex-1">
          <div className="text-sm font-medium text-amber-200 mb-1">
            Wrong network
          </div>
          <div className="text-xs text-amber-300/70 mb-4">
            Your wallet is on chain {chainId || 'unknown'}. AI Pay Seismic is
            configured for <strong>{ACTIVE_CHAIN.name}</strong> (chain {ACTIVE_CHAIN.id}).
          </div>
          <button
            onClick={() => switchChain({ chainId: ACTIVE_CHAIN.id })}
            disabled={isPending}
            className="px-4 py-2 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 rounded-lg text-sm font-medium text-amber-50 transition-colors"
          >
            {isPending ? 'Switching…' : `Switch to ${ACTIVE_CHAIN.name}`}
          </button>
        </div>
      </div>
    </motion.div>
  );
}
___F_NETGATE___

echo "→ Updating components/Sidebar.tsx network indicator…"
# Just patch the chain reference, not rewrite the whole file
python3 - << 'PYEOF'
import re
with open('components/Sidebar.tsx', 'r') as f:
    content = f.read()

# Replace sanvil import with ACTIVE_CHAIN
content = content.replace(
    "import { sanvil } from 'seismic-viem';",
    "import { ACTIVE_CHAIN } from '@/lib/chain';"
)
# Replace sanvil.id references
content = content.replace("sanvil.id", "ACTIVE_CHAIN.id")
# Update the label
content = content.replace(
    "'Seismic Local'",
    "ACTIVE_CHAIN.name"
)

with open('components/Sidebar.tsx', 'w') as f:
    f.write(content)
print("Sidebar updated")
PYEOF

echo "→ Updating app/providers.tsx…"
cat > app/providers.tsx << '___F_PROVIDERS___'
'use client';

import { PrivyProvider } from '@privy-io/react-auth';
import { WagmiProvider } from '@privy-io/wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { wagmiConfig } from '@/lib/wagmi';
import { ACTIVE_CHAIN } from '@/lib/chain';
import { ToastProvider } from '@/components/Toast';
import { useState } from 'react';

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID || ''}
      config={{
        loginMethods: ['email', 'wallet'],
        appearance: { theme: 'dark', accentColor: '#7c3aed' },
        embeddedWallets: { createOnLogin: 'users-without-wallets' },
        defaultChain: ACTIVE_CHAIN,
        supportedChains: [ACTIVE_CHAIN],
      }}
    >
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>
          <ToastProvider>{children}</ToastProvider>
        </WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
___F_PROVIDERS___

echo ""
echo "✓ Code updates done."
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  NEXT — manual steps for Seismic Testnet (do these in order)"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "1. Switch MetaMask to Seismic Testnet"
echo "   Open MetaMask → network dropdown at top → if 'Seismic Testnet'"
echo "   isn't there, add manually:"
echo "     Name:      Seismic Testnet"
echo "     RPC URL:   https://node-2.seismicdev.net/rpc"
echo "     Chain ID:  5124"
echo "     Symbol:    ETH"
echo "     Explorer:  https://explorer-2.seismicdev.net"
echo ""
echo "2. Get testnet ETH from the faucet"
echo "   Open https://faucet-2.seismicdev.net/"
echo "   Paste your MetaMask wallet address (0x581F…70E3)"
echo "   Claim. Takes 10-30 seconds."
echo ""
echo "3. Get a deploy private key"
echo "   For testnet only, export your MetaMask private key:"
echo "     MetaMask → 3 dots → Account details → Show private key"
echo "     → enter password → copy"
echo "   (Never paste this anywhere except the deploy command below."
echo "    Don't commit it. Don't share it.)"
echo ""
echo "4. Deploy the contract to Seismic Testnet"
echo "   cd ~/code/ai-pay-seismic/contracts"
echo "   sforge script script/Deploy.s.sol:DeploySeismicPay \\"
echo "     --rpc-url https://node-2.seismicdev.net/rpc \\"
echo "     --broadcast \\"
echo "     --private-key 0xYOUR_EXPORTED_KEY"
echo ""
echo "   Copy the 'Contract Address:' line from the output."
echo ""
echo "5. Update apps/web/.env.local with the testnet config:"
echo "     NEXT_PUBLIC_SEISMIC_PAY_ADDRESS=0x<address from step 4>"
echo "     NEXT_PUBLIC_CHAIN_ID=5124"
echo "     NEXT_PUBLIC_RPC_URL=https://node-2.seismicdev.net/rpc"
echo "     NEXT_PUBLIC_PRIVY_APP_ID=<keep your existing>"
echo "     GEMINI_API_KEY=<keep your existing>"
echo ""
echo "6. Restart dev server (Ctrl+C, npm run dev) and hard-refresh browser."
echo ""
echo "Now: MetaMask on Seismic Testnet → no Blockaid 'malicious' warning,"
echo "no fake mainnet pricing, contract deployed to a real persistent chain,"
echo "block explorer links work, faucet ETH covers all txs."
