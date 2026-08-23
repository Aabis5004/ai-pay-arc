'use client';

import { motion } from 'framer-motion';

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35 }}
      className="flex items-end justify-between mb-8"
    >
      <div>
        <h1 className="text-3xl tracking-tight">{title}</h1>
        {subtitle && (
          <p className="text-sm text-zinc-500 mt-1.5">{subtitle}</p>
        )}
      </div>
      {action && <div>{action}</div>}
    </motion.div>
  );
}
