#!/usr/bin/env bash
# upgrade-seismic-ai.sh
# 1. Enable Gemini googleSearch grounding so the agent answers from live web,
#    not just baked-in facts. Same API key.
# 2. Remove "Try these" and "Phase 6 roadmap" side panels; chat goes full width.
#
# Run from ~/code/ai-pay-seismic/apps/web/
set -euo pipefail

if [ ! -f "package.json" ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from apps/web/"; exit 1
fi

echo "→ Backing up files…"
cp app/api/chat/route.ts "app/api/chat/route.ts.bak.$(date +%s)"
cp "app/(app)/trading/page.tsx" "app/(app)/trading/page.tsx.bak.$(date +%s)"

# ───────────────────────────────────────────────
# 1. Chat route: add googleSearch grounding
# ───────────────────────────────────────────────
# NOTE: Gemini does NOT allow function-calling tools and googleSearch in the
# SAME request. So we run a two-pass approach:
#   Pass A: with function tools (deposit/send/balance). If the model calls a
#           function, we return that (action path).
#   Pass B: if no function call, re-run WITH googleSearch grounding for a
#           rich, web-backed answer.
echo "→ 1/2 Rewriting chat route with web-search grounding…"

cat > app/api/chat/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenAI, Type } from '@google/genai';

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const actionTools = [
  {
    functionDeclarations: [
      {
        name: 'get_balance',
        description:
          "Get the user's own shielded balance. Use whenever they ask about their balance, how much they have, etc.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'send_payment',
        description: 'Propose a shielded transfer. User confirms before execution.',
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
        description: "Get the user's portfolio: shielded balance + transaction counts.",
        parameters: { type: Type.OBJECT, properties: {} },
      },
    ],
  },
];

const baseFacts = `Background facts about Seismic (use these, and supplement with live web search):
- Seismic is an encrypted blockchain platform using secure hardware (TEE) for encrypted global state, memory, and data flow.
- It introduces shielded Solidity types: suint256, saddress, sbool — storage with these is encrypted on-chain (a normal uint256 is public; a suint256 is private).
- Mission: combine the privacy of traditional finance with the openness of public blockchains.
- Founded by Lyron Co Ting Keh.
- Raised $17M total: $7M seed (Mar 2025) + $10M Series A (Nov 2025) led by a16z crypto, with Polychain, Amber Group, TrueBridge Capital, dao5, LayerZero Labs.
- Use cases: private payments, exchanges, lending, sealed-bid auctions, stablecoins, launchpads.
- "AI Pay Seismic" (this app) is a shielded-payments demo: deposit ETH into a vault (balance stored as suint256), send shielded transfers.`;

const actionSystem = `You are Seismic AI, the assistant in the "AI Pay Seismic" shielded-payments app.
If the user wants to MOVE MONEY, call the matching tool:
- balance question → get_balance
- "deposit X" → deposit
- "send X to 0x…" → send_payment
- activity/history → get_history
- portfolio → get_portfolio
You never see real balances/amounts (encrypted) — always use tools, never invent numbers/hashes/addresses.
If the user is NOT asking to move money (e.g. a question about Seismic, crypto, or anything informational), do NOT call any tool — just respond with an empty message and we'll handle the answer separately.`;

const answerSystem = `You are Seismic AI, a friendly, knowledgeable assistant inside the "AI Pay Seismic" app.
Answer the user's question about Seismic, crypto, or whatever they ask. Use live web search to get current, accurate info (mainnet timing, token launches, recent news, prices). ${baseFacts}
Be clear and conversational — a short paragraph or a few bullets. If something is genuinely unknown or unannounced, say so honestly rather than inventing it. Cite what you find naturally (e.g. "according to recent reports…").`;

export async function POST(req: NextRequest) {
  try {
    const { messages } = await req.json();
    const contents = messages.map((m: { role: string; content: string }) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

    // ── PASS A: action detection (function tools, no search) ──
    const actionResp = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents,
      config: { tools: actionTools, systemInstruction: actionSystem },
    });

    const fcs = (actionResp.functionCalls || []).map((fc) => ({
      name: fc.name,
      args: fc.args,
    }));

    // If the model decided to call an action tool, return that (action path).
    if (fcs.length > 0) {
      return NextResponse.json({ text: actionResp.text || '', functionCalls: fcs });
    }

    // ── PASS B: informational answer with live web search grounding ──
    const answerResp = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents,
      config: {
        tools: [{ googleSearch: {} }],
        systemInstruction: answerSystem,
      },
    });

    return NextResponse.json({
      text: answerResp.text || "I'm not sure how to help with that—try rephrasing.",
      functionCalls: [],
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'unknown error';
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
TS
echo "  ✓ chat route now uses web search for answers"

# ───────────────────────────────────────────────
# 2. Trading page: remove side panels, full-width chat
# ───────────────────────────────────────────────
echo "→ 2/2 Removing 'Try these' + 'Phase 6 roadmap' panels…"

python3 - <<'PYEOF'
import re
p = 'app/(app)/trading/page.tsx'
with open(p) as f: c = f.read()
orig = c

# The layout is a grid: lg:grid-cols-3, chat in col-span-2, side panels in last col.
# We replace the entire grid block with a single full-width ChatPanel.

# Find the grid container start and replace through its close.
# Strategy: replace the chat grid wrapper with a simpler full-width version.

# 1. Change grid to single column, chat full width
c = re.sub(
    r'<div className="grid grid-cols-1 lg:grid-cols-3 gap-6">',
    '<div className="max-w-3xl">',
    c
)

# 2. Remove col-span-2 wrapper class (keep the motion.div + ChatPanel, just full width)
c = c.replace('className="lg:col-span-2"', 'className=""')

# 3. Remove the second motion.div (the side panel column) entirely.
# It starts at the motion.div with x:16 delay:0.15 and goes to its matching close
# before the closing </div> of the grid. We surgically cut from that motion.div
# to the end-of-file structure, then re-add the proper closing tags.

# Find the start of the side-panel motion.div
side_start = c.find('<motion.div\n          initial={{ opacity: 0, x: 16 }}')
if side_start == -1:
    # try a looser match
    m = re.search(r'<motion\.div[^>]*initial=\{\{\s*opacity:\s*0,\s*x:\s*16\s*\}\}', c)
    side_start = m.start() if m else -1

if side_start != -1:
    # Everything from side_start onward is the side panel + closing tags.
    # We replace it with the correct closing tags for our simplified structure.
    head = c[:side_start].rstrip()
    # Ensure we close the chat motion.div, the wrapper div, and the fragment.
    c = head + '\n      </div>\n    </>\n  );\n}\n'
    print("  ✓ side panels removed, chat is full-width")
else:
    print("  ⚠ couldn't locate side panel block — leaving as is")

if c != orig:
    with open(p,'w') as f: f.write(c)
PYEOF

echo ""
echo "→ Clearing Next.js cache…"
rm -rf .next
echo "  ✓ cleared"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DONE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Restart dev server:"
echo "    Ctrl+C in npm run dev, then 'npm run dev'"
echo "  Hard-refresh: Ctrl+Shift+R"
echo ""
echo "  Changes:"
echo "    • Agent now web-searches for live answers (mainnet date,"
echo "      token launch, current news) — not just baked-in facts."
echo "    • 'Try these' and 'Phase 6 roadmap' panels removed."
echo "    • Chat panel is now full width."
echo ""
echo "  Still one Gemini key. Web search is built into Gemini —"
echo "  no extra keys, no Gemma needed."
echo ""
echo "  Note: each question now makes up to 2 Gemini calls (action"
echo "  check, then web-grounded answer), so answers may take a beat"
echo "  longer. If you hit 503 'overloaded', that's the free-tier"
echo "  rate limit — wait a moment and retry."
