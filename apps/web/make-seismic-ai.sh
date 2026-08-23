#!/usr/bin/env bash
# make-seismic-ai.sh
# Converts the "Trade" page into "Seismic AI" — a hybrid agent that:
#   • Answers questions about Seismic (what it is, how it works, funding, tech)
#   • Still does deposit / send / balance / history when asked
# Uses the SAME Gemini API key. No new key needed. Knowledge is in the system prompt.
#
# Changes:
#   1. app/api/chat/route.ts  — rewrite systemInstruction with real Seismic facts
#   2. components/Sidebar.tsx  — rename "Trade" → "Seismic AI"
#   3. app/(app)/trading/page.tsx — new heading, note, example prompts
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

echo "→ Backing up files…"
cp app/api/chat/route.ts "app/api/chat/route.ts.bak.$(date +%s)"
cp components/Sidebar.tsx "components/Sidebar.tsx.bak.$(date +%s)"
cp "app/(app)/trading/page.tsx" "app/(app)/trading/page.tsx.bak.$(date +%s)"

# ───────────────────────────────────────────────
# 1. Rewrite chat route system prompt (keep tools identical)
# ───────────────────────────────────────────────
echo "→ 1/3 Rewriting chat route with Seismic knowledge…"

cat > app/api/chat/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenAI, Type } from '@google/genai';

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const tools = [
  {
    functionDeclarations: [
      {
        name: 'get_balance',
        description:
          "Get the user's own shielded balance. Use whenever they ask about balance, how much they have, etc.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'send_payment',
        description:
          'Propose a shielded transfer. User confirms before execution.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            to: { type: Type.STRING, description: 'Recipient 0x-address' },
            amount: { type: Type.STRING, description: 'Amount in ETH as a decimal string' },
          },
          required: ['to', 'amount'],
        },
      },
      {
        name: 'deposit',
        description: 'Deposit native ETH into the shielded vault.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            amount: { type: Type.STRING, description: 'Amount in ETH as a decimal string' },
          },
          required: ['amount'],
        },
      },
      {
        name: 'get_history',
        description:
          "Get the user's recent on-chain activity (deposits, sends, receives). Returns count + summary.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'get_portfolio',
        description:
          "Get the user's portfolio: shielded balance + transaction counts.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
    ],
  },
];

const systemInstruction = `You are Seismic AI — the assistant inside the "AI Pay Seismic" app, a shielded payments app built on the Seismic blockchain.

You have TWO jobs:

═══════════════════════════════════
JOB 1 — ANSWER QUESTIONS ABOUT SEISMIC
═══════════════════════════════════
When the user asks what Seismic is, how it works, who built it, how much it raised, or anything informational, answer from the facts below. Be clear and friendly. Use a short paragraph or a few bullet points.

WHAT SEISMIC IS:
- Seismic is an encrypted blockchain platform. It integrates secure hardware (a Trusted Execution Environment / TEE) to provide an encrypted global state, encrypted memory access, and encrypted data flow.
- Its mission: combine the privacy of traditional finance with the openness of public blockchains. Public chains expose every transaction; Seismic lets apps keep sensitive financial data (balances, amounts, salaries, loan data) confidential while still being on-chain.
- It introduces "shielded types" in Solidity — e.g. suint256 (a shielded/encrypted uint256), saddress, sbool. Contract storage using these types is encrypted on-chain. A normal uint256 is public; a suint256 is private. This is the core developer-facing innovation.
- Use cases it targets: private payments, exchanges, lending platforms, sealed-bid auctions, stablecoins, launchpads — anything needing confidentiality.

WHO BUILT IT / FUNDING:
- Founded by Lyron Co Ting Keh.
- Has raised $17 million total across 2 rounds: a $7M seed (March 2025) and a $10M Series A (November 2025).
- The $10M round was led by a16z crypto, with participation from Polychain, Amber Group, TrueBridge Capital, dao5, and LayerZero Labs.
- The funding goes toward building out its encrypted blockchain rails for fintechs, with revenue plans starting around 2026.

HOW THIS APP RELATES:
- "AI Pay Seismic" is a demo app showing shielded payments. You deposit ETH into a shielded vault (balance stored as suint256, so it's encrypted on-chain), then send shielded transfers to other addresses.
- The app runs on a local Seismic dev chain (sanvil) during development, and can connect to the public Seismic testnet for live use.

If asked something about Seismic you genuinely don't know (e.g. exact token launch date, current price), say you're not certain rather than inventing it.

═══════════════════════════════════
JOB 2 — DO ACTIONS WHEN ASKED
═══════════════════════════════════
When the user wants to move money, call the matching tool:
- balance question → get_balance
- "deposit X" → deposit
- "send X to 0x…" → send_payment (user confirms before signing)
- activity/history → get_history
- portfolio → get_portfolio

ACTION RULES:
- You never see actual balances or amounts — they're encrypted. Always use the tools; never invent numbers, hashes, or addresses.
- For send/deposit, always call the tool. The user confirms in their wallet before anything executes.
- Keep action replies concise.

═══════════════════════════════════
STYLE
═══════════════════════════════════
- Friendly, clear, never robotic.
- Informational answers: a short paragraph or a few bullets is fine.
- Action confirmations: one or two sentences.
- If a message mixes both ("what is Seismic and check my balance"), answer the question AND call the tool.`;

export async function POST(req: NextRequest) {
  try {
    const { messages } = await req.json();
    const contents = messages.map((m: { role: string; content: string }) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents,
      config: { tools, systemInstruction },
    });

    return NextResponse.json({
      text: response.text || '',
      functionCalls: (response.functionCalls || []).map((fc) => ({
        name: fc.name,
        args: fc.args,
      })),
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'unknown error';
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
TS
echo "  ✓ chat route updated with Seismic knowledge"

# ───────────────────────────────────────────────
# 2. Rename sidebar nav label
# ───────────────────────────────────────────────
echo "→ 2/3 Renaming sidebar 'Trade' → 'Seismic AI'…"
sed -i "s|{ href: '/trading', label: 'Trade', icon: ArrowLeftRight }|{ href: '/trading', label: 'Seismic AI', icon: Sparkles }|" components/Sidebar.tsx

# Make sure Sparkles is imported in Sidebar
if ! grep -q "Sparkles" components/Sidebar.tsx; then
  # add Sparkles to the lucide-react import
  sed -i "s|from 'lucide-react'|, Sparkles } from 'lucide-react'|" components/Sidebar.tsx 2>/dev/null || true
  # The above is fragile; do a safer python edit
fi

python3 - <<'PYEOF'
import re
p = 'components/Sidebar.tsx'
with open(p) as f: c = f.read()
# Ensure Sparkles imported from lucide-react
m = re.search(r"import\s*\{([^}]*)\}\s*from\s*'lucide-react';", c)
if m and 'Sparkles' not in m.group(1):
    new_imports = m.group(1).rstrip().rstrip(',') + ', Sparkles'
    c = c[:m.start(1)] + new_imports + c[m.end(1):]
    with open(p,'w') as f: f.write(c)
    print("  ✓ Sparkles icon imported in Sidebar")
else:
    print("  · Sidebar import already fine")
PYEOF
echo "  ✓ sidebar renamed"

# ───────────────────────────────────────────────
# 3. Update trading page header + examples
# ───────────────────────────────────────────────
echo "→ 3/3 Updating page header + example prompts…"

python3 - <<'PYEOF'
p = 'app/(app)/trading/page.tsx'
with open(p) as f: c = f.read()
orig = c

# Title + subtitle
c = c.replace(
    'title="Trade"\n        subtitle="AI-driven shielded transfers. Talk to the agent — it executes on-chain."',
    'title="Seismic AI"\n        subtitle="Ask about Seismic, or tell the agent to deposit, send, and check balances."'
)

# Replace the "Honest note" block with a friendlier intro about the hybrid agent
import re
c = re.sub(
    r'<Info className="w-4 h-4 text-violet-400 mt-0\.5 shrink-0" />\s*<div className="text-xs text-zinc-300 leading-relaxed">.*?</div>',
    '''<Info className="w-4 h-4 text-violet-400 mt-0.5 shrink-0" />
        <div className="text-xs text-zinc-300 leading-relaxed">
          <strong className="text-zinc-100">Seismic AI</strong> can answer questions
          about Seismic — what it is, how shielded types work, who built it, how much
          it raised — and it can also act: deposit ETH, send shielded transfers, and
          check your balance. Just ask in plain English.
        </div>''',
    c,
    flags=re.DOTALL
)

# Update the "Try these" examples to show both Q&A and actions
c = c.replace(
    '''<div className="font-mono text-violet-300">&quot;Send 0.5 to 0x70997…&quot;</div>
              <div className="font-mono text-violet-300">&quot;Deposit 2&quot;</div>
              <div className="font-mono text-violet-300">&quot;Check my balance&quot;</div>''',
    '''<div className="font-mono text-violet-300">&quot;What is Seismic?&quot;</div>
              <div className="font-mono text-violet-300">&quot;How much did Seismic raise?&quot;</div>
              <div className="font-mono text-violet-300">&quot;How do shielded types work?&quot;</div>
              <div className="font-mono text-violet-300">&quot;Deposit 2 ETH&quot;</div>
              <div className="font-mono text-violet-300">&quot;Send 0.5 to 0x70997…&quot;</div>
              <div className="font-mono text-violet-300">&quot;Check my balance&quot;</div>'''
)

if c != orig:
    with open(p,'w') as f: f.write(c)
    print("  ✓ page header + examples updated")
else:
    print("  ⚠ no changes matched in trading page — check manually")
PYEOF

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE — Trade is now 'Seismic AI'"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Restart dev server:"
echo "    Ctrl+C in npm run dev, then 'npm run dev'"
echo "  Hard-refresh: Ctrl+Shift+R"
echo ""
echo "  The sidebar now says 'Seismic AI'. The agent can:"
echo "    • Answer: 'What is Seismic?', 'How much did it raise?',"
echo "      'How do shielded types work?', 'Who built Seismic?'"
echo "    • Act: 'Deposit 2 ETH', 'Send 0.5 to 0x…', 'Check my balance'"
echo ""
echo "  Same Gemini key — no new API key needed."
echo ""
echo "  NOTE: if the AI ever says it's overloaded (503), that's"
echo "  Google rate-limiting the free Gemini tier. Wait a minute."
echo "  If it happens a lot, you can get a fresh free key at"
echo "  https://aistudio.google.com/apikey and put it in .env.local"
echo "  as GEMINI_API_KEY=…"
