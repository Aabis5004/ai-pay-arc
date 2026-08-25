import { createPublicClient, http, erc20Abi } from 'viem';

const arcTestnet = {
  id: 5042002,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://rpc.testnet.arc.network'] },
  },
};

const client = createPublicClient({
  chain: arcTestnet,
  transport: http(),
});

async function run() {
  const user = "0xCb92534f3bA18280f55A8A4cbC2665B48B36B429".toLowerCase();
  const cirBtc = "0xf0C4a4CE82A5746AbAAd9425360Ab04fbBA432BF";
  
  const bal = await client.readContract({
    address: cirBtc,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [user],
  });
  console.log("cirBTC Balance on 0xf0C4...:", bal);
  
  const dec = await client.readContract({
    address: cirBtc,
    abi: erc20Abi,
    functionName: 'decimals',
  });
  console.log("cirBTC decimals:", dec);
}
run();
