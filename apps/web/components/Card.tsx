'use client';

import { motion, type HTMLMotionProps } from 'framer-motion';
import { forwardRef } from 'react';

type Props = HTMLMotionProps<'div'> & { tilt?: boolean };

export const Card = forwardRef<HTMLDivElement, Props>(function Card(
  { tilt, className = '', children, ...rest },
  ref,
) {
  return (
    <motion.div
      ref={ref}
      whileHover={
        tilt
          ? { y: -2, transition: { duration: 0.2 } }
          : undefined
      }
      className={`bg-zinc-900/60 border border-zinc-800/80 rounded-2xl backdrop-blur transition-colors hover:border-zinc-700/80 ${className}`}
      {...rest}
    >
      {children}
    </motion.div>
  );
});
