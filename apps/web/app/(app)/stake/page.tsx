'use client';

import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/Card';
import { TrendingUp, ArrowDown } from 'lucide-react';
import { MOCK_TOKENS, Token } from '@/lib/tokens';
import { useState, useEffect } from 'react';
import { useShielded } from '@/lib/useShielded';
import { useWriteContract, useReadContract, useConfig } from 'wagmi';
import { parseUnits, parseAbi, erc20Abi, formatUnits } from 'viem';
import { ARC_PAY_ADDRESS } from '@/lib/contract';
import { toast } from 'sonner';
import { usePrivy } from '@privy-io/react-auth';
import { TxModal } from '@/components/TxModal';
import { waitForTx } from '@/lib/history';
import { waitForTransactionReceipt } from '@wagmi/core';
import { motion, AnimatePresence } from 'framer-motion';

const arcDeFiAbi = parseAbi([
  'function stake(address token, uint256 amount) external',
  'function unstake(address token, uint256 amount) external',
  'function stakedBalance(address user, address token) external view returns (uint256)',
  'function unlockTime(address user, address token) external view returns (uint256)',
  'function getStakeAPR(address token) external view returns (string)'
]);

function TokenSelector({
  value,
  onChange,
}: {
  value: Token;
  onChange: (t: Token) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      <button
        onClick={() => setIsOpen(true)}
        className="flex items-center gap-2 bg-zinc-900 hover:bg-zinc-800 transition-colors px-3 py-1.5 rounded-full border border-zinc-800/80"
      >
        {value.icon.startsWith('http') ? (
          <img src={value.icon} alt={value.symbol} className="w-5 h-5 rounded-full" />
        ) : (
          <div className="w-5 h-5 rounded-full bg-sky-500/20 flex items-center justify-center text-[10px] text-sky-400 font-bold border border-sky-500/30">
            {value.symbol[0]}
          </div>
        )}
        <span className="font-semibold text-white">{value.symbol}</span>
        <ArrowDown className="w-4 h-4 text-zinc-400" />
      </button>

      <AnimatePresence>
        {isOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="w-full max-w-sm bg-zinc-950 border border-zinc-800 rounded-2xl overflow-hidden shadow-2xl"
            >
              <div className="p-4 border-b border-zinc-800 flex justify-between items-center">
                <h2 className="text-lg font-medium text-white">Select a token</h2>
                <button onClick={() => setIsOpen(false)} className="text-zinc-400 hover:text-white">
                  ✕
                </button>
              </div>
              <div className="max-h-[60vh] overflow-y-auto p-2">
                {MOCK_TOKENS.map((token) => (
                  <button
                    key={token.symbol}
                    onClick={() => {
                      onChange(token);
                      setIsOpen(false);
                    }}
                    className="w-full flex items-center gap-3 p-3 hover:bg-zinc-900 rounded-xl transition-colors text-left"
                  >
                    {token.icon.startsWith('http') ? (
                      <img src={token.icon} alt={token.symbol} className="w-8 h-8 rounded-full" />
                    ) : (
                      <div className="w-8 h-8 rounded-full bg-sky-500/20 flex items-center justify-center text-sm text-sky-400 font-bold border border-sky-500/30">
                        {token.symbol[0]}
                      </div>
                    )}
                    <div>
                      <div className="text-white font-medium">{token.symbol}</div>
                      <div className="text-sm text-zinc-500">{token.name}</div>
                    </div>
                  </button>
                ))}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </>
  );
}

export default function StakePage() {
  const { account } = useShielded();
  const { login } = usePrivy();
  const [activeTab, setActiveTab] = useState<'stake' | 'unstake'>('stake');
  const [tokenToStake, setTokenToStake] = useState(MOCK_TOKENS[0]);
  const [amount, setAmount] = useState('');
  
  // Modal state
  const [modalOpen, setModalOpen] = useState(false);
  const [lastTxHash, setLastTxHash] = useState('');
  const [lastAmount, setLastAmount] = useState('');
  const [lastAction, setLastAction] = useState('Stake Completed');
  const [isTxPending, setIsTxPending] = useState(false);

  const [txStep, setTxStep] = useState<'approve' | 'execute' | null>(null);

  const config = useConfig();
  const { writeContractAsync } = useWriteContract();

  const { data: balance, refetch: refetchBal } = useReadContract({
    address: tokenToStake.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: account ? [account.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenToStake.address.startsWith('0x') },
  });

  const { data: allowance } = useReadContract({
    address: tokenToStake.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: account ? [account.address as `0x${string}`, ARC_PAY_ADDRESS] : undefined,
    query: { enabled: !!account && !!tokenToStake.address.startsWith('0x') },
  });

  const { data: stakedBalance, refetch: refetchStaked } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'stakedBalance',
    args: account ? [account.address as `0x${string}`, tokenToStake.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenToStake.address.startsWith('0x') },
  });

  const { data: globalStaked, refetch: refetchGlobal } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: parseAbi(['function totalStaked(address token) external view returns (uint256)']),
    functionName: 'totalStaked',
    args: [tokenToStake.address as `0x${string}`],
    query: { enabled: !!tokenToStake.address.startsWith('0x') },
  });

  const { data: unlockTimeRaw, refetch: refetchUnlock } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'unlockTime',
    args: account ? [account.address as `0x${string}`, tokenToStake.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenToStake.address.startsWith('0x') },
  });

  const { data: aprStr } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'getStakeAPR',
    args: [tokenToStake.address as `0x${string}`],
    query: { enabled: !!tokenToStake.address.startsWith('0x') },
  });

  const [cooldownSecs, setCooldownSecs] = useState<number>(0);
  useEffect(() => {
    if (unlockTimeRaw === undefined) return;
    const interval = setInterval(() => {
      const now = Math.floor(Date.now() / 1000);
      const unlock = Number(unlockTimeRaw);
      setCooldownSecs(unlock > now ? unlock - now : 0);
    }, 1000);
    return () => clearInterval(interval);
  }, [unlockTimeRaw]);

  const displayBal = balance !== undefined ? Number(formatUnits(balance, tokenToStake.decimals)).toFixed(2) : '0.00';
  const displayStaked = stakedBalance !== undefined ? Number(formatUnits(stakedBalance, tokenToStake.decimals)).toFixed(2) : '0.00';
  const displayGlobalStaked = globalStaked !== undefined ? Number(formatUnits(globalStaked, tokenToStake.decimals)).toLocaleString() : '0.00';

  const parsedAmount = amount ? parseUnits(amount, tokenToStake.decimals) : 0n;
  const needsApproval = allowance !== undefined && allowance < parsedAmount;

  const handleExecute = async () => {
    if (!account) {
      login();
      return;
    }
    if (!parsedAmount) return;

    try {
      setIsTxPending(true);

      if (activeTab === 'stake') {
        if (needsApproval) {
          setTxStep('approve');
          const hash = await writeContractAsync({
            address: tokenToStake.address as `0x${string}`,
            abi: erc20Abi,
            functionName: 'approve',
            args: [ARC_PAY_ADDRESS, parsedAmount],
          });
          await waitForTransactionReceipt(config, { hash });
        }
        
        setTxStep('execute');
        const hash = await writeContractAsync({
          address: ARC_PAY_ADDRESS,
          abi: arcDeFiAbi,
          functionName: 'stake',
          args: [tokenToStake.address as `0x${string}`, parsedAmount],
        });
        await waitForTransactionReceipt(config, { hash });
        
        setLastTxHash(hash);
        setLastAmount(amount);
        setLastAction('Stake Completed');
        setModalOpen(true);

        setAmount('');
        refetchBal();
        refetchStaked();
        refetchGlobal();
        toast.success('Stake successful!');
      } else {
        setTxStep('execute');
        const hash = await writeContractAsync({
          address: ARC_PAY_ADDRESS,
          abi: arcDeFiAbi,
          functionName: 'unstake',
          args: [tokenToStake.address as `0x${string}`, parsedAmount],
        });
        await waitForTransactionReceipt(config, { hash });
        
        setLastTxHash(hash);
        setLastAmount(amount);
        setLastAction('Unstake Completed');
        setModalOpen(true);

        setAmount('');
        refetchBal();
        refetchStaked();
        refetchGlobal();
        toast.success('Unstake successful!');
      }
    } catch (e: any) {
      console.error(e);
      if (e.message?.includes('CooldownNotFinished')) {
        toast.error('Cooldown period not finished yet (2 minutes).');
      } else {
        toast.error('Transaction failed. Check console for details.');
      }
    } finally {
      setIsTxPending(false);
      setTxStep(null);
    }
  };

  const isCooldownActive = activeTab === 'unstake' && cooldownSecs > 0;
  const isButtonDisabled = isTxPending || isCooldownActive || (!!account && (!amount || parseFloat(amount) === 0));
  let buttonText = activeTab === 'stake' ? 'Connect to Stake' : 'Connect to Unstake';
  
  if (account) {
    if (isTxPending) {
      buttonText = txStep === 'approve' ? 'Approving...' : (activeTab === 'stake' ? 'Staking...' : 'Unstaking...');
    }
    else if (isCooldownActive) {
      buttonText = `Cooldown: ${cooldownSecs}s remaining`;
    }
    else if (!amount || parseFloat(amount) === 0) buttonText = 'Enter an amount';
    else if (activeTab === 'stake' && needsApproval) buttonText = `Approve ${tokenToStake.symbol}`;
    else buttonText = activeTab === 'stake' ? 'Stake Tokens' : 'Unstake Tokens';
  }

  return (
    <>
      <TxModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        hash={lastTxHash}
        actionText={lastAction}
        sentAmount={lastAction.includes('Stake') ? lastAmount : undefined}
        sentToken={lastAction.includes('Stake') ? tokenToStake.symbol : undefined}
        receivedAmount={lastAction.includes('Unstake') ? lastAmount : undefined}
        receivedToken={lastAction.includes('Unstake') ? tokenToStake.symbol : undefined}
      />
      <div className="w-full max-w-4xl mx-auto space-y-8 pt-8 pb-20">
        <PageHeader 
          title="Stake" 
          subtitle="Earn protocol revenue by staking your tokens securely."
        />

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <Card className="p-6 bg-zinc-950/80 backdrop-blur-xl border border-zinc-800/80">
            <div className="text-zinc-500 text-sm mb-2 flex items-center gap-2">
              Dynamic APR
            </div>
            <div className="text-3xl font-light text-[#00D09E]">{aprStr || "0.00%"}</div>
          </Card>

        {/* Real Stats */}
        <Card className="p-6 bg-zinc-950/80 backdrop-blur-xl border border-zinc-800/80">
          <div className="text-zinc-500 text-sm mb-2 flex items-center gap-2">
            <TrendingUp className="w-4 h-4 text-sky-400" /> Total {tokenToStake.symbol} Staked
          </div>
          <div className="text-3xl font-light text-white">{displayGlobalStaked} {tokenToStake.symbol}</div>
        </Card>

        <Card className="p-6 bg-zinc-950/80 backdrop-blur-xl border border-zinc-800/80">
          <div className="text-zinc-500 text-sm mb-2 flex items-center gap-2">
            Your Staked {tokenToStake.symbol}
          </div>
          <div className="text-3xl font-light text-white">{displayStaked} {tokenToStake.symbol}</div>
        </Card>
      </div>

      <div className="max-w-2xl mx-auto">
        <Card className="p-1 bg-zinc-950/80 backdrop-blur-xl border border-zinc-800/80 shadow-2xl">
          <div className="p-6 space-y-6">
            <div className="flex justify-between items-center border-b border-zinc-800/50 pb-6">
              <div className="flex flex-col gap-1">
                <span className="text-sm text-zinc-500 font-medium">Select Token</span>
                <TokenSelector value={tokenToStake} onChange={setTokenToStake} />
              </div>
              <div className="text-right">
                <div className="text-white font-medium text-lg">{displayStaked} staked</div>
                <p className="text-sm text-zinc-500">Current position</p>
              </div>
            </div>

            <div className="flex gap-4 mb-4">
              <button
                onClick={() => setActiveTab('stake')}
                className={`text-lg font-semibold tracking-wide transition-colors ${activeTab === 'stake' ? 'text-white border-b-2 border-sky-400 pb-1' : 'text-zinc-600 hover:text-zinc-400'}`}
              >
                STAKE
              </button>
              <button
                onClick={() => setActiveTab('unstake')}
                className={`text-lg font-semibold tracking-wide transition-colors ${activeTab === 'unstake' ? 'text-white border-b-2 border-sky-400 pb-1' : 'text-zinc-600 hover:text-zinc-400'}`}
              >
                UNSTAKE
              </button>
            </div>

            <div className="bg-zinc-900/50 p-5 rounded-2xl border border-zinc-800/50 hover:border-zinc-700/50 transition-colors">
              <div className="flex justify-between text-sm text-zinc-500 mb-3 font-medium">
                <span>{activeTab === 'stake' ? 'Amount to Stake' : 'Amount to Unstake'}</span>
                <div className="flex gap-3 items-center">
                  <span>Balance: {activeTab === 'stake' ? displayBal : displayStaked}</span>
                  <button onClick={() => {
                    if (activeTab === 'stake' && balance) setAmount(formatUnits(balance, tokenToStake.decimals));
                    if (activeTab === 'unstake' && stakedBalance) setAmount(formatUnits(stakedBalance, tokenToStake.decimals));
                  }} className="text-sky-400 hover:text-sky-300 font-bold tracking-wide">MAX</button>
                </div>
              </div>
              <div className="flex items-center gap-4">
                <input
                  type="number"
                  placeholder="0.0"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  className="bg-transparent text-4xl font-light text-white outline-none w-full placeholder:text-zinc-700"
                />
                <span className="text-xl text-zinc-500 font-medium px-2">{tokenToStake.symbol}</span>
              </div>
            </div>

            <button 
              onClick={handleExecute}
              disabled={isButtonDisabled && !!account}
              className="w-full py-4 bg-sky-500 hover:bg-sky-400 disabled:opacity-50 disabled:hover:bg-sky-500 text-white font-semibold rounded-2xl transition-colors shadow-[0_0_20px_rgba(14,165,233,0.3)] text-lg"
            >
              {buttonText}
            </button>
          </div>
        </Card>
      </div>
    </div>
    </>
  );
}
