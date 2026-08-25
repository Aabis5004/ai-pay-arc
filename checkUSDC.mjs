import { createPublicClient, http, erc20Abi } from 'viem';

const client = createPublicClient({ chain: { id: 5042002 }, transport: http('https://rpc.testnet.arc.network') });

async function run() {
  try {
    const bal = await client.readContract({
      address: '0x3600000000000000000000000000000000000000',
      abi: erc20Abi,
      functionName: 'balanceOf',
      args: ['0x3715c568fBF492Da3B7899aD037BB773432f1C69']
    });
    console.log("USDC bal:", bal);
  } catch(e) {
    console.error("USDC Error:", e.message);
  }
}
run();
