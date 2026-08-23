'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { useState, useRef, useEffect } from 'react';
import { ToolConfirmation } from './ToolConfirmation';
import type { ToolCall, ToolResult } from '@/lib/tools';
import { Sparkles } from 'lucide-react';

type Msg = {
  role: 'user' | 'assistant';
  content: string;
  toolCall?: ToolCall;
  toolResult?: ToolResult;
};

const EXAMPLES = [
  'What is my balance?',
  'Deposit 100 USDC',
  'Send 50 USDC to 0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
];

export function ChatPanel({
  onTxComplete,
  embedded = true,
}: {
  onTxComplete?: () => void;
  embedded?: boolean;
}) {
  const [messages, setMessages] = useState<Msg[]>([
    {
      role: 'assistant',
      content:
        'I can check your balance, deposit, or send shielded payments. Try one of the examples or type your own.',
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
    const next: Msg[] = [...messages, { role: 'user', content }];
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
            content: data.text || `Let me ${fc.name.replace('_', ' ')}.`,
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
    <div
      className={`bg-zinc-900/60 border border-zinc-800 rounded-2xl overflow-hidden backdrop-blur flex flex-col ${embedded ? 'h-[560px]' : 'h-full'}`}
    >
      <div className="px-5 py-3 border-b border-zinc-800 flex items-center justify-between">
        <div className="flex items-center gap-2 text-xs uppercase tracking-[0.2em] text-zinc-500">
          <Sparkles className="w-3.5 h-3.5 text-violet-400" />
          AI agent
        </div>
        {busy && (
          <span className="text-xs text-violet-400 flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-pulse" />
            thinking
          </span>
        )}
      </div>

      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3">
        <AnimatePresence initial={false}>
          {messages.map((m, i) => (
            <motion.div
              key={`m-${i}`}
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
            transition={{ delay: 0.4 }}
            className="pt-2 space-y-2"
          >
            <div className="text-[10px] text-zinc-600 uppercase tracking-[0.2em]">
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
    </div>
  );
}
