import { createWalletClient, createPublicClient, http, custom, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { arcTestnet } from './lib/chain';
import { erc20Abi } from 'viem';

const PK = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const account = privateKeyToAccount(PK);

const client = createPublicClient({
  chain: arcTestnet,
  transport: http('https://rpc.testnet.arc.network')
});

const wallet = createWalletClient({
  account,
  chain: arcTestnet,
  transport: http('https://rpc.testnet.arc.network')
});

const routerAddr = '0x54599C3e0bcb99ca37b286242b5eC5D331AB9D18';
const testEthAddr = '0xe7f1725e7734ce288f8367e1bb143e90bb3f0512';

const routerAbi = [
  {
    "inputs": [
      { "internalType": "address", "name": "token", "type": "address" },
      { "internalType": "uint256", "name": "amountTokenDesired", "type": "uint256" },
      { "internalType": "uint256", "name": "amountTokenMin", "type": "uint256" },
      { "internalType": "uint256", "name": "amountETHMin", "type": "uint256" },
      { "internalType": "address", "name": "to", "type": "address" },
      { "internalType": "uint256", "name": "deadline", "type": "uint256" }
    ],
    "name": "addLiquidityETH",
    "outputs": [
      { "internalType": "uint256", "name": "amountToken", "type": "uint256" },
      { "internalType": "uint256", "name": "amountETH", "type": "uint256" },
      { "internalType": "uint256", "name": "liquidity", "type": "uint256" }
    ],
    "stateMutability": "payable",
    "type": "function"
  }
];

async function run() {
  console.log('Using account:', account.address);
  
  // 1. Check balances
  const arcBalance = await client.getBalance({ address: account.address });
  const usdcBalance = await client.readContract({
    address: testEthAddr,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [account.address]
  });
  console.log(`ARC Balance: ${arcBalance}`);
  console.log(`USDC Balance: ${usdcBalance}`);

  // 2. Approve Router to spend USDC
  const amountUSDC = parseEther('10000'); // 10,000 USDC
  const amountARC = parseEther('100');   // 100 ARC

  console.log('Approving Router...');
  const tx1 = await wallet.writeContract({
    address: testEthAddr,
    abi: erc20Abi,
    functionName: 'approve',
    args: [routerAddr, amountUSDC]
  });
  console.log('Approve Tx:', tx1);
  await client.waitForTransactionReceipt({ hash: tx1 });

  // 3. Add Liquidity
  console.log('Adding Liquidity...');
  const tx2 = await wallet.writeContract({
    address: routerAddr,
    abi: routerAbi,
    functionName: 'addLiquidityETH',
    args: [
      testEthAddr,
      amountUSDC,
      0n,
      0n,
      account.address,
      BigInt(Math.floor(Date.now() / 1000) + 60 * 10)
    ],
    value: amountARC
  });
  console.log('Add Liquidity Tx:', tx2);
  const receipt = await client.waitForTransactionReceipt({ hash: tx2 });
  console.log('Success! Block:', receipt.blockNumber);
}
run().catch(console.error);
