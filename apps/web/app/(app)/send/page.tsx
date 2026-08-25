'use client';
import { useEffect, useState } from 'react';
import {
  parseEther,
  createWalletClient,
  createPublicClient,
  custom,
  http,
  isAddress,
  type Address,
  zeroAddress,
} from 'viem';
import { useWallets } from '@privy-io/react-auth';
import { motion } from 'framer-motion';
import { Send as SendIcon, Loader2, CheckCircle2, XCircle, ArrowRight, Copy } from 'lucide-react';
import { arcPay, testEth } from '@/lib/contract';
import { arcTestnet } from '@/lib/chain';
import { useWalletAddress } from '@/lib/useWalletAddress';
import { calculateBalances } from '@/lib/balance';
import { formatEther, formatUnits, parseUnits } from 'viem';
import { PageHeader } from '@/components/PageHeader';
import { resolveCard } from '@/lib/cardRegistry';
import { useReadContract } from 'wagmi';
import { parseAbi } from 'viem';
import { MOCK_TOKENS } from '@/lib/tokens';
type SendState =
  | { kind: 'idle' }
  | { kind: 'preparing' }
  | { kind: 'switching_network' }
  | { kind: 'signing'; summary: string }
  | { kind: 'confirming'; summary: string; hash: `0x${string}` }
  | { kind: 'done'; summary: string; hash: `0x${string}` }
  | { kind: 'error'; message: string; details?: string };

export default function SendPage() {
  const address = useWalletAddress();
  const { wallets } = useWallets();
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [tokenType, setTokenType] = useState<'USDC' | 'ETH'>('USDC');
  const [state, setState] = useState<SendState>({ kind: 'idle' });
  const { data: vaultBalanceWei } = useReadContract({
    address: arcPay.address as Address,
    abi: parseAbi(['function vaultBalance(address user, address token) external view returns (uint256)']),
    functionName: 'vaultBalance',
    args: address ? [address as `0x${string}`, MOCK_TOKENS[0].address as `0x${string}`] : undefined,
    query: { enabled: !!address },
  });

  const vaultBalance = vaultBalanceWei ? formatUnits(vaultBalanceWei, 6) : '0';

  const activeChain = arcTestnet;
  const tokenSymbol = tokenType;

  const getProvider = async (): Promise<unknown> => {
    if (wallets && wallets.length > 0) {
      try {
        const p = await wallets[0].getEthereumProvider();
        if (p) return p;
      } catch (e) {
        console.warn('[send] privy provider unavailable:', e);
      }
    }
    if (typeof window !== 'undefined' && (window as { ethereum?: unknown }).ethereum) {
      return (window as { ethereum?: unknown }).ethereum;
    }
    return null;
  };

  const send = async () => {
    setState({ kind: 'preparing' });

    if (!address) {
      setState({ kind: 'error', message: 'Wallet not connected.', details: 'Sign in via Privy first.' });
      return;
    }
    
    let finalTo = to;
    if (!isAddress(to)) {
      const digits = to.replace(/\D/g, '');
      if (digits.length >= 16) {
        try {
          const resolved = await resolveCard(to);
          if (resolved && resolved !== zeroAddress) {
            finalTo = resolved;
          } else {
            setState({ kind: 'error', message: 'Card not registered.', details: 'This card number is not registered.' });
            return;
          }
        } catch (e) {
          setState({ kind: 'error', message: 'Could not resolve card.', details: e instanceof Error ? e.message : String(e) });
          return;
        }
      } else {
        setState({ kind: 'error', message: 'Recipient invalid.', details: 'Must be 0x address or 16-digit card.' });
        return;
      }
    }
    
    let amountWei: bigint;
    try {
      amountWei = tokenType === 'USDC' ? parseUnits(amount, 6) : parseEther(amount);
    } catch {
      setState({ kind: 'error', message: 'Amount is invalid.' });
      return;
    }
    if (amountWei <= BigInt(0)) {
      setState({ kind: 'error', message: 'Amount must be greater than zero.' });
      return;
    }

    const provider = (await getProvider()) as any;
    if (!provider) {
      setState({ kind: 'error', message: 'No wallet provider found.' });
      return;
    }

    const publicClient = createPublicClient({ chain: activeChain, transport: http(activeChain.rpcUrls.default.http[0]) });

    let currentChainHex: string;
    try {
      currentChainHex = (await provider.request({ method: 'eth_chainId' })) as string;
    } catch (e) {
      setState({ kind: 'error', message: 'Wallet failed to report network.' });
      return;
    }

    const targetChainHex = '0x' + activeChain.id.toString(16);
    if (currentChainHex.toLowerCase() !== targetChainHex.toLowerCase()) {
      setState({ kind: 'switching_network' });
      try {
        await provider.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: targetChainHex }],
        });
      } catch (e: unknown) {
        if ((e as { code?: number }).code === 4902) {
          try {
            await provider.request({
              method: 'wallet_addEthereumChain',
              params: [{
                chainId: targetChainHex, 
                chainName: activeChain.name,
                rpcUrls: activeChain.rpcUrls.default.http, 
                nativeCurrency: activeChain.nativeCurrency,
              }],
            });
          } catch {
             setState({ kind: 'error', message: 'Could not add network.' });
             return;
          }
        } else {
          setState({ kind: 'error', message: 'Could not switch network.' });
          return;
        }
      }
    }

    const summary = `${amount} ${tokenSymbol} → ${finalTo.slice(0, 6)}…${finalTo.slice(-4)}`;
    setState({ kind: 'signing', summary });

    let walletClient;
    try {
      walletClient = createWalletClient({
        account: address as Address,
        chain: activeChain,
        transport: custom(provider),
      });
    } catch (e) {
      setState({ kind: 'error', message: 'Could not create wallet client.' });
      return;
    }

    let hash: `0x${string}`;
    try {
      const tokenAddress = tokenType === 'USDC' ? (MOCK_TOKENS[0].address as Address) : testEth.address;
      hash = await walletClient.writeContract({
        address: arcPay.address as Address,
        abi: arcPay.abi,
        functionName: 'transfer',
        args: [finalTo as Address, tokenAddress, amountWei],
        chain: activeChain,
      });
    } catch (e: unknown) {
      const err = e as { message?: string; shortMessage?: string };
      const raw = err.shortMessage || err.message || String(e);
      let friendly = raw;
      if (/user rejected|denied/i.test(raw)) friendly = 'You cancelled the signature.';
      else if (/insufficient balance/i.test(raw)) friendly = 'Insufficient balance on contract for this token.';
      setState({ kind: 'error', message: friendly, details: raw });
      return;
    }

    setState({ kind: 'confirming', summary, hash });
    try {
      const receipt = await publicClient.waitForTransactionReceipt({ hash, timeout: 30_000 });
      if (receipt.status === 'reverted') {
        setState({ kind: 'error', message: 'Transaction reverted on-chain.' });
        return;
      }
      setState({ kind: 'done', summary, hash });
    } catch (e) {
      setState({ kind: 'error', message: 'Timed out waiting for confirmation.' });
    }
  };

  const reset = () => {
    setState({ kind: 'idle' });
    setTo('');
    setAmount('');
  };

  const copyHash = (hash: string) => {
    navigator.clipboard.writeText(hash);
  };

  useEffect(() => {
    if (state.kind === 'done') {
      const id = setTimeout(reset, 8000);
      return () => clearTimeout(id);
    }
  }, [state.kind]);

  const busy =
    state.kind === 'preparing' ||
    state.kind === 'switching_network' ||
    state.kind === 'signing' ||
    state.kind === 'confirming';

  return (
    <div>
      <PageHeader title="Send" subtitle="Transfer balances to another address or card instantly." />

      <motion.div
        initial={{ opacity: 0, scale: 0.98 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.3 }}
        className="mt-8 max-w-md mx-auto"
      >
        <div className="bg-zinc-900 rounded-[24px] p-2 border border-zinc-800 shadow-xl">
          {/* Recipient Block */}
          <div className="bg-zinc-800/40 rounded-[20px] p-5 border border-zinc-700/30 mb-2">
            <div className="flex justify-between text-sm text-zinc-400 mb-3 font-medium">
              <span>Send to</span>
            </div>
            <input
              type="text"
              value={to}
              onChange={(e) => setTo(e.target.value.trim())}
              placeholder="0x... or 4242 4242..."
              disabled={busy}
              className="w-full bg-transparent text-xl font-medium text-white placeholder:text-zinc-600 outline-none"
            />
          </div>

          {/* Amount Block */}
          <div className="bg-zinc-800/40 rounded-[20px] p-5 border border-zinc-700/30">
            <div className="flex justify-between text-sm text-zinc-400 mb-4 font-medium">
              <span>Amount</span>
              <button onClick={() => setAmount(vaultBalance)} className="text-xs px-2 py-0.5 rounded bg-zinc-800 text-zinc-300 hover:bg-zinc-700 hover:text-white transition-colors">MAX</button>
            </div>
            <div className="flex items-center justify-between">
              <input
                type="number"
                step="0.001"
                min="0"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0"
                disabled={busy}
                className="text-4xl font-medium outline-none text-white placeholder:text-zinc-600 w-full bg-transparent"
              />
              <div className="flex items-center gap-2 bg-zinc-700/50 rounded-full px-3 py-2 shrink-0 border border-zinc-600/50 shadow-sm">
                <div className="w-6 h-6 rounded-full bg-sky-500 flex items-center justify-center text-white font-bold text-[11px]">
                  $
                </div>
                <span className="text-white font-medium pr-1 text-sm">USDC</span>
              </div>
            </div>
          </div>

          {/* Action Button */}
          <div className="px-2 pb-2 pt-4">
            <motion.button
              whileHover={{ scale: busy || !to || !amount || !address ? 1 : 1.01 }}
              whileTap={{ scale: busy || !to || !amount || !address ? 1 : 0.99 }}
              onClick={send}
              disabled={busy || !to || !amount || !address}
              className="w-full py-4 bg-sky-500 hover:bg-sky-400 disabled:bg-zinc-800 disabled:text-zinc-500 text-white rounded-2xl font-semibold text-lg transition-colors flex items-center justify-center gap-2"
            >
              {busy ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  Processing...
                </>
              ) : (
                <>
                  <SendIcon className="w-5 h-5" /> Send USDC
                </>
              )}
            </motion.button>
          </div>
        </div>

        {state.kind === 'signing' && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="mt-5 p-4 rounded-xl bg-sky-500/10 border-sky-500/20 border"
          >
            <div className="text-xs tracking-wider uppercase text-sky-300/80 mb-1">Waiting for wallet</div>
            <div className="text-sm text-white/80">{state.summary}</div>
            <div className="text-xs text-white/40 mt-1">Open MetaMask and click Confirm.</div>
          </motion.div>
        )}

        {state.kind === 'confirming' && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="mt-5 p-4 rounded-xl bg-sky-500/10 border-sky-500/20 border"
          >
            <div className="text-xs tracking-wider uppercase text-sky-300/80 mb-1">Confirming</div>
            <div className="text-sm text-white/80">{state.summary}</div>
            <div className="text-xs text-white/40 font-mono mt-2 flex items-center gap-2">
              <span className="truncate">{state.hash}</span>
              <button onClick={() => copyHash(state.hash)} className="hover:text-white/80">
                <Copy className="w-3 h-3" />
              </button>
            </div>
          </motion.div>
        )}

        {state.kind === 'done' && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="mt-5 p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/20"
          >
            <div className="flex items-center gap-2 mb-1">
              <CheckCircle2 className="w-4 h-4 text-emerald-400" />
              <div className="text-xs tracking-wider uppercase text-emerald-300/80">Sent</div>
            </div>
            <div className="text-sm text-white/90">{state.summary}</div>
            <div className="text-xs text-white/40 font-mono mt-2 flex items-center gap-2">
              <span className="truncate">{state.hash}</span>
              <button onClick={() => copyHash(state.hash)} className="hover:text-white/80">
                <Copy className="w-3 h-3" />
              </button>
            </div>
          </motion.div>
        )}

        {state.kind === 'error' && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="mt-5 p-4 rounded-xl bg-red-500/10 border border-red-500/20"
          >
            <div className="flex items-center gap-2 mb-1">
              <XCircle className="w-4 h-4 text-red-400" />
              <div className="text-xs tracking-wider uppercase text-red-300/80">Failed</div>
            </div>
            <div className="text-sm text-white/90">{state.message}</div>
            {state.details && (
              <div className="text-xs text-white/40 mt-2 font-mono break-all">{state.details}</div>
            )}
            <button
              onClick={reset}
              className="mt-3 text-xs text-sky-400 hover:text-sky-300 flex items-center gap-1"
            >
              Try again <ArrowRight className="w-3 h-3" />
            </button>
          </motion.div>
        )}

      </motion.div>
    </div>
  );
}
