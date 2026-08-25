export type Token = {
  symbol: string;
  name: string;
  icon: string;
  address: string;
  decimals: number;
};

export const MOCK_TOKENS: Token[] = [
  { symbol: 'USDC', name: 'USD Coin', icon: 'https://cryptologos.cc/logos/usd-coin-usdc-logo.png', address: '0x3600000000000000000000000000000000000000', decimals: 6 },
  { symbol: 'EURC', name: 'Euro Coin', icon: 'https://cryptologos.cc/logos/usd-coin-usdc-logo.png', address: '0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a', decimals: 6 },
  { symbol: 'cirBTC', name: 'Circle Wrapped Bitcoin', icon: 'https://cryptologos.cc/logos/bitcoin-btc-logo.png', address: '0xf0C4a4CE82A5746AbAAd9425360Ab04fbBA432BF', decimals: 8 },
  { symbol: 'USDT', name: 'Tether USD', icon: 'https://cryptologos.cc/logos/tether-usdt-logo.png', address: '0x175CdB1D338945f0D851A741ccF787D343E57952', decimals: 6 },
];

export type Pool = {
  id: string;
  token0: Token;
  token1: Token;
  fee: string;
  type: string;
  volume: string;
  fees: string;
  tvl: string;
  apr: string;
  emissionApr: string;
};

export const MOCK_POOLS: Pool[] = [
  {
    id: 'pool-1',
    token0: MOCK_TOKENS[0], // USDC
    token1: MOCK_TOKENS[1], // EURC
    fee: '0.01%',
    type: 'Stable',
    volume: '~$10.22M',
    fees: '~$30,684.53',
    tvl: '~$27.79M',
    apr: '11.65%',
    emissionApr: '22.9%',
  },
  {
    id: 'pool-2',
    token0: MOCK_TOKENS[0], // USDC
    token1: MOCK_TOKENS[2], // cirBTC
    fee: '0.05%',
    type: 'Volatile',
    volume: '~$23.83M',
    fees: '~$59,591.67',
    tvl: '~$18.49M',
    apr: '35.36%',
    emissionApr: '50.37%',
  },
  {
    id: 'pool-3',
    token0: MOCK_TOKENS[1], // EURC
    token1: MOCK_TOKENS[2], // cirBTC
    fee: '0.05%',
    type: 'Volatile',
    volume: '~$5.12M',
    fees: '~$15,302.11',
    tvl: '~$12.55M',
    apr: '42.10%',
    emissionApr: '65.20%',
  },
];
