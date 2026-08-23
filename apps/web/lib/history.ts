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

export async function fetchHistory(rawUser: Address): Promise<HistoryEvent[]> {
  const events: HistoryEvent[] = [];
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
    // Fetch last 99k blocks to stay under RPC 100k limit
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

  for (const q of queries) {
    try {
      const evts = await client.getContractEvents({
        address: contract.address as Address,
        abi: contract.abi,
        eventName: q.name,
        args: q.args,
        fromBlock,
      });
      for (const e of evts) {
        const args = e.args as any;
        events.push({
          type: q.type,
          txHash: e.transactionHash!,
          blockNumber: e.blockNumber!,
          token: args.token,
          amount: args.amount,
          counterparty:
            q.type === 'send' ? args.to : q.type === 'receive' ? args.from : undefined,
        });
      }
    } catch (e) {
      console.warn('[history]', e);
    }
  }

  events.sort((a, b) => Number(b.blockNumber - a.blockNumber));

  const top = events.slice(0, 60);
  await Promise.all(
    top.map(async (ev) => {
      try {
        const block = await client.getBlock({ blockNumber: ev.blockNumber });
        ev.timestamp = Number(block.timestamp) * 1000;
      } catch {
        /* ignore */
      }
    }),
  );

  return events;
}

export async function waitForTx(hash: Hash) {
  const client = getClient();
  return client.waitForTransactionReceipt({ hash });
}
