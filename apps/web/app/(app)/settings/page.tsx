'use client';

import { motion } from 'framer-motion';
import { usePrivy } from '@privy-io/react-auth';
import { useChainId } from 'wagmi';
import { arcTestnet } from '@/lib/chain';
import { PageHeader } from '@/components/PageHeader';
import { LogOut } from 'lucide-react';

export default function SettingsPage() {
  const { user, logout, linkWallet } = usePrivy();
  const chainId = useChainId();

  const hasExternalWallet = user?.linkedAccounts.some(
    (acc) => acc.type === 'wallet' && acc.walletClientType !== 'privy'
  );

  const rows = [
    {
      label: 'Email',
      value: user?.email?.address || 'not linked',
    },
    {
      label: 'Wallet',
      value: user?.wallet?.address || '—',
      mono: true,
    },
    {
      label: 'Network',
      value: chainId === arcTestnet.id ? 'Arc Testnet' : `Chain ${chainId}`,
    },
    {
      label: 'Account created',
      value: user?.createdAt
        ? new Date(user.createdAt).toLocaleDateString()
        : '—',
    },
  ];

  return (
    <>
      <PageHeader title="Settings" subtitle="Your account and connection." />

      <motion.div
        initial={{ opacity: 0, x: -16 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="max-w-2xl space-y-4"
      >
        <div className="bg-zinc-900/60 border border-zinc-800 rounded-2xl backdrop-blur overflow-hidden">
          {rows.map((r, i) => (
            <div
              key={r.label}
              className={`px-6 py-4 ${i > 0 ? 'border-t border-zinc-800/60' : ''} flex items-center justify-between`}
            >
              <div className="text-xs uppercase tracking-[0.15em] text-zinc-500">
                {r.label}
              </div>
              <div
                className={`text-sm text-zinc-200 break-all text-right max-w-[60%] ${r.mono ? 'font-mono text-xs' : ''}`}
              >
                {r.value}
              </div>
            </div>
          ))}
        </div>

        {user && !hasExternalWallet && (
          <motion.button
            whileHover={{ scale: 1.01 }}
            whileTap={{ scale: 0.99 }}
            onClick={linkWallet}
            className="w-full px-6 py-3.5 bg-zinc-800 hover:bg-zinc-700 border border-zinc-700/50 rounded-2xl text-zinc-300 text-sm font-medium transition-colors flex items-center justify-center gap-2"
          >
            Link External Wallet
          </motion.button>
        )}

        <motion.button
          whileHover={{ scale: 1.01 }}
          whileTap={{ scale: 0.99 }}
          onClick={logout}
          className="w-full px-6 py-3.5 bg-red-950/40 hover:bg-red-950/60 border border-red-900/50 rounded-2xl text-red-300 text-sm font-medium transition-colors flex items-center justify-center gap-2"
        >
          <LogOut className="w-4 h-4" />
          Sign out
        </motion.button>
      </motion.div>
    </>
  );
}
