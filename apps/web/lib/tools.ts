import { parseEther, formatEther, type Address, zeroAddress, parseUnits, parseAbi, formatUnits } from 'viem';
import { arcPay } from './contract';
import { calculateBalances } from './balance';
import { fetchHistory } from './history';
import { ACTIVE_CHAIN } from './chain';
import { MOCK_TOKENS } from './tokens';

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
        return { ok: true, data: `USDC (Vault): ${formatUnits(usdc, 6)}, USDC (Wallet): ${formatUnits(walletUsdc, 6)}` };
      }
      case 'withdraw': {
        const amount = parseUnits(String(tc.args.amount), 6);
        const usdcAddress = MOCK_TOKENS[0].address as Address;
        const hash = await walletClient.writeContract({
          address: arcPay.address as Address,
          abi: parseAbi(['function withdraw(address token, uint256 amount) external']),
          functionName: 'withdraw',
          args: [usdcAddress, amount],
          account: account.address as Address,
          chain: ACTIVE_CHAIN,
        });
        return { ok: true, data: `Withdrew ${tc.args.amount} USDC`, hash: hash as string };
      }
      case 'deposit': {
        const amount = parseUnits(String(tc.args.amount), 6);
        const usdcAddress = MOCK_TOKENS[0].address as Address;
        const hash = await walletClient.writeContract({
          address: arcPay.address as Address,
          abi: parseAbi(['function deposit(address token, uint256 amount) external']),
          functionName: 'deposit',
          args: [usdcAddress, amount],
          account: account.address as Address,
          chain: ACTIVE_CHAIN,
        });
        return { ok: true, data: `Deposited ${tc.args.amount} USDC`, hash: hash as string };
      }
      case 'send_payment': {
        const amount = parseUnits(String(tc.args.amount), 6);
        const to = String(tc.args.to) as Address;
        const usdcAddress = MOCK_TOKENS[0].address as Address;
        const hash = await walletClient.writeContract({
          address: arcPay.address as Address,
          abi: parseAbi(['function transfer(address to, address token, uint256 amount) external']),
          functionName: 'transfer',
          args: [to, usdcAddress, amount],
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
          data: `USDC (Vault): ${formatUnits(usdc, 6)}, USDC (Wallet): ${formatUnits(walletUsdc, 6)} · ${events.length} on-chain events.`,
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
