'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { CheckCircle2, XCircle, Info } from 'lucide-react';

type ToastKind = 'success' | 'error' | 'info';
type Toast = { id: number; kind: ToastKind; title: string; body?: string };

type ToastCtx = {
  push: (t: Omit<Toast, 'id'>) => void;
};

const Ctx = createContext<ToastCtx | null>(null);

export function useToast() {
  const c = useContext(Ctx);
  if (!c) throw new Error('useToast outside ToastProvider');
  return c;
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const push = useCallback((t: Omit<Toast, 'id'>) => {
    const id = Date.now() + Math.random();
    setToasts((arr) => [...arr, { id, ...t }]);
    setTimeout(() => {
      setToasts((arr) => arr.filter((x) => x.id !== id));
    }, 5000);
  }, []);

  return (
    <Ctx.Provider value={{ push }}>
      {children}
      <div className="fixed top-4 right-4 z-[100] flex flex-col gap-2 pointer-events-none">
        <AnimatePresence initial={false}>
          {toasts.map((t) => (
            <ToastItem key={t.id} toast={t} />
          ))}
        </AnimatePresence>
      </div>
    </Ctx.Provider>
  );
}

function ToastItem({ toast }: { toast: Toast }) {
  const Icon =
    toast.kind === 'success'
      ? CheckCircle2
      : toast.kind === 'error'
        ? XCircle
        : Info;
  const colour =
    toast.kind === 'success'
      ? 'text-emerald-400 border-emerald-900/40 bg-emerald-950/40'
      : toast.kind === 'error'
        ? 'text-red-400 border-red-900/40 bg-red-950/40'
        : 'text-violet-400 border-violet-900/40 bg-violet-950/40';

  return (
    <motion.div
      initial={{ opacity: 0, x: 24, scale: 0.95 }}
      animate={{ opacity: 1, x: 0, scale: 1 }}
      exit={{ opacity: 0, x: 24, transition: { duration: 0.15 } }}
      transition={{ type: 'spring', stiffness: 350, damping: 28 }}
      className={`pointer-events-auto min-w-[280px] max-w-sm px-4 py-3 rounded-xl border backdrop-blur ${colour}`}
    >
      <div className="flex items-start gap-3">
        <Icon className="w-4 h-4 mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium text-zinc-100">{toast.title}</div>
          {toast.body && (
            <div className="text-xs text-zinc-400 mt-0.5 break-all">
              {toast.body}
            </div>
          )}
        </div>
      </div>
    </motion.div>
  );
}
