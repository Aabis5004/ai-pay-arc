'use client';

import { motion } from 'framer-motion';
import { useState, useEffect } from 'react';
import { parseUnits, formatUnits, parseAbi, erc20Abi } from 'viem';
import { ARC_PAY_ADDRESS } from '@/lib/contract';
import { useShielded } from '@/lib/useShielded';
import { usePrivy } from '@privy-io/react-auth';
import { waitForTx } from '@/lib/history';
import { PageHeader } from '@/components/PageHeader';
import { TxModal } from '@/components/TxModal';
import { MOCK_TOKENS } from '@/lib/tokens';
import { useReadContract, useWriteContract } from 'wagmi';

const quickAmounts = ['10', '50', '100', '500'];

const arcDeFiAbi = parseAbi([
  'function withdraw(address token, uint256 amount) external',
  'function vaultBalance(address user, address token) external view returns (uint256)'
]);

export default function WithdrawPage() {
  const { account, ready } = useShielded();
  const { user, login } = usePrivy();
  const [amount, setAmount] = useState('');
  const [isTxPending, setIsTxPending] = useState(false);
  const [txStep, setTxStep] = useState<'approve' | 'execute' | null>(null);

  // Modal state
  const [modalOpen, setModalOpen] = useState(false);
  const [lastTxHash, setLastTxHash] = useState('');
  const [lastAmount, setLastAmount] = useState('');

  const tokenToWithdraw = MOCK_TOKENS[0]; // USDC
  const valid = parseFloat(amount) > 0;
  const summary = valid ? `Withdraw ${amount} ${tokenToWithdraw.symbol} to Vault` : '';

  const { writeContractAsync } = useWriteContract();

  // Read wallet balance
  const { data: walletBalance } = useReadContract({
    address: tokenToWithdraw.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: account ? [account.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenToWithdraw.address.startsWith('0x') },
  });

  // Read vault balance
  const { data: vaultBalance, refetch: refetchVault } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'vaultBalance',
    args: account ? [account.address as `0x${string}`, tokenToWithdraw.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenToWithdraw.address.startsWith('0x') },
  });

  // Read allowance
  const { data: allowance } = useReadContract({
    address: tokenToWithdraw.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: account ? [account.address as `0x${string}`, ARC_PAY_ADDRESS] : undefined,
    query: { enabled: !!account && !!tokenToWithdraw.address.startsWith('0x') },
  });

  const displayWallet = walletBalance !== undefined ? Number(formatUnits(walletBalance, tokenToWithdraw.decimals)).toFixed(2) : '0.00';
  const displayVault = vaultBalance !== undefined ? Number(formatUnits(vaultBalance, tokenToWithdraw.decimals)).toFixed(2) : '0.00';

  const parsedAmount = amount ? parseUnits(amount, tokenToWithdraw.decimals) : 0n;
  const needsApproval = false;

  const submit = async () => {
    if (!account) {
      login();
      return;
    }
    if (!valid) return;
    setIsTxPending(true);
    
    try {
      

      setTxStep('execute');
      const hash = await writeContractAsync({
        address: ARC_PAY_ADDRESS,
        abi: arcDeFiAbi,
        functionName: 'withdraw',
        args: [tokenToWithdraw.address as `0x${string}`, parsedAmount],
      });
      await waitForTx(hash as `0x${string}`);
      
      setLastTxHash(hash);
      setLastAmount(amount);
      setModalOpen(true);
      
      setAmount('');
      refetchVault();
    } catch (e) {
      console.error(e);
      import('sonner').then(s => s.toast.error('Transaction failed.'));
    } finally {
      setIsTxPending(false);
      setTxStep(null);
    }
  };

  let buttonText = 'Connect Wallet';
  if (account) {
    if (isTxPending) {
      buttonText = txStep === 'approve' ? 'Approving...' : 'Withdrawing...';
    }
    else if (!amount || parseFloat(amount) === 0) buttonText = 'Enter an amount';
    else if (needsApproval) buttonText = `Approve ${tokenToWithdraw.symbol}`;
    else buttonText = 'Withdraw';
  }

  return (
    <>
      <TxModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        hash={lastTxHash}
        actionText="Withdraw Completed"
        sentAmount={lastAmount}
        sentToken={tokenToWithdraw.symbol}
      />
      
      <PageHeader
        title="Withdraw"
        subtitle={`Move ${tokenToWithdraw.symbol} out of the smart contract Vault back to your wallet.`}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl">
        <motion.div
          initial={{ opacity: 0, scale: 0.98 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.3 }}
          className="w-full"
        >
          <div className="bg-zinc-900 rounded-[24px] p-2 border border-zinc-800 shadow-xl">
            {/* Input Block */}
            <div className="bg-zinc-800/40 rounded-[20px] p-5 border border-zinc-700/30">
              <div className="flex justify-between text-sm text-zinc-400 mb-4 font-medium">
                <span>Withdraw</span>
                {account && (
                  <div className="flex items-center gap-2">
                    <span>Vault: {displayVault}</span>
                    <button onClick={() => { if (vaultBalance) setAmount(formatUnits(vaultBalance, tokenToWithdraw.decimals)); }} className="text-sky-400 hover:text-sky-300 font-bold tracking-wide text-xs">MAX</button>
                  </div>
                )}
              </div>
              <div className="flex items-center justify-between">
                <input
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="0.0"
                  type="number"
                  step="0.1"
                  className="text-4xl font-medium outline-none text-white placeholder:text-zinc-600 w-full bg-transparent"
                />
                <div className="flex items-center gap-2 bg-zinc-700/50 rounded-full px-3 py-2 shrink-0 border border-zinc-600/50 shadow-sm">
                  <img src={tokenToWithdraw.icon} alt="USDC" className="w-5 h-5 rounded-full" />
                  <span className="text-white font-medium pr-1 text-sm">{tokenToWithdraw.symbol}</span>
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
              <button
                onClick={submit}
                disabled={(!valid && !!account) || !ready || isTxPending}
                className="w-full mt-6 py-4 px-6 bg-white hover:bg-zinc-200 disabled:opacity-50 text-black font-bold rounded-[16px] transition-all shadow-md active:scale-[0.98] uppercase tracking-wider"
              >
                {buttonText}
              </button>
            </div>
          </div>
        </motion.div>

        {/* Website Balance Card */}
        <div className="bg-zinc-950/80 backdrop-blur-xl border border-zinc-800/80 rounded-3xl p-8 flex flex-col justify-center shadow-xl">
          <h3 className="text-zinc-400 text-sm font-medium mb-2 uppercase tracking-widest">Your Vault Balance</h3>
          <div className="text-5xl font-light text-white flex items-baseline gap-2">
            {displayVault} <span className="text-xl text-zinc-500 font-normal">{tokenToWithdraw.symbol}</span>
          </div>
          <p className="text-zinc-500 text-sm mt-4 leading-relaxed">
            These funds are stored securely in the smart contract and are ready to be used by the AI Agent for recurring payments and auto-swaps.
          </p>
        </div>
      </div>
    </>
  );
}
