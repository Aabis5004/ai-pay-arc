import { http } from 'wagmi';
import { createConfig } from '@privy-io/wagmi';
import { arcTestnet } from './chain';

export const wagmiConfig = createConfig({
  chains: [arcTestnet],
  transports: {
    [arcTestnet.id]: http(),
  },
});
