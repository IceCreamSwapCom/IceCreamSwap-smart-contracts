type BridgeConfig = {
  bridgeAdmin: string;
  relayers: string[];
  relayerThreshold: number;
  baseFeeDolla: number;
  tokenFeePercent: number;
  bridgedTokens: BridgedToken[];
};

interface BridgedToken {
  symbol: string;
  name: string;
  resourceId: string;
  rateLimit4h: string;
  rateLimit1d: string;
}

export const bridgeConfig: BridgeConfig = {
  bridgeAdmin: "0xe020582E77b5aA9e471e1A127906476242d12cb7",
  relayers: ["0xe4B30ce8D7Fd3A546D8a2a785D7D6108cCD1D683", "0x79f0939bf2E1bD0a9b526BE1A5462976b03a1278"],
  relayerThreshold: 1,
  baseFeeDolla: 1,
  tokenFeePercent: 0.5,
  bridgedTokens: [
    {
      symbol: "ICE",
      name: "IceCream",
      resourceId: "0x0000000000000000000000B999Ea90607a826A3E6E6646B404c3C7d11fa39D02",
      rateLimit4h: "10000000000000000000000", // 10k
      rateLimit1d: "25000000000000000000000", // 25k
    },
    {
      symbol: "USDT",
      name: "Tether USD",
      resourceId: "0x0000000000000000000000C7E6d7E08A89209F02af47965337714153c529F001",
      rateLimit4h: "10000000000000000000000", // 10k
      rateLimit1d: "25000000000000000000000", // 25k
    },
    {
      symbol: "BNB",
      name: "Binance Token",
      resourceId: "0x0000000000000000000000bb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c01",
      rateLimit4h: "20000000000000000000", // 20
      rateLimit1d: "50000000000000000000", // 50
    },
    {
      symbol: "ETH",
      name: "Ether",
      resourceId: "0x00000000000000000000002170Ed0880ac9A755fd29B2688956BD959F933F801",
      rateLimit4h: "1500000000000000000", // 1.5
      rateLimit1d: "4000000000000000000", // 4
    },
    {
      symbol: "SQD",
      name: "Subsquid",
      resourceId: "0x00000000000000000000001337420dED5ADb9980CFc35f8f2B054ea86f8aB112",
      rateLimit4h: "400000000000000000000000", // 400_000
      rateLimit1d: "1000000000000000000000000", // 1_000_000
    },
  ],
};

export const dexConfig = {
  dexAdmin: "0x0075C169d8887F902cF881fEdC26AD0EbC7c8c19",
  feeCollector: "0x2Bfd1fc5e25a8F55C2E849492ad7966EA8A0dd9E",
} as const;

export const farmConfig = {
  farmAdmin: "0x0075C169d8887F902cF881fEdC26AD0EbC7c8c19",
  iceTreasury: "0x0075C169d8887F902cF881fEdC26AD0EbC7c8c19",
} as const;
