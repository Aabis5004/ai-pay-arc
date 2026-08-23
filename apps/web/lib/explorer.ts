import { sanvil } from 'seismic-viem';

export function explorerTxUrl(hash: string, chainId: number): string | null {
  if (chainId === sanvil.id) return null;
  if (chainId === 5124) return `https://seismic-testnet.socialscan.io/tx/${hash}`;
  return null;
}

export function explorerAddressUrl(addr: string, chainId: number): string | null {
  if (chainId === sanvil.id) return null;
  if (chainId === 5124) return `https://seismic-testnet.socialscan.io/address/${addr}`;
  return null;
}
