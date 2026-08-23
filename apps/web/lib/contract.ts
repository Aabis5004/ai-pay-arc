import arcPayAbi from './arcPayAbi.json';
import { arcTestnet } from './chain';
import { erc20Abi } from 'viem';

export const ARC_PAY_ADDRESS = process.env
  .NEXT_PUBLIC_ARC_PAY_ADDRESS as `0x${string}`;

export const TEST_ETH_ADDRESS = process.env
  .NEXT_PUBLIC_TEST_ETH_ADDRESS as `0x${string}`;

export const CHAIN = arcTestnet;

export const arcPay = {
  address: ARC_PAY_ADDRESS,
  abi: arcPayAbi,
} as const;

export const testEth = {
  address: TEST_ETH_ADDRESS,
  abi: erc20Abi,
} as const;
