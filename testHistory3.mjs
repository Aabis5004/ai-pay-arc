import { parseAbi, decodeEventLog, pad } from 'viem';

const ARC_PAY_ADDRESS = "0x3715c568fBF492Da3B7899aD037BB773432f1C69";
const user = "0xCb92534f3bA18280f55A8A4cbC2665B48B36B429"; 

const historyAbi = parseAbi([
  'event Deposited(address indexed user, address indexed token, uint256 amount)',
  'event Staked(address indexed user, address indexed token, uint256 amount)',
  'event Unstaked(address indexed user, address indexed token, uint256 amount)',
  'event LiquidityAdded(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB)',
  'event LiquidityRemoved(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB)',
  'event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)'
]);

async function run() {
  const topic1 = pad(user, { size: 32 }).toLowerCase();
  const url = `https://testnet.arcscan.app/api?module=logs&action=getLogs&fromBlock=58513500&toBlock=latest&address=${ARC_PAY_ADDRESS}&topic1=${topic1}`;
  
  console.log("Fetching", url);
  const res = await fetch(url);
  const data = await res.json();
  
  if (data.status === '1' && data.result) {
    const logs = data.result;
    console.log(`Found ${logs.length} logs for user`);
    for (const log of logs) {
      try {
        const decoded = decodeEventLog({
          abi: historyAbi,
          data: log.data,
          topics: log.topics,
        });
        console.log(decoded.eventName, decoded.args);
      } catch(e) {
        // Unknown event
      }
    }
  } else {
    console.log("Error or no logs:", data);
  }
}

run().catch(console.error);
