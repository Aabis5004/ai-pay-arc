'use client';
import {
  createPublicClient, createWalletClient, custom, http, type Address,
} from 'viem';
import { arcTestnet } from './chain';
import { cardRegistryAbi } from '@/abi/CardRegistry';

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';
const REGISTRY = process.env.NEXT_PUBLIC_CARD_REGISTRY as Address | undefined;

type Provider = { request: (a: { method: string; params?: unknown }) => Promise<unknown> };

function pub() {
  return createPublicClient({ chain: arcTestnet, transport: http(RPC_URL) });
}

export function cardToBigInt(card: string): bigint {
  const digits = card.replace(/\D/g, '');
  if (!digits) return 0n;
  return BigInt(digits);
}

export function isRegistryConfigured(): boolean {
  return !!REGISTRY;
}

export async function resolveCard(card: string): Promise<Address | null> {
  if (!REGISTRY) throw new Error('Card registry not configured.');
  const num = cardToBigInt(card);
  if (num === 0n) return null;
  const addr = (await pub().readContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'addressOf', args: [num],
  })) as Address;
  if (!addr || addr === '0x0000000000000000000000000000000000000000') return null;
  return addr;
}

export async function cardOf(addr: Address): Promise<bigint> {
  if (!REGISTRY) return 0n;
  return (await pub().readContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'cardOf', args: [addr],
  })) as bigint;
}

export async function registerCard(
  provider: Provider, account: Address, card: string,
): Promise<`0x${string}`> {
  if (!REGISTRY) throw new Error('Card registry not configured.');
  const num = cardToBigInt(card);
  if (num === 0n) throw new Error('Invalid card number.');
  const wc = createWalletClient({
    account, chain: arcTestnet, transport: custom(provider as Parameters<typeof custom>[0]),
  });
  const hash = await wc.writeContract({
    address: REGISTRY, abi: cardRegistryAbi, functionName: 'register', args: [num], chain: arcTestnet,
  });
  await pub().waitForTransactionReceipt({ hash, timeout: 30_000 });
  return hash;
}
