import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenAI, Type } from '@google/genai';
import { arcDocsContext } from '../../../lib/arc-data';

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! });

const actionTools = [
  {
    functionDeclarations: [
      {
        name: 'get_balance',
        description:
          "Get the user's balance on the Arc Testnet. Use whenever they ask about their balance, how much they have, etc.",
      },
      {
        name: 'send_payment',
        description: 'Propose a transfer on Arc. User confirms before execution.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            to: { type: Type.STRING, description: 'Recipient 0x-address or 16-digit card number' },
            amount: { type: Type.STRING, description: 'Amount in USDC as a decimal string' },
          },
          required: ['to', 'amount'],
        },
      },
      {
        name: 'deposit',
        description: 'Deposit native USDC into the FlowPay vault.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            amount: { type: Type.STRING, description: 'Amount in USDC as a decimal string' },
          },
          required: ['amount'],
        },
      },
      {
        name: 'get_history',
        description:
          "Get the user's recent on-chain activity (deposits, sends, receives). Returns count + summary.",
      },
      {
        name: 'get_portfolio',
        description: "Get the user's portfolio: balance + transaction counts.",
      },
    ],
  },
];

const actionSystem = `You are Flow AI, the assistant in the "FlowPay" payments app.
If the user wants to MOVE MONEY, call the matching tool:
- balance question → get_balance
- "deposit X" → deposit
- "withdraw X" → withdraw
- "send X to 0x…" or "send X to 4242 4242…" → send_payment
- activity/history → get_history
- portfolio → get_portfolio
Always use tools to process their requests, never invent numbers/hashes/addresses.
If the user is NOT asking to move money (e.g. a question about Arc, crypto, or anything informational), do NOT call any tool — just respond with an empty message and we'll handle the answer separately.`;

const answerSystem = `You are Flow AI, a friendly, knowledgeable assistant inside the "FlowPay" app.
Answer the user's question about Arc, programmable money, crypto, or whatever they ask. Use live web search to get current, accurate info (mainnet timing, token launches, recent news, prices). 

Here is the deep context about Arc that you MUST use to answer questions:
${arcDocsContext}

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
      config: { tools: actionTools as any, systemInstruction: actionSystem },
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
