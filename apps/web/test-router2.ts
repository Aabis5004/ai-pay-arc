import { createPublicClient, http } from 'viem';
import { arcTestnet } from './lib/chain';

const client = createPublicClient({
  chain: arcTestnet,
  transport: http('https://rpc.testnet.arc.network')
});

const routerAbi = [
  { inputs: [], name: 'WETH', outputs: [{ internalType: 'address', name: '', type: 'address' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'factory', outputs: [{ internalType: 'address', name: '', type: 'address' }], stateMutability: 'view', type: 'function' }
];

async function run() {
  const routerAddr = '0x54599C3e0bcb99ca37b286242b5eC5D331AB9D18';
  try {
    const weth = await client.readContract({ address: routerAddr, abi: routerAbi, functionName: 'WETH' });
    const factory = await client.readContract({ address: routerAddr, abi: routerAbi, functionName: 'factory' });
    console.log('WETH:', weth);
    console.log('Factory:', factory);
  } catch (e) {
    console.log('Error:', e);
  }
}
run();
