'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useRouter, usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Menu, X } from 'lucide-react';
import { Sidebar } from '@/components/Sidebar';
import { ChatFloater } from '@/components/ChatFloater';
import { NetworkGate } from '@/components/NetworkGate';
import { Particles } from '@/components/Particles';

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { ready, authenticated } = usePrivy();
  const router = useRouter();
  const pathname = usePathname();
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    if (ready && !authenticated) router.replace('/');
  }, [ready, authenticated, router]);

  useEffect(() => {
    setDrawerOpen(false);
  }, [pathname]);

  if (!ready || !authenticated) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-zinc-500">Loading…</div>
      </main>
    );
  }

  return (
    <>
      <Particles density={28} />
      <div className="relative z-10 flex min-h-screen">
        {/* Desktop sidebar */}
        <div className="hidden md:block w-60 shrink-0">
          <div className="fixed top-0 left-0 w-60 h-screen">
            <Sidebar />
          </div>
        </div>

        {/* Mobile drawer */}
        <AnimatePresence>
          {drawerOpen && (
            <>
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onClick={() => setDrawerOpen(false)}
                className="fixed inset-0 z-40 bg-black/60 md:hidden"
              />
              <motion.div
                initial={{ x: -240 }}
                animate={{ x: 0 }}
                exit={{ x: -240 }}
                transition={{ type: 'spring', stiffness: 320, damping: 30 }}
                className="fixed top-0 left-0 z-50 h-screen w-60 md:hidden"
              >
                <Sidebar onNavigate={() => setDrawerOpen(false)} />
              </motion.div>
            </>
          )}
        </AnimatePresence>

        <main className="flex-1 overflow-y-auto">
          {/* Mobile menu button */}
          <div className="md:hidden sticky top-0 z-30 bg-zinc-950/80 backdrop-blur border-b border-zinc-900 px-4 py-3 flex items-center gap-3">
            <button
              onClick={() => setDrawerOpen(true)}
              className="p-2 -ml-2 hover:bg-zinc-900 rounded-lg transition-colors"
              aria-label="Open menu"
            >
              {drawerOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
            <h1 className="text-sm tracking-tight">
              AI Pay{' '}
              <span
                className="text-violet-400"
                style={{ fontFamily: 'var(--font-display), serif', fontStyle: 'italic' }}
              >
                Seismic
              </span>
            </h1>
          </div>

          <div className="max-w-5xl mx-auto px-4 md:px-8 py-6 md:py-10">
            <NetworkGate>
              <AnimatePresence mode="wait">
                <motion.div
                  key={pathname}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -8 }}
                  transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
                >
                  {children}
                </motion.div>
              </AnimatePresence>
            </NetworkGate>
          </div>
        </main>

        <ChatFloater />
      </div>
    </>
  );
}
