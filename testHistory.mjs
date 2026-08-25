import { createPublicClient, http, getAddress, parseAbi } from 'viem';

const ARC_PAY_ADDRESS = "0x3715c568fBF492Da3B7899aD037BB773432f1C69";
const user = getAddress("0xCb92534f3bA18280f55A8A4cbC2665B48B36B429"); // From the user's screenshot
const fromBlock = 58513500n;

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

  const evts = await client.getContractEvents({
    address: ARC_PAY_ADDRESS,
    abi: historyAbi,
    eventName: 'Staked',
    args: { user },
    fromBlock,
  });

  console.log("Found Staked events:", evts.length);
  console.log(evts);
}

run().catch(console.error);
