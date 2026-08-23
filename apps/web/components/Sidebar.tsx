'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { motion } from 'framer-motion';
import { usePrivy } from '@privy-io/react-auth';
import { arcTestnet } from '@/lib/chain';
import {
  LayoutDashboard,
  Send,
  ArrowDownToLine,
  QrCode,
  Clock,
  PieChart,
  Settings,
  LogOut,
  Sparkles,
  CreditCard,
} from 'lucide-react';

const nav = [
  { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/send', label: 'Send', icon: Send },
  { href: '/deposit', label: 'Deposit', icon: ArrowDownToLine },
  { href: '/receive', label: 'Receive', icon: QrCode },
  { href: '/history', label: 'Activity', icon: Clock },
  { href: '/portfolio', label: 'Portfolio', icon: PieChart },
  { href: '/card', label: 'Card', icon: CreditCard },
  { href: '/trading', label: 'Arc AI', icon: Sparkles },
  { href: '/settings', label: 'Settings', icon: Settings },
];

export function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { user, logout } = usePrivy();
  
  const activeChain = arcTestnet;

  return (
    <aside className="w-60 h-full border-r border-zinc-900 bg-zinc-950/80 backdrop-blur p-5 flex flex-col">
      <div className="mb-8">
        <Link href="/dashboard" className="block" onClick={onNavigate}>
          <h1 className="text-lg tracking-tight">
            AI Pay{' '}
            <span
              className="text-sky-400"
              style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}
            >
              Arc
            </span>
          </h1>
          <div className="text-[10px] uppercase tracking-[0.2em] text-zinc-600 mt-1">
            Public Payments
          </div>
        </Link>
      </div>

      <nav className="flex-1 space-y-1 relative z-10">
        {nav.map((item) => {
          const active = pathname === item.href;
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className="block"
              onClick={onNavigate}
            >
              <motion.div
                className={`relative flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                  active ? 'text-white' : 'text-zinc-500 hover:text-zinc-200'
                }`}
              >
                {active && (
                  <motion.div
                    layoutId="sidebar-active"
                    className="absolute inset-0 bg-sky-600/15 border border-sky-800/50 rounded-lg"
                    transition={{ type: 'spring', stiffness: 380, damping: 30 }}
                  />
                )}
                <Icon className="w-4 h-4 relative" />
                <span className="relative">{item.label}</span>
              </motion.div>
            </Link>
          );
        })}
      </nav>

      <div className="pt-4 border-t border-zinc-900 space-y-3 relative z-20">
        {/* Network Status */}
        <div className="w-full flex items-center px-3 py-2 bg-zinc-900/30 border border-zinc-800/50 rounded-lg cursor-default">
          <div className="flex items-center gap-2 text-[11px]">
            <span className="w-1.5 h-1.5 rounded-full bg-sky-500" />
            <span className="text-zinc-400 font-medium">{activeChain.name}</span>
          </div>
        </div>

        <div className="px-3">
          <div className="text-[10px] uppercase tracking-[0.15em] text-zinc-600 mb-1">
            Signed in
          </div>
          <div className="text-xs font-mono text-zinc-400 truncate">
            {user?.wallet?.address
              ? `${user.wallet.address.slice(0, 6)}…${user.wallet.address.slice(-4)}`
              : user?.email?.address || '—'}
          </div>
        </div>
        <button
          onClick={logout}
          className="w-full flex items-center gap-2 px-3 py-2 text-xs text-zinc-500 hover:text-red-400 hover:bg-zinc-900/60 rounded-lg transition-colors"
        >
          <LogOut className="w-3.5 h-3.5" />
          Sign out
        </button>
      </div>
    </aside>
  );
}
