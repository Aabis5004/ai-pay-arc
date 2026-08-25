import { createWalletClient, createPublicClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { arcTestnet } from './lib/chain';
import * as fs from 'fs';

const PK = '0x92340f03bab2f8d4475f293ad5792aa82a969c930e5b0a567070419d24bf5b6a';
const account = privateKeyToAccount(PK);
const client = createPublicClient({ chain: arcTestnet, transport: http('https://rpc.testnet.arc.network') });
const wallet = createWalletClient({ account, chain: arcTestnet, transport: http('https://rpc.testnet.arc.network') });

const json = JSON.parse(fs.readFileSync('../../contracts/out/MockERC20.sol/MockERC20.json', 'utf8'));

async function run() {
  const hash = await wallet.deployContract({
    abi: json.abi,
    bytecode: json.bytecode.object,
  });
  console.log('Tx:', hash);
  const receipt = await client.waitForTransactionReceipt({ hash });
  console.log('Deployed Token to:', receipt.contractAddress);
}
run().catch(console.error);
