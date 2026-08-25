import { createPublicClient, http, getAddress, parseAbi } from 'viem';

const ARC_PAY_ADDRESS = "0x3715c568fBF492Da3B7899aD037BB773432f1C69";
const user = getAddress("0xCb92534f3bA18280f55A8A4cbC2665B48B36B429"); // From the user's screenshot

const arcTestnet = {
  id: 5042002,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://rpc.testnet.arc.network'] },
    public: { http: ['https://rpc.testnet.arc.network'] },
  },
};

const historyAbi = parseAbi([
  'event Deposited(address indexed user, address indexed token, uint256 amount)',
  'event Staked(address indexed user, address indexed token, uint256 amount)',
  'event Unstaked(address indexed user, address indexed token, uint256 amount)',
  'event LiquidityAdded(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB)',
  'event LiquidityRemoved(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB)',
  'event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)'
]);

async function run() {
  const client = createPublicClient({
    chain: arcTestnet,
    transport: http(arcTestnet.rpcUrls.default.http[0]),
  });

  const currentBlock = await client.getBlockNumber();
  let fromBlock = 58513500n;
  if (currentBlock - fromBlock > 9000n) {
    fromBlock = currentBlock - 9000n;
  }
  
  console.log("Fetching from block", fromBlock, "to", currentBlock);

  const queries = [
    { name: 'Deposited', type: 'deposit' },
    { name: 'Staked', type: 'stake' },
  ];

  for (const q of queries) {
    try {
      const evts = await client.getContractEvents({
        address: ARC_PAY_ADDRESS,
        abi: historyAbi,
        eventName: q.name,
        args: { user } ,
        fromBlock,
      });
      console.log(`Found ${evts.length} ${q.name} events`);
      if (evts.length > 0) {
        console.log(evts[0]);
      }
    } catch (e) {
      console.error(`Error fetching ${q.name}:`, e.message);
    }
  }
}

run().catch(console.error);
