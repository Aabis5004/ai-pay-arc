import { defineChain } from 'viem';

export const arcTestnet = defineChain({
  id: 5042002,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_RPC_URL || 'https://rpc.testnet.arc.network'] },
    public: { http: [process.env.NEXT_PUBLIC_RPC_URL || 'https://rpc.testnet.arc.network'] },
  },
  blockExplorers: {
    default: { name: 'ArcScan', url: 'https://testnet.arcscan.app' },
  },
  testnet: true,
});

// We keep ACTIVE_CHAIN as the default for the app initially
export const ACTIVE_CHAIN = arcTestnet;
export const SUPPORTED_CHAINS = [arcTestnet] as const;
export const IS_TESTNET = true;
export const NATIVE_SYMBOL = ACTIVE_CHAIN.nativeCurrency.symbol;
