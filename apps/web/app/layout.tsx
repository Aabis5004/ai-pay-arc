import type { Metadata } from 'next';
import { Instrument_Serif, Geist, JetBrains_Mono } from 'next/font/google';
import { Providers } from './providers';
import './globals.css';

const display = Instrument_Serif({
  weight: '400',
  subsets: ['latin'],
  variable: '--font-display',
});

const sans = Geist({
  subsets: ['latin'],
  variable: '--font-sans',
});

const mono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
});

export const metadata: Metadata = {
  title: 'AI Pay Arc',
  description: 'Smart payments with natural language',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`dark ${sans.variable} ${display.variable} ${mono.variable}`}
    >
      <body className="bg-zinc-950 text-zinc-100 antialiased font-sans">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
