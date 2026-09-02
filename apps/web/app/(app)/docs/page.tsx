
'use client';

import { motion } from 'framer-motion';
import { PageHeader } from '@/components/PageHeader';
import { GlueBillCalculator } from '@/components/demos/GlueBillCalculator';
import { NodeFlowDiagram } from '@/components/demos/NodeFlowDiagram';
import { ComparisonTable } from '@/components/demos/ComparisonTable';
import { Zap, Activity, Layers, Code2, Workflow, ShieldCheck, Cpu, Repeat } from 'lucide-react';

export default function DocsPage() {
  return (
    <>
      <PageHeader
        title="Architecture & Roadmap"
        subtitle="How FlowPay integrates with Rialo to enable fully on-chain recurring payments."
      />

      <div className="max-w-5xl space-y-8 pb-12">
        
        {/* Abstract / Intro */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4 }}
          className="bg-zinc-900/40 border border-zinc-800 rounded-2xl p-6 md:p-8 backdrop-blur"
        >
          <div className="flex items-center gap-2 text-sky-400 mb-4">
            <Zap className="w-5 h-5" />
            <h3 className="font-semibold tracking-wide">The Stack Collapses into the Chain</h3>
          </div>
          <p className="text-zinc-300 leading-relaxed text-sm md:text-base">
            Current blockchain applications rely on a fragile tower of off-chain automation. Blockchains are fundamentally synchronous systems, making tasks like recurring subscriptions difficult without centralized relayers.
            <br/><br/>
            FlowPay is evolving. By integrating with <b>Rialo</b>—the infrastructure for the next generation of intelligent systems—we are bringing <b>native automation</b> directly to our smart contracts. Recurring payments are triggered natively on-chain without the "Glue Bill" of off-chain keeper networks.
          </p>
        </motion.div>

        {/* How it Works: Technical Flow */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.1 }}
        >
          <h3 className="text-xl font-medium text-white mb-4 flex items-center gap-2">
            <Workflow className="w-5 h-5 text-zinc-400" />
            How Recurring Payments Work
          </h3>
          
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Step 1 */}
            <div className="bg-zinc-900/60 border border-zinc-800/80 rounded-2xl p-6 relative overflow-hidden group hover:border-zinc-700 transition-colors">
              <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
                <Activity className="w-16 h-16 text-sky-400" />
              </div>
              <div className="w-8 h-8 rounded-full bg-zinc-800 border border-zinc-700 flex items-center justify-center text-xs font-mono text-zinc-400 mb-4">01</div>
              <h4 className="text-white font-medium mb-2">Vault Deposit</h4>
              <p className="text-zinc-400 text-sm leading-relaxed">
                Users deposit USDC into the FlowPay smart contract Vault once. No continuous manual approvals are needed.
              </p>
            </div>

            {/* Step 2 */}
            <div className="bg-zinc-900/60 border border-zinc-800/80 rounded-2xl p-6 relative overflow-hidden group hover:border-zinc-700 transition-colors">
              <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
                <Layers className="w-16 h-16 text-sky-400" />
              </div>
              <div className="w-8 h-8 rounded-full bg-zinc-800 border border-zinc-700 flex items-center justify-center text-xs font-mono text-zinc-400 mb-4">02</div>
              <h4 className="text-white font-medium mb-2">Reactive Registration</h4>
              <p className="text-zinc-400 text-sm leading-relaxed">
                The user signs a single intent parameterizing the subscription (e.g., 10 USDC/month). This state is registered on the Rialo Network.
              </p>
            </div>

            {/* Step 3 */}
            <div className="bg-zinc-900/60 border border-zinc-800/80 rounded-2xl p-6 relative overflow-hidden group hover:border-zinc-700 transition-colors">
              <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
                <Repeat className="w-16 h-16 text-sky-400" />
              </div>
              <div className="w-8 h-8 rounded-full bg-zinc-800 border border-zinc-700 flex items-center justify-center text-xs font-mono text-zinc-400 mb-4">03</div>
              <h4 className="text-white font-medium mb-2">Native Execution</h4>
              <p className="text-zinc-400 text-sm leading-relaxed">
                Rialo's Reactive Transactions natively trigger the FlowPay smart contract at the exact interval, streaming funds to the merchant securely via Gauss SMR.
              </p>
            </div>
          </div>
        </motion.div>

        {/* Code / Architecture Snippet */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.2 }}
          className="bg-[#0D0D12] border border-zinc-800/80 rounded-2xl overflow-hidden"
        >
          <div className="flex items-center gap-2 px-4 py-3 border-b border-zinc-800/80 bg-zinc-900/50">
            <Code2 className="w-4 h-4 text-zinc-500" />
            <span className="text-xs font-mono text-zinc-400">FlowPay_Reactive.sol</span>
          </div>
          <div className="p-4 md:p-6 overflow-x-auto text-sm font-mono text-zinc-300 leading-relaxed">
            <pre><code>
              <span className="text-sky-400">contract</span> FlowPay <span className="text-sky-400">is</span> IReactiveExecutable {'{'}<br/>
              {'  '}mapping(bytes32 =&gt; Subscription) <span className="text-sky-400">public</span> subscriptions;<br/><br/>
              {'  '}<span className="text-zinc-500">// Triggered natively by Rialo state machine</span><br/>
              {'  '}<span className="text-sky-400">function</span> executeReactive(<span className="text-emerald-400">bytes32</span> subId) <span className="text-sky-400">external</span> {'{'}<br/>
              {'    '}<span className="text-sky-400">require</span>(msg.sender == RIALO_SMR_ADDRESS, <span className="text-amber-300">&quot;Unauthorized&quot;</span>);<br/><br/>
              {'    '}Subscription memory sub = subscriptions[subId];<br/>
              {'    '}<span className="text-sky-400">require</span>(block.timestamp &gt;= sub.nextPayment, <span className="text-amber-300">&quot;Too early&quot;</span>);<br/><br/>
              {'    '}<span className="text-zinc-500">// Internal ledger update (No gas cost to user)</span><br/>
              {'    '}vaultBalance[sub.user] -= sub.amount;<br/>
              {'    '}vaultBalance[sub.merchant] += sub.amount;<br/><br/>
              {'    '}sub.nextPayment += sub.interval;<br/>
              {'    '}subscriptions[subId] = sub;<br/>
              {'  }'}<br/>
              {'}'}
            </code></pre>
          </div>
        </motion.div>


        {/* Interactive Demos */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.4 }}
          className="mt-16 pt-12 border-t border-zinc-800"
        >
          <div className="mb-8">
            <h3 className="text-2xl font-bold text-white mb-2">Interactive Architecture Demos</h3>
            <p className="text-zinc-400">Play with these interactive models to understand the cost and performance benefits of collapsing the stack into the chain.</p>
          </div>
          
          <GlueBillCalculator />
          <NodeFlowDiagram />
          <ComparisonTable />
        </motion.div>

        {/* AI Integration */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.3 }}
          className="grid grid-cols-1 md:grid-cols-2 gap-4"
        >
          <div className="bg-zinc-900/40 border border-zinc-800 rounded-2xl p-6 backdrop-blur flex flex-col justify-center">
            <Cpu className="w-8 h-8 text-indigo-400 mb-4" />
            <h4 className="text-lg font-medium text-white mb-2">Flow AI Co-Pilot</h4>
            <p className="text-sm text-zinc-400 leading-relaxed">
              With recurring payments handled on-chain by Rialo, Flow AI steps in as your intelligent manager. It monitors your vault liquidity, alerts you if an upcoming payment will bounce, and can automatically schedule swaps to ensure your subscriptions stay funded.
            </p>
          </div>
          
          <div className="bg-zinc-900/40 border border-zinc-800 rounded-2xl p-6 backdrop-blur flex flex-col justify-center">
            <ShieldCheck className="w-8 h-8 text-emerald-400 mb-4" />
            <h4 className="text-lg font-medium text-white mb-2">Supermodular Security</h4>
            <p className="text-sm text-zinc-400 leading-relaxed">
              By utilizing Supermodularity, FlowPay determines exactly what is necessary to integrate into the blockchain environment. We collapse the off-chain stack into the chain, drastically reducing counterparty risk and failure points.
            </p>
          </div>
        </motion.div>
        
      </div>
    </>
  );
}
