'use client';

import { motion } from 'framer-motion';
import { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { useShielded } from '@/lib/useShielded';
import { useToast } from '@/components/Toast';
import { PageHeader } from '@/components/PageHeader';
import { Copy, Check, Share2 } from 'lucide-react';

export default function ReceivePage() {
  const { address } = useShielded();
  const toast = useToast();
  const [copied, setCopied] = useState(false);

  const copy = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true);
    toast.push({ kind: 'info', title: 'Address copied' });
    setTimeout(() => setCopied(false), 2000);
  };

  const share = async () => {
    if (!address) return;
    if (typeof navigator !== 'undefined' && (navigator as Navigator & { share?: (data: ShareData) => Promise<void> }).share) {
      try {
        await (navigator as Navigator & { share: (data: ShareData) => Promise<void> }).share({
          title: 'My FlowPay address',
          text: `Send me USDC on Arc Testnet: ${address}`,
        });
      } catch {
        /* user cancelled */
      }
    } else {
      copy();
    }
  };

  return (
    <>
      <PageHeader
        title="Receive"
        subtitle="Share your address to receive transfers."
      />

      <motion.div
        initial={{ opacity: 0, scale: 0.9, rotateY: 8 }}
        animate={{ opacity: 1, scale: 1, rotateY: 0 }}
        transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
        className="max-w-md bg-zinc-900/60 border border-zinc-800 rounded-2xl p-8 backdrop-blur"
      >
        {address ? (
          <>
            <div className="flex justify-center mb-6">
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.2 }}
                className="p-4 bg-white rounded-2xl"
              >
                <QRCodeSVG value={address} size={200} level="H" />
              </motion.div>
            </div>
            <div className="text-xs uppercase tracking-[0.15em] text-zinc-500 mb-2">
              Your address
            </div>
            <div className="font-mono text-xs break-all text-zinc-200 bg-zinc-950/60 border border-zinc-800 rounded-lg p-3 mb-3">
              {address}
            </div>
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={copy}
                className="py-2.5 bg-zinc-800 hover:bg-zinc-700 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
              >
                {copied ? (
                  <Check className="w-4 h-4 text-emerald-400" />
                ) : (
                  <Copy className="w-4 h-4" />
                )}
                {copied ? 'Copied' : 'Copy'}
              </button>
              <button
                onClick={share}
                className="py-2.5 bg-sky-600 hover:bg-sky-500 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
              >
                <Share2 className="w-4 h-4" />
                Share
              </button>
            </div>
          </>
        ) : (
          <div className="text-zinc-500 text-sm text-center py-12">
            Wallet not connected yet.
          </div>
        )}
      </motion.div>
    </>
  );
}
