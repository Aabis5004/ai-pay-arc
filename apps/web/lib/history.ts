import { createPublicClient, http, type Address, type Hash, type PublicClient, getAddress, parseAbi, decodeEventLog, pad } from 'viem';
import { ARC_PAY_ADDRESS } from './contract';
import { arcTestnet } from './chain';
import { MOCK_TOKENS } from './tokens';

export type HistoryEvent = {
  type: 'deposit' | 'send' | 'receive' | 'withdraw' | 'swap' | 'stake' | 'unstake' | 'add_liquidity' | 'remove_liquidity';
  txHash: Hash;
  blockNumber: bigint;
  counterparty?: Address;
  token?: Address;
  tokenB?: Address;
  amount?: bigint;
  amountB?: bigint;
  timestamp?: number;
};

function getClient(): PublicClient {
  return createPublicClient({
    chain: arcTestnet,
    transport: http(arcTestnet.rpcUrls.default.http[0]),
  });
}



const historyAbi = parseAbi([
  'event Deposited(address indexed user, address indexed token, uint256 amount)',
  'event Staked(address indexed user, address indexed token, uint256 amount)',
  'event Unstaked(address indexed user, address indexed token, uint256 amount)',
  'event LiquidityAdded(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB)',
  'event LiquidityRemoved(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB)',
  'event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)',
  'event Transferred(address indexed from, address indexed to, address indexed token, uint256 amount)'
]);

export async function fetchHistory(rawUser: Address): Promise<HistoryEvent[]> {
  let user: Address;
  try {
    user = getAddress(rawUser);
  } catch (e) {
    return [];
  }

  const topic1 = pad(user, { size: 32 }).toLowerCase();
  const url = `https://testnet.arcscan.app/api?module=logs&action=getLogs&fromBlock=58513500&toBlock=latest&address=${ARC_PAY_ADDRESS}&topic1=${topic1}`;
  
  let logs: any[] = [];
  try {
    const res = await fetch(url);
    const data = await res.json();
    if (data.status === '1' && Array.isArray(data.result)) {
      logs = data.result;
    } else if (data.result && Array.isArray(data.result)) {
      logs = data.result;
    }
  } catch(e) {
    console.warn("Failed to fetch logs from explorer", e);
    return [];
  }

  const events: HistoryEvent[] = [];
  
  for (const log of logs) {
    try {
      const decoded = decodeEventLog({
        abi: historyAbi,
        data: log.data,
        topics: log.topics,
      });

      const args = decoded.args as any;
      let token = args.token || args.tokenIn || args.tokenA;
      let tokenB = args.tokenOut || args.tokenB;
      let amount = args.amount || args.amountIn || args.amountA;
      let amountB = args.amountOut || args.amountB;

      let type = '';
      if (decoded.eventName === 'Deposited') type = 'deposit';
      else if (decoded.eventName === 'Staked') type = 'stake';
      else if (decoded.eventName === 'Unstaked') type = 'unstake';
      else if (decoded.eventName === 'Swapped') type = 'swap';
      else if (decoded.eventName === 'LiquidityAdded') type = 'add_liquidity';
      else if (decoded.eventName === 'LiquidityRemoved') type = 'remove_liquidity';
      else if (decoded.eventName === 'Transferred') {
        if (args.from.toLowerCase() === user.toLowerCase()) type = 'send';
        else if (args.to.toLowerCase() === user.toLowerCase()) type = 'receive';
      }

      if (type) {
        events.push({
          type: type as any,
          txHash: log.transactionHash,
          blockNumber: BigInt(log.blockNumber),
          token,
          tokenB,
          amount,
          amountB,
          timestamp: log.timeStamp ? parseInt(log.timeStamp, 16) * 1000 : undefined
        });
      }
    } catch(e) {
      // ignore decoding errors for unknown events
    }
  }

  events.sort((a, b) => Number(b.blockNumber - a.blockNumber));
  return events.slice(0, 60);
}

export async function waitForTx(hash: Hash) {
  const client = getClient();
  return client.waitForTransactionReceipt({ hash });
}
