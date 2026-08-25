import { createPublicClient, http, formatEther } from 'viem';
import { arcTestnet } from './lib/chain';

const client = createPublicClient({ chain: arcTestnet, transport: http('https://rpc.testnet.arc.network') });

async function run() {
  const balance = await client.getBalance({ address: '0xb6451Edd0a1ce1256F2D32dA2Bf8c1E68bf04126' });
  console.log('Balance:', formatEther(balance), 'ARC');
}
run().catch(console.error);
