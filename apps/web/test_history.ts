import { createPublicClient, http, getAddress } from 'viem';
import { arcTestnet } from './lib/chain';
import arcPayAbi from './lib/arcPayAbi.json';

const client = createPublicClient({
  chain: arcTestnet,
  transport: http(arcTestnet.rpcUrls.default.http[0]),
});

async function main() {
  const user = getAddress('0x581F8afBa88a7aa93c662c738559b634798A70E3');
  const contract = '0xb7192af98d138a4970cf71bda43b27357339ea1f';
  console.log('Fetching logs for', user);
  try {
    const latest = await client.getBlockNumber();
    console.log('Latest block:', latest);
    
    const evts = await client.getContractEvents({
      address: contract,
      abi: arcPayAbi,
      eventName: 'Deposited',
      args: { user },
      fromBlock: 0n,
    });
    console.log('Deposited:', evts.length, evts.map(e => e.args));

    const allEvts = await client.getContractEvents({
      address: contract,
      abi: arcPayAbi,
      fromBlock: latest > 1000n ? latest - 1000n : 0n,
    });
    console.log('All recent events on contract:', allEvts.length);
  } catch (e) {
    console.error(e);
  }
}
main();
