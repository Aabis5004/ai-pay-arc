'use client';

import { PageHeader } from '@/components/PageHeader';
import { MOCK_POOLS, Pool } from '@/lib/tokens';
import { Sparkles, ArrowDownToLine, Plus, X } from 'lucide-react';
import { useShielded } from '@/lib/useShielded';
import { useWriteContract, useReadContracts, useReadContract, useConfig } from 'wagmi';
import { waitForTransactionReceipt } from '@wagmi/core';
import { parseUnits, parseAbi, erc20Abi, formatUnits, createPublicClient, http } from 'viem';
import { arcTestnet } from '@/lib/chain';
import { ARC_PAY_ADDRESS } from '@/lib/contract';
import { toast } from 'sonner';
import { usePrivy } from '@privy-io/react-auth';
import { TxModal } from '@/components/TxModal';
import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

function PoolRow({ pool, account, showMyPositions, onManage }: { pool: Pool, account: any, showMyPositions: boolean, onManage: () => void }) {
  const { data: bal0 } = useReadContract({
    address: pool.token0.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [ARC_PAY_ADDRESS],
  });

  const { data: bal1 } = useReadContract({
    address: pool.token1.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [ARC_PAY_ADDRESS],
  });

  const { data: lpBal } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: parseAbi(['function getUserLPBalance(address user, address tokenA, address tokenB) external view returns (uint256)']),
    functionName: 'getUserLPBalance',
    args: account ? [account.address as `0x${string}`, pool.token0.address as `0x${string}`, pool.token1.address as `0x${string}`] : undefined,
    query: { enabled: !!account }
  });

  if (showMyPositions && (!lpBal || lpBal === 0n)) {
    return null;
  }

  const getPrice = (symbol: string) => {
    if (symbol === 'cirBTC') return 60000;
    if (symbol === 'EURC') return 1.1;
    return 1;
  };

  let tvlStr = pool.tvl;
  if (bal0 !== undefined && bal1 !== undefined) {
    const num0 = Number(formatUnits(bal0, pool.token0.decimals));
    const num1 = Number(formatUnits(bal1, pool.token1.decimals));
    const tvlValue = (num0 * getPrice(pool.token0.symbol)) + (num1 * getPrice(pool.token1.symbol));
    tvlStr = `$${tvlValue.toLocaleString(undefined, { maximumFractionDigits: 2, minimumFractionDigits: 2 })}`;
  }

  const userLpStr = lpBal ? Number(formatUnits(lpBal, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : '0.00';

  return (
    <tr className="hover:bg-zinc-950 transition-colors group">
      <td className="p-4 pl-6">
        <div className="flex items-center gap-4">
          <div className="flex -space-x-3">
            <img src={pool.token0.icon} alt={pool.token0.symbol} className="w-8 h-8 rounded-full border-2 border-zinc-900 relative z-10 bg-zinc-800" />
            <img src={pool.token1.icon} alt={pool.token1.symbol} className="w-8 h-8 rounded-full border-2 border-zinc-900 bg-zinc-800" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-semibold text-white">{pool.token0.symbol} / {pool.token1.symbol}</span>
              <span className="text-[10px] px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400 font-medium border border-zinc-700">{pool.fee}</span>
            </div>
            <div className="text-xs text-zinc-500 mt-1 flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>
              {pool.type}
            </div>
          </div>
        </div>
      </td>
      <td className="p-4 text-right text-sm text-zinc-300">
        <div className="font-semibold text-white">{tvlStr}</div>
      </td>
      <td className="p-4 text-right text-sm font-semibold text-zinc-300">
        {pool.apr}
      </td>
      <td className="p-4 text-right text-sm font-semibold text-indigo-400">
        {pool.emissionApr}
      </td>
      <td className="p-4 text-right text-sm font-semibold text-zinc-300">
        {userLpStr} LP
      </td>
      <td className="p-4 pr-6 text-right">
        <button 
          onClick={onManage}
          className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1.5 text-indigo-400 hover:text-indigo-300 text-sm font-bold uppercase tracking-wider ml-auto"
        >
          <ArrowDownToLine className="w-4 h-4" />
          Manage
        </button>
      </td>
    </tr>
  );
}

const arcDeFiAbi = parseAbi([
  'function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external',
  'function removeLiquidity(address tokenA, address tokenB, uint256 liquidityAmount) external',
  'function getPoolFeeAPR(address tokenA, address tokenB) external view returns (string)',
  'function getPoolEmissionAPR(address tokenA, address tokenB) external view returns (string)',
  'function getUserLPBalance(address user, address tokenA, address tokenB) external view returns (uint256)'
]);

interface ManageModalProps {
  pool: Pool;
  onClose: () => void;
  onTxSuccess: (hash: string, actionText: string, amountA?: string, tokenA?: string, amountB?: string, tokenB?: string) => void;
}

function ManageModal({ pool, onClose, onTxSuccess }: ManageModalProps) {
  const { account } = useShielded();
  const config = useConfig();
  const { writeContractAsync } = useWriteContract();
  const [activeTab, setActiveTab] = useState<'add' | 'remove'>('add');
  const [amountA, setAmountA] = useState('');
  const [amountB, setAmountB] = useState('');
  const [removePercent, setRemovePercent] = useState('0');
  const [isPending, setIsPending] = useState(false);
  const [txStep, setTxStep] = useState<'approve' | 'execute' | null>(null);

  // Read wallet balances
  const { data: balA } = useReadContract({
    address: pool.token0.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: account ? [account.address as `0x${string}`] : undefined,
  });

  const { data: balB } = useReadContract({
    address: pool.token1.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: account ? [account.address as `0x${string}`] : undefined,
  });

  // Read router allowances
  const { data: allowanceA } = useReadContract({
    address: pool.token0.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: account ? [account.address as `0x${string}`, ARC_PAY_ADDRESS] : undefined,
  });

  const { data: allowanceB } = useReadContract({
    address: pool.token1.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: account ? [account.address as `0x${string}`, ARC_PAY_ADDRESS] : undefined,
  });

  const formatBal = (val: bigint | undefined, dec: number) => {
    if (val === undefined) return '0.00';
    const num = Number(formatUnits(val, dec));
    if (num > 0 && num < 0.01) return num.toFixed(6);
    return num.toFixed(2);
  };
  const displayBalA = formatBal(balA, pool.token0.decimals);
  const displayBalB = formatBal(balB, pool.token1.decimals);

  const { data: lpBalance, refetch: refetchLp } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'getUserLPBalance',
    args: account ? [account.address as `0x${string}`, pool.token0.address as `0x${string}`, pool.token1.address as `0x${string}`] : undefined,
    query: { enabled: !!account },
  });

  const { data: feeApr } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'getPoolFeeAPR',
    args: [pool.token0.address as `0x${string}`, pool.token1.address as `0x${string}`],
  });

  const { data: emissionApr } = useReadContract({
    address: ARC_PAY_ADDRESS,
    abi: arcDeFiAbi,
    functionName: 'getPoolEmissionAPR',
    args: [pool.token0.address as `0x${string}`, pool.token1.address as `0x${string}`],
  });

  const getPrice = (symbol: string) => {
    if (symbol === 'cirBTC') return 60000;
    if (symbol === 'EURC') return 1.1;
    return 1;
  };

  const handleAmountAChange = (val: string) => {
    setAmountA(val);
    if (!val || isNaN(Number(val))) {
      setAmountB('');
      return;
    }
    const priceA = getPrice(pool.token0.symbol);
    const priceB = getPrice(pool.token1.symbol);
    setAmountB((Number(val) * (priceA / priceB)).toFixed(6).replace(/\.?0+$/, ''));
  };

  const handleAmountBChange = (val: string) => {
    setAmountB(val);
    if (!val || isNaN(Number(val))) {
      setAmountA('');
      return;
    }
    const priceA = getPrice(pool.token0.symbol);
    const priceB = getPrice(pool.token1.symbol);
    setAmountA((Number(val) * (priceB / priceA)).toFixed(6).replace(/\.?0+$/, ''));
  };

  const parsedA = amountA ? parseUnits(amountA, pool.token0.decimals) : 0n;
  const parsedB = amountB ? parseUnits(amountB, pool.token1.decimals) : 0n;
  const needsApprovalA = allowanceA !== undefined && allowanceA < parsedA;
  const needsApprovalB = allowanceB !== undefined && allowanceB < parsedB;

  const executeAdd = async () => {
    if (!parsedA || !parsedB) return;
    try {
      setIsPending(true);
      if (needsApprovalA) {
        setTxStep('approve');
        const hash = await writeContractAsync({
          address: pool.token0.address as `0x${string}`,
          abi: erc20Abi,
          functionName: 'approve',
          args: [ARC_PAY_ADDRESS, parsedA],
        });
        await waitForTransactionReceipt(config, { hash });
      } 
      
      if (needsApprovalB) {
        setTxStep('approve');
        const hash = await writeContractAsync({
          address: pool.token1.address as `0x${string}`,
          abi: erc20Abi,
          functionName: 'approve',
          args: [ARC_PAY_ADDRESS, parsedB],
        });
        await waitForTransactionReceipt(config, { hash });
      }
      
      setTxStep('execute');
      const hash = await writeContractAsync({
        address: ARC_PAY_ADDRESS,
        abi: arcDeFiAbi,
        functionName: 'addLiquidity',
        args: [pool.token0.address as `0x${string}`, pool.token1.address as `0x${string}`, parsedA, parsedB],
      });
      await waitForTransactionReceipt(config, { hash });
      toast.success('Liquidity added successfully!');
      onTxSuccess(hash, 'Liquidity Added', amountA, pool.token0.symbol, amountB, pool.token1.symbol);
      onClose();
    } catch (e: any) {
      console.error(e);
      toast.error('Transaction failed. Make sure you have enough tokens.');
    } finally {
      setIsPending(false);
      setTxStep(null);
    }
  };

  const executeRemove = async () => {
    try {
      setIsPending(true);
      setTxStep('execute');
      
      const lpBal = lpBalance as bigint || 0n;
      const pct = BigInt(removePercent);
      const lpAmountToRemove = (lpBal * pct) / 100n;
      
      if (lpAmountToRemove === 0n) {
        toast.error("You do not have enough liquidity to remove.");
        setIsPending(false);
        setTxStep(null);
        return;
      }

      const hash = await writeContractAsync({
        address: ARC_PAY_ADDRESS,
        abi: arcDeFiAbi,
        functionName: 'removeLiquidity',
        args: [pool.token0.address as `0x${string}`, pool.token1.address as `0x${string}`, lpAmountToRemove],
      });
      await waitForTransactionReceipt(config, { hash });
      toast.success('Liquidity removed successfully!');
      onTxSuccess(hash, 'Liquidity Removed');
      onClose();
    } catch (e: any) {
      console.error(e);
      toast.error('Transaction failed. Make sure you actually have liquidity first.');
    } finally {
      setIsPending(false);
      setTxStep(null);
    }
  };

  let btnText = 'Enter an amount';
  if (activeTab === 'add') {
    if (isPending) {
      btnText = txStep === 'approve' ? 'Approving...' : 'Adding Liquidity...';
    } else if (amountA && parseFloat(amountA) > 0) {
      if (needsApprovalA) btnText = `Approve ${pool.token0.symbol}`;
      else if (needsApprovalB) btnText = `Approve ${pool.token1.symbol}`;
      else btnText = 'Add Liquidity';
    }
  } else {
    btnText = isPending ? 'Removing Liquidity...' : 'Remove Liquidity';
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-zinc-950/80 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.95 }}
        className="w-full max-w-xl bg-zinc-900 border border-zinc-800 rounded-[2rem] overflow-hidden shadow-2xl relative"
      >
        <div className="flex justify-between items-center p-6 border-b border-zinc-800">
          <div className="flex gap-6">
            <button
              onClick={() => setActiveTab('add')}
              className={`text-xl font-bold tracking-wide transition-colors ${activeTab === 'add' ? 'text-white' : 'text-zinc-500 hover:text-zinc-300'}`}
            >
              ADD
            </button>
            <button
              onClick={() => setActiveTab('remove')}
              className={`text-xl font-bold tracking-wide transition-colors ${activeTab === 'remove' ? 'text-white' : 'text-zinc-500 hover:text-zinc-300'}`}
            >
              REMOVE
            </button>
          </div>
          <button onClick={onClose} className="text-zinc-500 hover:text-zinc-300 transition-colors">
            <X className="w-6 h-6" />
          </button>
        </div>

        <div className="p-6 space-y-6">
          {activeTab === 'add' ? (
            <>
              <div className="bg-zinc-950 rounded-2xl p-5 border border-zinc-800 transition-colors hover:border-zinc-700">
                <div className="flex justify-between text-sm mb-3 text-zinc-500 font-medium">
                  <span>Deposit Amount</span>
                  <span>Balance: {displayBalA} {pool.token0.symbol}</span>
                </div>
                <div className="flex items-center gap-4">
                  <input 
                    type="number"
                    value={amountA}
                    onChange={(e) => handleAmountAChange(e.target.value)}
                    placeholder="0.0"
                    className="bg-transparent text-4xl font-medium text-white outline-none w-full placeholder:text-zinc-700"
                  />
                  <div className="flex items-center gap-2 bg-zinc-900 border border-zinc-800 px-4 py-2 rounded-full shrink-0 shadow-sm">
                    <img src={pool.token0.icon} alt={pool.token0.symbol} className="w-6 h-6 rounded-full" />
                    <span className="text-white font-semibold">{pool.token0.symbol}</span>
                  </div>
                </div>
              </div>

              <div className="flex justify-center -my-3 relative z-10">
                <div className="bg-indigo-600 rounded-full p-2 border-4 border-zinc-900 shadow-sm">
                  <Plus className="w-5 h-5 text-white" />
                </div>
              </div>

              <div className="bg-zinc-950 rounded-2xl p-5 border border-zinc-800 transition-colors hover:border-zinc-700">
                <div className="flex justify-between text-sm mb-3 text-zinc-500 font-medium">
                  <span>Deposit Amount</span>
                  <span>Balance: {displayBalB} {pool.token1.symbol}</span>
                </div>
                <div className="flex items-center gap-4">
                  <input 
                    type="number"
                    value={amountB}
                    onChange={(e) => handleAmountBChange(e.target.value)}
                    placeholder="0.0"
                    className="bg-transparent text-4xl font-medium text-white outline-none w-full placeholder:text-zinc-700"
                  />
                  <div className="flex items-center gap-2 bg-zinc-900 border border-zinc-800 px-4 py-2 rounded-full shrink-0 shadow-sm">
                    <img src={pool.token1.icon} alt={pool.token1.symbol} className="w-6 h-6 rounded-full" />
                    <span className="text-white font-semibold">{pool.token1.symbol}</span>
                  </div>
                </div>
              </div>

              <div className="p-4 bg-zinc-950 rounded-xl border border-zinc-800 space-y-2">
                <div className="flex justify-between items-center text-sm">
                  <span className="text-zinc-500 font-medium">Trading Fee APR</span>
                  <span className="text-white font-semibold">{feeApr as string || pool.apr}</span>
                </div>
                <div className="flex justify-between items-center text-sm">
                  <span className="text-zinc-500 font-medium">Emission APR</span>
                  <span className="text-indigo-400 font-semibold">{emissionApr as string || pool.emissionApr}</span>
                </div>
                <div className="pt-2 mt-2 border-t border-zinc-800 text-xs text-zinc-600">
                  By adding liquidity, you will earn fees proportional to your share of the pool.
                </div>
              </div>

              <button 
                onClick={executeAdd}
                disabled={isPending || !amountA || parseFloat(amountA) === 0}
                className="w-full py-4 bg-white hover:bg-zinc-200 text-black disabled:opacity-50 font-bold rounded-2xl transition-all shadow-md uppercase tracking-wider active:scale-[0.98]"
              >
                {btnText}
              </button>
            </>
          ) : (
            <>
              <div className="bg-zinc-950 rounded-2xl p-5 border border-zinc-800 mb-4">
                <div className="text-sm text-zinc-500 font-medium mb-1">Your Pool Share</div>
                <div className="text-3xl font-semibold text-white">
                  {lpBalance ? Number(formatUnits(lpBalance as bigint, 6)).toLocaleString() : '0.00'} <span className="text-sm font-medium text-zinc-600">LP Tokens</span>
                </div>
              </div>

              <div className="bg-zinc-950 rounded-2xl p-5 border border-zinc-800">
                <div className="flex justify-between text-sm mb-6 text-zinc-500 font-medium">
                  <span>Amount to Remove</span>
                  <span className="text-white font-bold">{removePercent}%</span>
                </div>
                
                <div className="text-5xl font-semibold text-center text-white mb-8">
                  {removePercent}%
                </div>

                <input 
                  type="range"
                  min="0"
                  max="100"
                  value={removePercent}
                  onChange={(e) => setRemovePercent(e.target.value)}
                  className="w-full accent-indigo-500 mb-6"
                />

                <div className="flex gap-2">
                  {[25, 50, 75, 100].map(pct => (
                    <button
                      key={pct}
                      onClick={() => setRemovePercent(pct.toString())}
                      className="flex-1 py-2 bg-zinc-900 hover:bg-zinc-800 text-zinc-300 border border-zinc-800 rounded-lg text-sm font-semibold transition-colors shadow-sm"
                    >
                      {pct}%
                    </button>
                  ))}
                </div>
              </div>

              <button 
                onClick={executeRemove}
                disabled={isPending || removePercent === '0'}
                className="w-full py-4 bg-red-500 hover:bg-red-600 text-white disabled:opacity-50 font-bold rounded-2xl transition-all shadow-md uppercase tracking-wider active:scale-[0.98]"
              >
                {btnText}
              </button>
            </>
          )}
        </div>
      </motion.div>
    </div>
  );
}

export default function LiquidityPage() {
  const { account } = useShielded();
  const { login } = usePrivy();
  const [selectedPool, setSelectedPool] = useState<Pool | null>(null);

  const [showMyPositions, setShowMyPositions] = useState(false);

  // Modal state
  const [modalOpen, setModalOpen] = useState(false);
  const [lastTxHash, setLastTxHash] = useState('');
  const [lastAction, setLastAction] = useState('Transaction Completed');
  const [lastSentA, setLastSentA] = useState<{amount?: string, token?: string}>({});
  const [lastSentB, setLastSentB] = useState<{amount?: string, token?: string}>({});

  const handleTxSuccess = (hash: string, actionText: string, amountA?: string, tokenA?: string, amountB?: string, tokenB?: string) => {
    setLastTxHash(hash);
    setLastAction(actionText);
    setLastSentA({ amount: amountA, token: tokenA });
    setLastSentB({ amount: amountB, token: tokenB });
    setModalOpen(true);
    setSelectedPool(null);
  };

  const handleDepositClick = (pool: Pool) => {
    if (!account) {
      login();
      return;
    }
    setSelectedPool(pool);
  };

  return (
    <>
      <TxModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        hash={lastTxHash}
        actionText={lastAction}
        sentAmount={lastSentA.amount}
        sentToken={lastSentA.token}
        receivedAmount={lastSentB.amount}
        receivedToken={lastSentB.token}
      />
      
      <div className="w-full max-w-6xl mx-auto space-y-6 pt-8 pb-20">
      <AnimatePresence>
        {selectedPool && (
          <ManageModal 
            pool={selectedPool} 
            onClose={() => setSelectedPool(null)}
            onTxSuccess={handleTxSuccess}
          />
        )}
      </AnimatePresence>

      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <PageHeader 
          title="Pools" 
          subtitle="Provide liquidity to earn trading fees and emissions."
        />
        <div className="flex gap-2">
          <button 
            onClick={() => setShowMyPositions(!showMyPositions)}
            className={`px-4 py-2 border text-sm font-medium rounded-xl transition-colors shadow-sm ${showMyPositions ? 'bg-zinc-800 border-zinc-700 text-white' : 'bg-zinc-900 border-zinc-800 hover:bg-zinc-800 text-zinc-300'}`}
          >
            My Positions
          </button>
          <button 
            onClick={() => handleDepositClick(MOCK_POOLS[0])}
            className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 flex items-center gap-2 text-sm font-bold rounded-xl transition-colors text-white shadow-sm uppercase tracking-wider"
          >
            <Plus className="w-4 h-4" /> Create Pool
          </button>
        </div>
      </div>

      <div className="bg-zinc-900 border border-zinc-800 rounded-[2rem] overflow-hidden shadow-[0_8px_30px_rgb(0,0,0,0.2)]">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-zinc-800 text-xs font-semibold text-zinc-500 uppercase tracking-wider bg-zinc-950/50">
                <th className="p-4 pl-6 font-medium">Pools</th>
                <th className="p-4 font-medium text-right">TVL ↓</th>
                <th className="p-4 font-medium text-right">Fee APR</th>
                <th className="p-4 font-medium text-right">Emission APR</th>
                <th className="p-4 font-medium text-right">Your LP</th>
                <th className="p-4 pr-6"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {MOCK_POOLS.map((pool) => (
                <PoolRow 
                  key={pool.id} 
                  pool={pool} 
                  account={account} 
                  showMyPositions={showMyPositions} 
                  onManage={() => handleDepositClick(pool)} 
                />
              ))}
            </tbody>
          </table>
        </div>
      </div>
      
      <div className="p-4 bg-indigo-50 border border-indigo-100 rounded-2xl flex items-start gap-3 mt-6 max-w-xl mx-auto text-center">
        <Sparkles className="w-5 h-5 text-indigo-500 mt-0.5 shrink-0" />
        <div className="text-sm text-indigo-900/80 text-left">
          <strong className="text-indigo-900 font-semibold block mb-1">AI Smart LP (Coming Soon)</strong>
          Automatically rebalance your liquidity ranges and compound rewards using Arc AI agents to maximize yields.
        </div>
      </div>
    </div>
    </>
  );
}
