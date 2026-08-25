'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowDown, Settings, Sparkles } from 'lucide-react';
import { MOCK_TOKENS, Token } from '@/lib/tokens';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/Card';
import { useShielded } from '@/lib/useShielded';
import { useReadContract, useWriteContract, useConfig } from 'wagmi';
import { waitForTransactionReceipt } from 'wagmi/actions';
import { erc20Abi, formatUnits, parseUnits, parseAbi } from 'viem';
import { ARC_PAY_ADDRESS } from '@/lib/contract';
import { toast } from 'sonner';
import { usePrivy } from '@privy-io/react-auth';
import { TxModal } from '@/components/TxModal';

const arcDeFiAbi = parseAbi([
  'function swap(address tokenIn, address tokenOut, uint256 amountIn) external',
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

export default function SwapPage() {
  const { account, ready } = useShielded();
  const { login } = usePrivy();
  const config = useConfig();
  const [tokenIn, setTokenIn] = useState(MOCK_TOKENS[0]); 
  const [tokenOut, setTokenOut] = useState(MOCK_TOKENS[1]); 
  const [amountIn, setAmountIn] = useState('');
  const [amountOut, setAmountOut] = useState('');

  // Fetch balances
  const { data: balanceIn } = useReadContract({
    address: tokenIn.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: account ? [account.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenIn.address.startsWith('0x') },
  });

  const { data: balanceOut } = useReadContract({
    address: tokenOut.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: account ? [account.address as `0x${string}`] : undefined,
    query: { enabled: !!account && !!tokenOut.address.startsWith('0x') },
  });

  const { data: allowance } = useReadContract({
    address: tokenIn.address as `0x${string}`,
    abi: erc20Abi,
    functionName: 'allowance',
    args: account ? [account.address as `0x${string}`, ARC_PAY_ADDRESS] : undefined,
    query: { enabled: !!account && !!tokenIn.address.startsWith('0x') },
  });

  const { writeContractAsync } = useWriteContract();
  const [isTxPending, setIsTxPending] = useState(false);
  const [txStep, setTxStep] = useState<'approve' | 'swap' | null>(null);
  
  // Modal state
  const [modalOpen, setModalOpen] = useState(false);
  const [lastTxHash, setLastTxHash] = useState('');
  const [lastSent, setLastSent] = useState({ amount: '', token: '' });
  const [lastReceived, setLastReceived] = useState({ amount: '', token: '' });

  const displayBalIn = balanceIn !== undefined ? Number(formatUnits(balanceIn, tokenIn.decimals)).toFixed(2) : '0.00';
  const displayBalOut = balanceOut !== undefined ? Number(formatUnits(balanceOut, tokenOut.decimals)).toFixed(2) : '0.00';
  
  const parsedAmountIn = amountIn ? parseUnits(amountIn, tokenIn.decimals) : 0n;
  const needsApproval = allowance !== undefined && allowance < parsedAmountIn;

  const handleSwapTokens = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn(amountOut);
    setAmountOut(amountIn);
  };

  const handleAmountInChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    setAmountIn(val);
    if (val && parseFloat(val) > 0) {
      // 1:1 dummy estimation since stablecoins
      setAmountOut(val);
    } else {
      setAmountOut('');
    }
  };

  const executeAction = async () => {
    if (!account) {
      login();
      return;
    }
    if (!parsedAmountIn) return;

    try {
      setIsTxPending(true);
      if (needsApproval) {
        setTxStep('approve');
        const hash = await writeContractAsync({
          address: tokenIn.address as `0x${string}`,
          abi: erc20Abi,
          functionName: 'approve',
          args: [ARC_PAY_ADDRESS, parsedAmountIn],
        });
        await waitForTransactionReceipt(config, { hash });
      }
      
      setTxStep('swap');
      const hash = await writeContractAsync({
        address: ARC_PAY_ADDRESS,
        abi: arcDeFiAbi,
        functionName: 'swap',
        args: [tokenIn.address as `0x${string}`, tokenOut.address as `0x${string}`, parsedAmountIn],
      });
      await waitForTransactionReceipt(config, { hash });

      // Show modal instead of just toast
      setLastTxHash(hash);
      setLastSent({ amount: amountIn, token: tokenIn.symbol });
      setLastReceived({ amount: amountOut, token: tokenOut.symbol });
      setModalOpen(true);
      toast.success('Swap successful!');

      setAmountIn('');
      setAmountOut('');
    } catch (e: any) {
      console.error(e);
      toast.error('Swap failed. Check console for details.');
    } finally {
      setIsTxPending(false);
      setTxStep(null);
    }
  };

  const isButtonDisabled = isTxPending || (!!account && !amountIn);
  let buttonText = 'Connect Wallet to Swap';
  if (account) {
    if (isTxPending) {
      buttonText = txStep === 'approve' ? 'Approving...' : 'Swapping...';
    }
    else if (!amountIn || parseFloat(amountIn) === 0) buttonText = 'Enter an amount';
    else if (needsApproval) buttonText = `Swap ${tokenIn.symbol}`;
    else buttonText = 'Swap';
  }

  return (
    <>
      <TxModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        hash={lastTxHash}
        actionText="Swap Completed"
        sentAmount={lastSent.amount}
        sentToken={lastSent.token}
        receivedAmount={lastReceived.amount}
        receivedToken={lastReceived.token}
      />
      
      <div className="max-w-2xl mx-auto w-full space-y-6 pt-12">
      <PageHeader 
        title="Swap" 
        subtitle="Exchange tokens instantly on Arc Testnet."
      />

      <div className="relative">
        {/* Glow effect behind the card */}
        <div className="absolute -inset-1 bg-gradient-to-r from-sky-500/20 to-blue-500/20 rounded-[2rem] blur-xl opacity-50" />
        
        <Card className="relative p-1 bg-zinc-950/80 backdrop-blur-xl border border-zinc-800/80 shadow-2xl rounded-3xl">
          <div className="flex justify-between items-center p-4">
            <div className="text-sm font-medium text-white/80">Swap</div>
            <button className="p-2 hover:bg-zinc-800 rounded-full text-zinc-400 transition-colors">
              <Settings className="w-4 h-4" />
            </button>
          </div>

          <div className="p-2 space-y-1">
            {/* Input Section */}
            <div className="bg-zinc-900/50 p-4 rounded-2xl border border-zinc-800/50 hover:border-zinc-700/50 transition-colors">
              <div className="text-sm text-zinc-500 mb-2">You pay</div>
              <div className="flex justify-between items-center gap-4">
                <input
                  type="number"
                  placeholder="0.0"
                  value={amountIn}
                  onChange={handleAmountInChange}
                  className="bg-transparent text-4xl font-light text-white outline-none w-full placeholder:text-zinc-700"
                />
                <TokenSelector value={tokenIn} onChange={setTokenIn} />
              </div>
              <div className="text-xs text-zinc-500 mt-3 flex justify-between items-center">
                <span>~$0.00</span>
                <div className="flex items-center gap-2">
                  <span>Balance: {displayBalIn}</span>
                  <button onClick={() => {
                    if (balanceIn) {
                      const val = formatUnits(balanceIn, tokenIn.decimals);
                      setAmountIn(val);
                      setAmountOut(val);
                    }
                  }} className="text-sky-400 hover:text-sky-300 font-bold tracking-wide">MAX</button>
                </div>
              </div>
            </div>

            {/* Swap Button (Middle) */}
            <div className="relative h-1">
              <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 z-10">
                <button
                  onClick={handleSwapTokens}
                  className="p-2 bg-zinc-900 border-4 border-zinc-950 rounded-xl hover:bg-zinc-800 hover:scale-110 transition-all text-white"
                >
                  <ArrowDown className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Output Section */}
            <div className="bg-zinc-900/50 p-4 rounded-2xl border border-zinc-800/50 hover:border-zinc-700/50 transition-colors">
              <div className="text-sm text-zinc-500 mb-2">You receive</div>
              <div className="flex justify-between items-center gap-4">
                <input
                  type="number"
                  placeholder="0.0"
                  value={amountOut}
                  readOnly
                  className="bg-transparent text-4xl font-light text-white outline-none w-full placeholder:text-zinc-700"
                />
                <TokenSelector value={tokenOut} onChange={setTokenOut} />
              </div>
              <div className="text-xs text-zinc-500 mt-3 flex justify-between">
                <span>~$0.00</span>
                <span>Balance: {displayBalOut}</span>
              </div>
            </div>
          </div>

          <div className="p-2 mt-2">
            <button 
              onClick={executeAction}
              disabled={isButtonDisabled && !!account}
              className="w-full py-4 bg-sky-500 hover:bg-sky-400 disabled:opacity-50 disabled:hover:bg-sky-500 text-white font-semibold rounded-2xl transition-colors shadow-[0_0_20px_rgba(14,165,233,0.3)] hover:shadow-[0_0_25px_rgba(14,165,233,0.5)]"
            >
              {buttonText}
            </button>
          </div>
        </Card>
      </div>

      <div className="p-4 bg-sky-500/5 border border-sky-500/20 rounded-2xl flex items-start gap-3">
        <Sparkles className="w-5 h-5 text-sky-400 mt-0.5" />
        <div className="text-sm text-sky-200/70">
          <strong className="text-sky-300 font-medium block mb-1">AI Recurring Swap (Coming Soon)</strong>
          Set up automated, dollar-cost average swaps executing at optimal gas times using Arc AI.
        </div>
      </div>
    </div>
    </>
  );
}
