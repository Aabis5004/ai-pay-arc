import { createPublicClient, http, type Address, type Hash, type PublicClient, getAddress } from 'viem';
import { arcPay } from './contract';
import { arcTestnet } from './chain';

export type HistoryEvent = {
  type: 'deposit' | 'send' | 'receive' | 'withdraw';
  txHash: Hash;
  blockNumber: bigint;
  counterparty?: Address;
  token?: Address;
  amount?: bigint;
  timestamp?: number;
};

function getClient(): PublicClient {
  return createPublicClient({
    chain: arcTestnet,
    transport: http(arcTestnet.rpcUrls.default.http[0]),
  });
}

const blockCache = new Map<bigint, number>();

export async function fetchHistory(rawUser: Address): Promise<HistoryEvent[]> {
  const client = getClient();
  const contract = arcPay;
  
  let user: Address;
  try {
    user = getAddress(rawUser);
  } catch (e) {
    return [];
  }

  let fromBlock = 0n;
  try {
    const latest = await client.getBlockNumber();
    fromBlock = latest > 99000n ? latest - 99000n : 0n;
  } catch (e) {
    console.warn('Failed to get block number', e);
  }

  const queries = [
    { name: 'Deposited' as const, args: { user }, type: 'deposit' as const },
    { name: 'Transferred' as const, args: { from: user }, type: 'send' as const },
    { name: 'Transferred' as const, args: { to: user }, type: 'receive' as const },
    { name: 'Withdrawn' as const, args: { user }, type: 'withdraw' as const },
  ];

  const results = await Promise.all(
    queries.map(async (q) => {
      try {
        const evts = await client.getContractEvents({
          address: contract.address as Address,
          abi: contract.abi,
          eventName: q.name,
          args: q.args as any,
          fromBlock,
        });
        return evts.map((e) => {
          const args = (e as any).args;
          return {
            type: q.type,
            txHash: e.transactionHash!,
            blockNumber: e.blockNumber!,
            token: args.token,
            amount: args.amount,
            counterparty: q.type === 'send' ? args.to : q.type === 'receive' ? args.from : undefined,
          } as HistoryEvent;
        });
      } catch (e) {
        console.warn(`[history] error for ${q.type}`, e);
        return [];
      }
    }),
  );

  const events = results.flat();
  events.sort((a, b) => Number(b.blockNumber - a.blockNumber));

  const top = events.slice(0, 60);
  const uniqueBlocks = Array.from(new Set(top.map((e) => e.blockNumber)));
  
  await Promise.all(
    uniqueBlocks.map(async (num) => {
      if (!blockCache.has(num)) {
        try {
          const block = await client.getBlock({ blockNumber: num });
          blockCache.set(num, Number(block.timestamp) * 1000);
        } catch { /* ignore */ }
      }
    })
  );

  for (const ev of top) {
    ev.timestamp = blockCache.get(ev.blockNumber);
  }

  return top;
}

export async function waitForTx(hash: Hash) {
  const client = getClient();
  return client.waitForTransactionReceipt({ hash });
}
