import { parseEther, formatEther, type Address, zeroAddress } from 'viem';
import { arcPay } from './contract';
import { calculateBalances } from './balance';
import { fetchHistory } from './history';
import { ACTIVE_CHAIN } from './chain';

export type ToolCall = { name: string; args: Record<string, unknown> };
export type ToolResult =
  | { ok: true; data: string; hash?: string }
  | { ok: false; error: string };

/* eslint-disable @typescript-eslint/no-explicit-any */
type WalletClient = any;
type Account = any;
/* eslint-enable @typescript-eslint/no-explicit-any */

export async function executeTool(
  tc: ToolCall,
  walletClient: WalletClient,
  account: Account,
): Promise<ToolResult> {
  if (!walletClient || !account) {
    return { ok: false, error: 'Wallet not connected.' };
  }

  try {
    switch (tc.name) {
      case 'get_balance': {
        const { usdc, walletUsdc } = await calculateBalances(account.address as Address);
        return { ok: true, data: `USDC (Vault): ${formatEther(usdc)}, USDC (Wallet): ${formatEther(walletUsdc)}` };
      }
      case 'deposit': {
        const amount = parseEther(String(tc.args.amount));
        const hash = await walletClient.writeContract({
          address: arcPay.address as Address,
          abi: arcPay.abi,
          functionName: 'deposit',
          value: amount,
          account: account.address as Address,
          chain: ACTIVE_CHAIN,
        });
        return { ok: true, data: `Deposited ${tc.args.amount} USDC (Native)`, hash: hash as string };
      }
      case 'send_payment': {
        const amount = parseEther(String(tc.args.amount));
        const to = String(tc.args.to) as Address;
        const hash = await walletClient.writeContract({
          address: arcPay.address as Address,
          abi: arcPay.abi,
          functionName: 'transfer',
          args: [to, zeroAddress, amount],
          account: account.address as Address,
          chain: ACTIVE_CHAIN,
        });
        const short = `${to.slice(0, 6)}…${to.slice(-4)}`;
        return { ok: true, data: `Sent ${tc.args.amount} USDC to ${short}`, hash: hash as string };
      }
      case 'get_history': {
        const events = await fetchHistory(account.address as Address);
        const sends = events.filter((e) => e.type === 'send').length;
        const receives = events.filter((e) => e.type === 'receive').length;
        const deposits = events.filter((e) => e.type === 'deposit').length;
        return {
          ok: true,
          data: `${events.length} total events: ${deposits} deposits, ${sends} sent, ${receives} received.`,
        };
      }
      case 'get_portfolio': {
        const { usdc, walletUsdc } = await calculateBalances(account.address as Address);
        const events = await fetchHistory(account.address as Address);
        return {
          ok: true,
          data: `USDC (Vault): ${formatEther(usdc)}, USDC (Wallet): ${formatEther(walletUsdc)} · ${events.length} on-chain events.`,
        };
      }
      default:
        return { ok: false, error: `Unknown tool: ${tc.name}` };
    }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'unknown error';
    return { ok: false, error: msg.slice(0, 240) };
  }
}
