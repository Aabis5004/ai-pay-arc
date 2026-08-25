import { createPublicClient, http } from 'viem';
import { arcTestnet } from './lib/chain';

const client = createPublicClient({
  chain: arcTestnet,
  transport: http('https://rpc.testnet.arc.network')
});

async function run() {
  const routerAddr = '0x54599C3e0bcb99ca37b286242b5eC5D331AB9D18';
  try {
    const code = await client.getBytecode({ address: routerAddr });
    if (code && code !== '0x') {
      console.log('Router exists! Code length:', code.length);
    } else {
      console.log('No code at router address.');
    }
  } catch (e) {
    console.log('Error:', e);
  }
}
run();
