import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
const pk = generatePrivateKey();
const account = privateKeyToAccount(pk);
console.log('New Wallet Address:', account.address);
console.log('New Private Key:', pk);
