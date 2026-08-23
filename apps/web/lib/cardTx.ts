'use client';

import {
  createWalletClient, createPublicClient, custom, http,
  parseEther, isAddress, type Address, zeroAddress, type Chain
} from 'viem';
import { arcPay } from './contract';
import { arcTestnet } from './chain';
import { resolveCard } from './cardRegistry';

type Provider = { request: (a: { method: string; params?: unknown }) => Promise<unknown> };

async function ensureNetwork(provider: Provider, chainId: number) {
  const chainIdHex = '0x' + chainId.toString(16);
  const current = (await provider.request({ method: 'eth_chainId' })) as string;
  if (current.toLowerCase() === chainIdHex.toLowerCase()) return;
  
  const targetChain = arcTestnet;

  try {
    await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: chainIdHex }] });
  } catch (e: unknown) {
    if ((e as { code?: number }).code === 4902) {
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [{
          chainId: chainIdHex, 
          chainName: targetChain.name,
          rpcUrls: targetChain.rpcUrls.default.http, 
          nativeCurrency: targetChain.nativeCurrency,
        }],
      });
    } else throw e;
  }
}

function getPublicClient(chain: Chain) {
  return createPublicClient({ chain, transport: http(chain.rpcUrls.default.http[0]) });
}

async function getWalletClient(provider: Provider, account: Address, chain: Chain) {
  await ensureNetwork(provider, chain.id);
  return createWalletClient({
    account, chain,
    transport: custom(provider as Parameters<typeof custom>[0]),
  });
}

function friendly(raw: string): string {
  if (/user rejected|user denied/i.test(raw)) return 'You cancelled in your wallet.';
  if (/insufficient funds/i.test(raw)) return 'Not enough funds for gas or transaction.';
  if (/arithmetic|overflow|underflow|reverted/i.test(raw)) return 'Insufficient balance or transaction reverted.';
  return raw.slice(0, 140);
}

export async function cardDeposit(
  provider: Provider, account: Address, amount: string
): Promise<`0x${string}`> {
  const chain = arcTestnet;
  const contract = arcPay;
  
  const wc = await getWalletClient(provider, account, chain);
  
  try {
    const hash = await wc.writeContract({
      address: contract.address as Address,
      abi: contract.abi,
      functionName: 'deposit',
      args: [],
      value: parseEther(amount),
      chain,
    });
    await getPublicClient(chain).waitForTransactionReceipt({ hash, timeout: 30_000 });
    return hash;
  } catch (e) {
    throw new Error(friendly(e instanceof Error ? (e as { shortMessage?: string }).shortMessage || e.message : String(e)));
  }
}

export async function cardSend(
  provider: Provider, account: Address, to: string, amount: string
): Promise<`0x${string}`> {
  if (!isAddress(to)) throw new Error('Recipient must be a valid 0x wallet address.');
  const chain = arcTestnet;
  const contract = arcPay;
  
  const wc = await getWalletClient(provider, account, chain);
  try {
    const hash = await wc.writeContract({
      address: contract.address as Address,
      abi: contract.abi,
      functionName: 'transfer',
      args: [to as Address, zeroAddress, parseEther(amount)],
      chain,
    });
    const receipt = await getPublicClient(chain).waitForTransactionReceipt({ hash, timeout: 30_000 });
    if (receipt.status === 'reverted') throw new Error('Transaction reverted.');
    return hash;
  } catch (e) {
    throw new Error(friendly(e instanceof Error ? (e as { shortMessage?: string }).shortMessage || e.message : String(e)));
  }
}

export async function cardSendByNumber(
  provider: Provider, account: Address, cardNumber: string, amount: string
): Promise<`0x${string}`> {
  const to = await resolveCard(cardNumber);
  if (!to) throw new Error('That card number is not registered on-chain.');
  return cardSend(provider, account, to, amount);
}
