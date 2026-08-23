'use client';

import { motion } from 'framer-motion';
import { useState, useEffect } from 'react';
import { parseEther, formatEther } from 'viem';
import { arcPay } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { usePrivy } from '@privy-io/react-auth';
import { waitForTx } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import { TxStatusModal, type TxStatus } from '@/components/TxStatusModal';
import { ArrowDownToLine } from 'lucide-react';
import { arcTestnet } from '@/lib/chain';
import { createPublicClient, http, type Address } from 'viem';

const quickAmounts = ['0.1', '0.5', '1', '5'];

export default function DepositPage() {
  const { walletClient, account, ready } = useShielded();
  const { user, linkWallet } = usePrivy();
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState<TxStatus>({ state: 'idle' });
  const [walletBalance, setWalletBalance] = useState<string | null>(null);

  const hasExternalWallet = user?.linkedAccounts.some(
    (acc) => acc.type === 'wallet' && acc.walletClientType !== 'privy'
  );

  const tokenSymbol = 'USDC';
  const valid = parseFloat(amount) > 0;
  const summary = valid ? `Deposit ${amount} ${tokenSymbol} to ArcPay contract` : '';

  useEffect(() => {
    if (!account) {
      setWalletBalance(null);
      return;
    }
    const fetchWalletBalance = async () => {
      const client = createPublicClient({
        chain: arcTestnet,
        transport: http(arcTestnet.rpcUrls.default.http[0]),
      });
      try {
        const bal = await client.getBalance({ address: account.address as Address });
        setWalletBalance(parseFloat(formatEther(bal)).toFixed(2));
      } catch (e) {
        console.error('Failed to fetch wallet balance:', e);
      }
    };
    fetchWalletBalance();
  }, [account, status.state]); // Re-fetch when transaction status changes

  const submit = async () => {
    if (!valid || !walletClient || !account) return;
    setStatus({ state: 'preparing', summary });
    
    try {
      setStatus({ state: 'signing', summary });
      const hash = (await walletClient.writeContract({
        address: arcPay.address as `0x${string}`,
        abi: arcPay.abi,
        functionName: 'deposit',
        value: parseEther(amount),
        account: account.address as `0x${string}`,
        chain: arcTestnet,
      })) as string;
      setStatus({ state: 'confirming', summary, hash });
      await waitForTx(hash as `0x${string}`);
      setStatus({ state: 'confirmed', summary, hash });
      setAmount('');
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'failed';
      setStatus({ state: 'failed', summary, error: msg.slice(0, 200) });
    }
  };

  return (
    <>
      <PageHeader
        title="Deposit"
        subtitle={`Move native ${tokenSymbol} into the ArcPay smart contract.`}
      />

      <motion.div
        initial={{ opacity: 0, scale: 0.98 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.3 }}
        className="max-w-md w-full"
      >
        <div className="bg-zinc-900 rounded-[24px] p-2 border border-zinc-800 shadow-xl">
          {/* Input Block */}
          <div className="bg-zinc-800/40 rounded-[20px] p-5 border border-zinc-700/30">
            <div className="flex justify-between text-sm text-zinc-400 mb-4 font-medium">
              <span>Deposit</span>
              {walletBalance !== null && (
                <span>Wallet: {walletBalance}</span>
              )}
            </div>
            <div className="flex items-center justify-between">
              <input
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0"
                type="number"
                step="0.0001"
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

          {/* Quick Amounts */}
          <div className="flex gap-2 px-2 py-4">
            {quickAmounts.map((a) => (
              <button
                key={a}
                onClick={() => setAmount(a)}
                className="flex-1 py-1.5 text-xs bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-full transition-colors font-medium"
              >
                {a}
              </button>
            ))}
          </div>

          {/* Action Button */}
          <div className="px-2 pb-2">
            <motion.button
              whileHover={{ scale: valid && ready ? 1.01 : 1 }}
              whileTap={{ scale: valid && ready ? 0.99 : 1 }}
              disabled={!valid || !ready}
              onClick={submit}
              className="w-full py-4 bg-sky-500 hover:bg-sky-400 disabled:bg-zinc-800 disabled:text-zinc-500 text-white rounded-2xl font-semibold text-lg transition-colors flex items-center justify-center gap-2"
            >
              Deposit USDC
            </motion.button>
            
            {user && !hasExternalWallet && (
              <button
                onClick={linkWallet}
                className="w-full mt-3 py-3 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-2xl font-medium text-sm transition-colors border border-zinc-700/50"
              >
                Link External Wallet to fund account
              </button>
            )}
          </div>
        </div>
      </motion.div>

      <TxStatusModal
        status={status}
        onClose={() => setStatus({ state: 'idle' })}
      />
    </>
  );
}
