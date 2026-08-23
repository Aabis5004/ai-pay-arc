#!/usr/bin/env bash
# apply-phase-3.sh
# Writes all Phase 3 frontend files for AI Pay Seismic into apps/web/.
# Run this from inside ~/code/ai-pay-seismic/apps/web/
#
# Usage:
#   cd ~/code/ai-pay-seismic/apps/web
#   bash apply-phase-3.sh
#
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: this script must be run from apps/web/ (where Next.js package.json lives)."
  echo "Try:  cd ~/code/ai-pay-seismic/apps/web && bash apply-phase-3.sh"
  exit 1
fi

echo "→ Creating directories…"
mkdir -p components lib app/dashboard app/api/chat abi

# ----------------------------------------------------------------------------
# Extract the SeismicPay ABI from the Foundry build (in case it's missing)
# ----------------------------------------------------------------------------
if [ ! -f "abi/SeismicPay.ts" ]; then
  echo "→ Extracting SeismicPay ABI from contracts/out/…"
  if [ -f "../../contracts/out/SeismicPay.sol/SeismicPay.json" ]; then
    node -e "const j=require('../../contracts/out/SeismicPay.sol/SeismicPay.json'); require('fs').writeFileSync('abi/SeismicPay.ts', 'export const seismicPayAbi = ' + JSON.stringify(j.abi) + ' as const;');"
    echo "  ✓ abi/SeismicPay.ts"
  else
    echo "  ⚠ contracts/out/SeismicPay.sol/SeismicPay.json not found — run 'sforge build' in contracts/ first."
  fi
fi

# ----------------------------------------------------------------------------
# lib/contract.ts
# ----------------------------------------------------------------------------
echo "→ Writing lib/contract.ts"
cat > lib/contract.ts << '___FILE_CONTRACT_TS___'
import { seismicPayAbi } from '@/abi/SeismicPay';
import { sanvil } from 'seismic-viem';

export const SEISMIC_PAY_ADDRESS = process.env
  .NEXT_PUBLIC_SEISMIC_PAY_ADDRESS as `0x${string}`;

export const CHAIN = sanvil;

export const seismicPay = {
  address: SEISMIC_PAY_ADDRESS,
  abi: seismicPayAbi,
} as const;
___FILE_CONTRACT_TS___

# ----------------------------------------------------------------------------
# lib/wagmi.ts
# ----------------------------------------------------------------------------
echo "→ Writing lib/wagmi.ts"
cat > lib/wagmi.ts << '___FILE_WAGMI_TS___'
import { http } from 'viem';
import { sanvil } from 'seismic-viem';
import { createConfig } from '@privy-io/wagmi';

export const wagmiConfig = createConfig({
  chains: [sanvil],
  transports: {
    [sanvil.id]: http(
      process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545',
    ),
  },
});
___FILE_WAGMI_TS___

# ----------------------------------------------------------------------------
# lib/tools.ts — client-side tool executors
# ----------------------------------------------------------------------------
echo "→ Writing lib/tools.ts"
cat > lib/tools.ts << '___FILE_TOOLS_TS___'
import { getShieldedContract } from 'seismic-viem';
import { parseEther, formatEther, type Address } from 'viem';
import { seismicPay } from './contract';

export type ToolCall = { name: string; args: Record<string, unknown> };
export type ToolResult =
  | { ok: true; data: string }
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
    return { ok: false, error: 'Wallet not connected to Seismic network' };
  }

  const contract = getShieldedContract({ ...seismicPay, client: walletClient });

  try {
    switch (tc.name) {
      case 'get_balance': {
        const bal = (await contract.read.balanceOf([
          account.address as Address,
        ])) as bigint;
        return { ok: true, data: `${formatEther(bal)} ETH` };
      }
      case 'deposit': {
        const amount = parseEther(String(tc.args.amount));
        const hash = await contract.write.deposit({ value: amount });
        return { ok: true, data: `Deposit sent. Tx: ${hash}` };
      }
      case 'send_payment': {
        const amount = parseEther(String(tc.args.amount));
        const to = String(tc.args.to) as Address;
        const hash = await contract.write.transfer([to, amount]);
        const short = `${to.slice(0, 6)}…${to.slice(-4)}`;
        return {
          ok: true,
          data: `Sent ${tc.args.amount} ETH to ${short}. Tx: ${hash}`,
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
___FILE_TOOLS_TS___

# ----------------------------------------------------------------------------
# components/NetworkGate.tsx
# ----------------------------------------------------------------------------
echo "→ Writing components/NetworkGate.tsx"
cat > components/NetworkGate.tsx << '___FILE_NETWORKGATE_TSX___'
'use client';

import { motion } from 'framer-motion';
import { useChainId, useSwitchChain } from 'wagmi';
import { sanvil } from 'seismic-viem';

export function NetworkGate({ children }: { children: React.ReactNode }) {
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  if (chainId === sanvil.id) return <>{children}</>;

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-amber-950/30 border border-amber-900/50 rounded-2xl p-6 mb-6"
    >
      <div className="text-sm font-medium text-amber-200 mb-1">
        Wrong network
      </div>
      <div className="text-xs text-amber-300/70 mb-4">
        Your wallet is on chain {chainId || 'unknown'}. AI Pay Seismic runs on
        Seismic Local (31337).
      </div>
      <button
        onClick={() => switchChain({ chainId: sanvil.id })}
        disabled={isPending}
        className="px-4 py-2 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 rounded-lg text-sm font-medium transition-colors"
      >
        {isPending ? 'Switching…' : 'Switch to Seismic Local'}
      </button>
      <div className="text-xs text-amber-300/50 mt-3 leading-relaxed">
        If MetaMask says the network doesn&apos;t exist, add it manually: RPC{' '}
        <code className="bg-black/30 px-1 rounded">http://127.0.0.1:8545</code>,
        Chain ID <code className="bg-black/30 px-1 rounded">31337</code>, Symbol{' '}
        <code className="bg-black/30 px-1 rounded">ETH</code>.
      </div>
    </motion.div>
  );
}
___FILE_NETWORKGATE_TSX___

# ----------------------------------------------------------------------------
# components/BalanceCard.tsx
# ----------------------------------------------------------------------------
echo "→ Writing components/BalanceCard.tsx"
cat > components/BalanceCard.tsx << '___FILE_BALANCECARD_TSX___'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useState, useCallback } from 'react';
import { useShieldedWallet } from 'seismic-react';
import { getShieldedContract } from 'seismic-viem';
import { formatEther } from 'viem';
import { seismicPay } from '@/lib/contract';

export function BalanceCard() {
  const { walletClient, account } = useShieldedWallet();
  const [balance, setBalance] = useState<string>('—');
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!walletClient || !account) {
      setBalance('—');
      return;
    }
    setLoading(true);
    try {
      const contract = getShieldedContract({
        ...seismicPay,
        client: walletClient,
      });
      const bal = (await contract.read.balanceOf([account.address])) as bigint;
      setBalance(formatEther(bal));
    } catch (e) {
      console.error('balance read failed', e);
      setBalance('error');
    } finally {
      setLoading(false);
    }
  }, [walletClient, account]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return (
    <motion.div
      initial={{ opacity: 0, y: -20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
      className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
    >
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs uppercase tracking-widest text-zinc-500">
          Shielded balance
        </span>
        <button
          onClick={refresh}
          className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          {loading ? '…' : 'refresh'}
        </button>
      </div>
      <div className="text-4xl font-light tracking-tight">
        {balance}{' '}
        <span className="text-lg text-zinc-500 font-normal">ETH</span>
      </div>
      <div className="text-xs text-zinc-600 mt-3 font-mono">
        {account?.address
          ? `${account.address.slice(0, 6)}…${account.address.slice(-4)}`
          : 'wallet not connected'}
      </div>
    </motion.div>
  );
}
___FILE_BALANCECARD_TSX___

# ----------------------------------------------------------------------------
# components/ToolConfirmation.tsx
# ----------------------------------------------------------------------------
echo "→ Writing components/ToolConfirmation.tsx"
cat > components/ToolConfirmation.tsx << '___FILE_TOOLCONFIRM_TSX___'
'use client';

import { motion } from 'framer-motion';
import { useEffect, useRef, useState } from 'react';
import { useShieldedWallet } from 'seismic-react';
import { executeTool, type ToolCall, type ToolResult } from '@/lib/tools';

export function ToolConfirmation({
  call,
  onResult,
}: {
  call: ToolCall;
  onResult: (r: ToolResult) => void;
}) {
  const { walletClient, account } = useShieldedWallet();
  const [status, setStatus] = useState<'idle' | 'running' | 'done'>('idle');
  const startedRef = useRef(false);

  const isReadOnly = call.name === 'get_balance';

  const run = async () => {
    if (startedRef.current) return;
    startedRef.current = true;
    setStatus('running');
    const result = await executeTool(call, walletClient, account);
    setStatus('done');
    onResult(result);
  };

  // Auto-run read-only tools as soon as a wallet is available.
  useEffect(() => {
    if (isReadOnly && status === 'idle' && walletClient && account) {
      run();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isReadOnly, walletClient, account]);

  const summary = (() => {
    if (call.name === 'send_payment')
      return `Send ${call.args.amount} ETH to ${String(call.args.to).slice(0, 8)}…`;
    if (call.name === 'deposit')
      return `Deposit ${call.args.amount} ETH to shielded vault`;
    if (call.name === 'get_balance') return 'Reading your shielded balance';
    return call.name;
  })();

  if (isReadOnly) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: 1, y: 0 }}
        className="mt-2 text-xs text-zinc-500 italic"
      >
        → {summary}
        {status === 'running' ? '…' : ''}
      </motion.div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      className="mt-3 p-3 bg-zinc-950/50 border border-violet-900/50 rounded-lg"
    >
      <div className="text-xs uppercase tracking-wider text-violet-400 mb-1">
        Proposed action
      </div>
      <div className="text-sm mb-3">{summary}</div>
      {status === 'idle' && (
        <div className="flex gap-2">
          <button
            onClick={run}
            className="flex-1 px-3 py-2 bg-violet-600 hover:bg-violet-500 rounded-md text-xs font-medium transition-colors"
          >
            Confirm &amp; sign
          </button>
          <button
            onClick={() => onResult({ ok: false, error: 'Cancelled' })}
            className="px-3 py-2 bg-zinc-800 hover:bg-zinc-700 rounded-md text-xs font-medium transition-colors"
          >
            Cancel
          </button>
        </div>
      )}
      {status === 'running' && (
        <div className="text-xs text-zinc-400">Signing &amp; broadcasting…</div>
      )}
    </motion.div>
  );
}
___FILE_TOOLCONFIRM_TSX___

# ----------------------------------------------------------------------------
# components/ChatPanel.tsx
# ----------------------------------------------------------------------------
echo "→ Writing components/ChatPanel.tsx"
cat > components/ChatPanel.tsx << '___FILE_CHATPANEL_TSX___'
'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { useState, useRef, useEffect } from 'react';
import { ToolConfirmation } from './ToolConfirmation';
import type { ToolCall, ToolResult } from '@/lib/tools';

type Msg = {
  role: 'user' | 'assistant';
  content: string;
  toolCall?: ToolCall;
  toolResult?: ToolResult;
};

const EXAMPLES = [
  'What is my balance?',
  'Deposit 1 ETH',
  'Send 0.5 ETH to 0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
];

export function ChatPanel({
  onTxComplete,
}: {
  onTxComplete?: () => void;
}) {
  const [messages, setMessages] = useState<Msg[]>([
    {
      role: 'assistant',
      content:
        'Hi. I can check your balance, deposit, or send shielded payments. Try one of the examples.',
    },
  ]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const send = async (text?: string) => {
    const content = (text ?? input).trim();
    if (!content || busy) return;
    const userMsg: Msg = { role: 'user', content };
    const next = [...messages, userMsg];
    setMessages(next);
    setInput('');
    setBusy(true);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: next }),
      });
      const data = await res.json();

      if (data.error) {
        setMessages((m) => [
          ...m,
          { role: 'assistant', content: `Error: ${data.error}` },
        ]);
      } else if (data.functionCalls?.length > 0) {
        const fc = data.functionCalls[0] as ToolCall;
        setMessages((m) => [
          ...m,
          {
            role: 'assistant',
            content:
              data.text ||
              `Let me ${fc.name.replace('_', ' ')}.`,
            toolCall: fc,
          },
        ]);
      } else {
        setMessages((m) => [
          ...m,
          { role: 'assistant', content: data.text || '(no response)' },
        ]);
      }
    } catch (e) {
      setMessages((m) => [
        ...m,
        { role: 'assistant', content: `Network error: ${e}` },
      ]);
    } finally {
      setBusy(false);
    }
  };

  const handleToolResult = (idx: number, result: ToolResult) => {
    setMessages((m) =>
      m.map((msg, i) => (i === idx ? { ...msg, toolResult: result } : msg)),
    );
    if (result.ok && onTxComplete) onTxComplete();
  };

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.97 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.6, delay: 0.1, ease: [0.16, 1, 0.3, 1] }}
      className="bg-zinc-900/60 border border-zinc-800 rounded-2xl overflow-hidden backdrop-blur flex flex-col h-[560px]"
    >
      <div className="px-5 py-3 border-b border-zinc-800 text-xs uppercase tracking-widest text-zinc-500 flex items-center justify-between">
        <span>Chat</span>
        {busy && (
          <span className="text-violet-400 normal-case tracking-normal">
            thinking…
          </span>
        )}
      </div>

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3">
        <AnimatePresence initial={false}>
          {messages.map((m, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.25 }}
              className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-[85%] px-4 py-2.5 rounded-2xl text-sm ${
                  m.role === 'user'
                    ? 'bg-violet-600 text-white rounded-br-md'
                    : 'bg-zinc-800 text-zinc-100 rounded-bl-md'
                }`}
              >
                <div>{m.content}</div>
                {m.toolCall && !m.toolResult && (
                  <ToolConfirmation
                    call={m.toolCall}
                    onResult={(r) => handleToolResult(i, r)}
                  />
                )}
                {m.toolResult && (
                  <div
                    className={`mt-2 pt-2 border-t border-zinc-700/50 text-xs break-all ${
                      m.toolResult.ok ? 'text-emerald-400' : 'text-red-400'
                    }`}
                  >
                    {m.toolResult.ok
                      ? `✓ ${m.toolResult.data}`
                      : `✗ ${m.toolResult.error}`}
                  </div>
                )}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
        <div ref={endRef} />

        {messages.length === 1 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.5 }}
            className="pt-2 space-y-2"
          >
            <div className="text-xs text-zinc-600 uppercase tracking-widest">
              Try
            </div>
            {EXAMPLES.map((ex) => (
              <button
                key={ex}
                onClick={() => send(ex)}
                className="block w-full text-left text-xs px-3 py-2 bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 hover:border-zinc-700 rounded-lg transition-colors text-zinc-400 hover:text-zinc-200"
              >
                {ex}
              </button>
            ))}
          </motion.div>
        )}
      </div>

      <div className="border-t border-zinc-800 p-3 flex gap-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && send()}
          placeholder="Tell the agent what to do…"
          disabled={busy}
          className="flex-1 bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-violet-500 transition-colors"
        />
        <button
          onClick={() => send()}
          disabled={busy || !input.trim()}
          className="px-4 py-2 bg-violet-600 hover:bg-violet-500 disabled:bg-zinc-700 disabled:text-zinc-500 rounded-lg text-sm font-medium transition-colors"
        >
          {busy ? '…' : 'Send'}
        </button>
      </div>
    </motion.div>
  );
}
___FILE_CHATPANEL_TSX___

# ----------------------------------------------------------------------------
# components/QuickActions.tsx
# ----------------------------------------------------------------------------
echo "→ Writing components/QuickActions.tsx"
cat > components/QuickActions.tsx << '___FILE_QUICKACTIONS_TSX___'
'use client';

import { motion } from 'framer-motion';

const actions = [
  { label: 'Deposit', hint: '"Deposit 1 ETH"' },
  { label: 'Send', hint: '"Send 0.1 to 0x..."' },
  { label: 'Balance', hint: '"What is my balance?"' },
];

export function QuickActions() {
  return (
    <motion.div
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.5, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
      className="space-y-2"
    >
      <div className="text-xs uppercase tracking-widest text-zinc-500 mb-3">
        Quick actions
      </div>
      {actions.map((a, i) => (
        <motion.div
          key={a.label}
          initial={{ opacity: 0, x: 10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.3 + i * 0.08 }}
          className="bg-zinc-900/60 border border-zinc-800 rounded-xl p-4 hover:border-zinc-700 transition-colors cursor-default"
        >
          <div className="font-medium text-sm">{a.label}</div>
          <div className="text-xs text-zinc-500 mt-1 font-mono">{a.hint}</div>
        </motion.div>
      ))}
    </motion.div>
  );
}
___FILE_QUICKACTIONS_TSX___

# ----------------------------------------------------------------------------
# components/ActivityFeed.tsx
# ----------------------------------------------------------------------------
echo "→ Writing components/ActivityFeed.tsx"
cat > components/ActivityFeed.tsx << '___FILE_ACTIVITY_TSX___'
'use client';

import { motion } from 'framer-motion';

export function ActivityFeed() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.3, ease: [0.16, 1, 0.3, 1] }}
      className="bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 backdrop-blur"
    >
      <div className="text-xs uppercase tracking-widest text-zinc-500 mb-3">
        Activity
      </div>
      <div className="text-sm text-zinc-600 leading-relaxed">
        Recent transactions will appear here once you start sending payments.
        Privacy note: only the fact that a tx happened is public — amounts stay
        shielded.
      </div>
    </motion.div>
  );
}
___FILE_ACTIVITY_TSX___

# ----------------------------------------------------------------------------
# app/api/chat/route.ts — Gemini endpoint
# ----------------------------------------------------------------------------
echo "→ Writing app/api/chat/route.ts"
cat > app/api/chat/route.ts << '___FILE_CHATROUTE_TS___'
import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenAI, Type } from '@google/genai';

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const tools = [
  {
    functionDeclarations: [
      {
        name: 'get_balance',
        description:
          "Get the user's own shielded SeismicPay balance. Use whenever the user asks about their balance, how much they have, etc.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'send_payment',
        description:
          'Propose a shielded transfer to a recipient address. The user confirms before it executes.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            to: {
              type: Type.STRING,
              description: 'Recipient wallet address (0x-prefixed)',
            },
            amount: {
              type: Type.STRING,
              description: 'Amount in ETH as a decimal string, e.g. "0.1"',
            },
          },
          required: ['to', 'amount'],
        },
      },
      {
        name: 'deposit',
        description:
          "Deposit native ETH from the user's wallet into the shielded SeismicPay vault.",
        parameters: {
          type: Type.OBJECT,
          properties: {
            amount: {
              type: Type.STRING,
              description: 'Amount in ETH as a decimal string',
            },
          },
          required: ['amount'],
        },
      },
    ],
  },
];

const systemInstruction = `You are the assistant for AI Pay Seismic, a privacy-preserving payments app built on the Seismic blockchain.
You help users send shielded payments, check balances, and deposit funds via natural language.

Critical rules:
- You NEVER see the user's actual balance or transaction amounts; they live on-chain encrypted. Only call tools to act on the user's behalf.
- When the user wants to send money, always call send_payment with the parsed amount and address. Do not guess amounts — if unclear, ask.
- Be concise. Two sentences max unless explaining.
- Never invent transaction hashes, addresses, or balances. Only report what tools return.`;

export async function POST(req: NextRequest) {
  try {
    const { messages } = await req.json();

    const contents = messages.map(
      (m: { role: string; content: string }) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      }),
    );

    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents,
      config: { tools, systemInstruction },
    });

    const fnCalls = response.functionCalls || [];
    const text = response.text || '';

    return NextResponse.json({
      text,
      functionCalls: fnCalls.map((fc) => ({ name: fc.name, args: fc.args })),
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'unknown error';
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
___FILE_CHATROUTE_TS___

# ----------------------------------------------------------------------------
# app/providers.tsx
# ----------------------------------------------------------------------------
echo "→ Writing app/providers.tsx"
cat > app/providers.tsx << '___FILE_PROVIDERS_TSX___'
'use client';

import { PrivyProvider } from '@privy-io/react-auth';
import { WagmiProvider } from '@privy-io/wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ShieldedWalletProvider } from 'seismic-react';
import { sanvil } from 'seismic-viem';
import { wagmiConfig } from '@/lib/wagmi';
import { useState } from 'react';

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID || ''}
      config={{
        loginMethods: ['email', 'wallet'],
        appearance: {
          theme: 'dark',
          accentColor: '#7c3aed',
        },
        embeddedWallets: {
          createOnLogin: 'users-without-wallets',
        },
        defaultChain: sanvil,
        supportedChains: [sanvil],
      }}
    >
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>
          <ShieldedWalletProvider
            config={wagmiConfig}
            options={{ publicChain: sanvil }}
          >
            {children}
          </ShieldedWalletProvider>
        </WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
___FILE_PROVIDERS_TSX___

# ----------------------------------------------------------------------------
# app/layout.tsx
# ----------------------------------------------------------------------------
echo "→ Writing app/layout.tsx"
cat > app/layout.tsx << '___FILE_LAYOUT_TSX___'
import type { Metadata } from 'next';
import { Providers } from './providers';
import './globals.css';

export const metadata: Metadata = {
  title: 'AI Pay Seismic',
  description: 'Shielded payments with natural language',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="bg-zinc-950 text-zinc-100 antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
___FILE_LAYOUT_TSX___

# ----------------------------------------------------------------------------
# app/page.tsx — landing / sign-in
# ----------------------------------------------------------------------------
echo "→ Writing app/page.tsx"
cat > app/page.tsx << '___FILE_HOMEPAGE_TSX___'
'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { motion } from 'framer-motion';

export default function Home() {
  const { ready, authenticated, login } = usePrivy();
  const router = useRouter();

  useEffect(() => {
    if (ready && authenticated) router.replace('/dashboard');
  }, [ready, authenticated, router]);

  if (!ready) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <main className="min-h-screen flex items-center justify-center px-4">
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="max-w-md w-full p-8 bg-zinc-900/80 backdrop-blur-sm rounded-2xl border border-zinc-800 shadow-2xl"
      >
        <h1 className="text-3xl font-semibold tracking-tight mb-2">
          AI Pay <span className="text-violet-400">Seismic</span>
        </h1>
        <p className="text-sm text-zinc-400 mb-8">
          Shielded payments. Natural language.
        </p>
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={login}
          className="w-full py-3 px-4 bg-violet-600 hover:bg-violet-500 transition-colors rounded-lg font-medium"
        >
          Sign in with email or wallet
        </motion.button>
      </motion.div>
    </main>
  );
}
___FILE_HOMEPAGE_TSX___

# ----------------------------------------------------------------------------
# app/dashboard/page.tsx
# ----------------------------------------------------------------------------
echo "→ Writing app/dashboard/page.tsx"
cat > app/dashboard/page.tsx << '___FILE_DASHBOARD_TSX___'
'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { BalanceCard } from '@/components/BalanceCard';
import { ChatPanel } from '@/components/ChatPanel';
import { QuickActions } from '@/components/QuickActions';
import { ActivityFeed } from '@/components/ActivityFeed';
import { NetworkGate } from '@/components/NetworkGate';

export default function Dashboard() {
  const { ready, authenticated, logout, user } = usePrivy();
  const router = useRouter();
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (ready && !authenticated) router.replace('/');
  }, [ready, authenticated, router]);

  if (!ready || !authenticated) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <main className="min-h-screen px-6 py-8 max-w-6xl mx-auto">
      <motion.header
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="flex items-center justify-between mb-8"
      >
        <h1 className="text-xl font-semibold tracking-tight">
          AI Pay <span className="text-violet-400">Seismic</span>
        </h1>
        <div className="flex items-center gap-4">
          <div className="text-xs text-zinc-500 font-mono">
            {user?.wallet?.address?.slice(0, 6)}…
            {user?.wallet?.address?.slice(-4)}
          </div>
          <button
            onClick={logout}
            className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
          >
            Sign out
          </button>
        </div>
      </motion.header>

      <NetworkGate>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-6">
            <BalanceCard key={refreshKey} />
            <ChatPanel onTxComplete={() => setRefreshKey((k) => k + 1)} />
          </div>
          <div className="space-y-6">
            <QuickActions />
            <ActivityFeed />
          </div>
        </div>
      </NetworkGate>
    </main>
  );
}
___FILE_DASHBOARD_TSX___

echo ""
echo "✓ All Phase 3 files written."
echo ""
echo "Files written:"
echo "  abi/SeismicPay.ts            (ABI export)"
echo "  lib/contract.ts              (contract address + ABI)"
echo "  lib/wagmi.ts                 (wagmi config)"
echo "  lib/tools.ts                 (client-side tool executors)"
echo "  components/NetworkGate.tsx   (wrong-chain prompt)"
echo "  components/BalanceCard.tsx   (shielded balance display)"
echo "  components/ChatPanel.tsx     (chat UI + tool routing)"
echo "  components/ToolConfirmation.tsx (confirm + sign action)"
echo "  components/QuickActions.tsx  (action hints)"
echo "  components/ActivityFeed.tsx  (recent tx placeholder)"
echo "  app/providers.tsx            (Privy + Wagmi + Seismic providers)"
echo "  app/layout.tsx               (root layout)"
echo "  app/page.tsx                 (sign-in landing)"
echo "  app/dashboard/page.tsx       (post-auth main page)"
echo "  app/api/chat/route.ts        (Gemini endpoint)"
echo ""
echo "Next: stop the dev server (Ctrl+C) and run 'npm run dev' to pick up changes."
