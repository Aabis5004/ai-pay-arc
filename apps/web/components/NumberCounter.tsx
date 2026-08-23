'use client';

import { useEffect, useRef, useState } from 'react';

export function NumberCounter({
  value,
  decimals = 4,
}: {
  value: number;
  decimals?: number;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);

  useEffect(() => {
    const start = prevRef.current;
    const end = value;
    const duration = 700;
    const t0 = performance.now();
    let raf = 0;
    const tick = (t: number) => {
      const elapsed = t - t0;
      const k = Math.min(1, elapsed / duration);
      const eased = 1 - Math.pow(1 - k, 3);
      setDisplay(start + (end - start) * eased);
      if (k < 1) raf = requestAnimationFrame(tick);
      else prevRef.current = end;
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return <span>{display.toFixed(decimals)}</span>;
}
