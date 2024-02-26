// eslint-disable-next-line @typescript-eslint/no-var-requires,global-require
import "dotenv/config"

interface NetworkUserConfig {
  url: string;
  chainId: number;
  accounts: string[];
}

const core: NetworkUserConfig = {
  url: "https://rpc-core.icecreamswap.com",
  chainId: 1116,
  accounts: [process.env.PRIVATE_KEY!],
};

const xdc: NetworkUserConfig = {
  url: "https://rpc.ankr.com/xdc",
  chainId: 50,
  accounts: [process.env.PRIVATE_KEY!],
};

const shimmer: NetworkUserConfig = {
  url: "https://json-rpc.evm.shimmer.network",
  chainId: 148,
  accounts: [process.env.PRIVATE_KEY!],
};

const scroll: NetworkUserConfig = {
  url: "https://rpc-scroll.icecreamswap.com",
  chainId: 534352,
  accounts: [process.env.PRIVATE_KEY!],
};

const telos: NetworkUserConfig = {
  url: "https://mainnet.telos.net/evm",
  chainId: 40,
  accounts: [process.env.PRIVATE_KEY!],
};

const bitgert: NetworkUserConfig = {
  url: "https://rpc.icecreamswap.com",
  chainId: 32520,
  accounts: [process.env.PRIVATE_KEY!],
};

const base: NetworkUserConfig = {
  url: "https://developer-access-mainnet.base.org",
  chainId: 8453,
  accounts: [process.env.PRIVATE_KEY!],
};

const doge: NetworkUserConfig = {
  url: "https://rpc.dogechain.dog",
  chainId: 2000,
  accounts: [process.env.PRIVATE_KEY!],
};

const fuse: NetworkUserConfig = {
  url: "https://rpc.fuse.io",
  chainId: 122,
  accounts: [process.env.PRIVATE_KEY!],
};

const xodex: NetworkUserConfig = {
  url: "https://xo-dex.io",
  chainId: 2415,
  accounts: [process.env.PRIVATE_KEY!],
};

const doken: NetworkUserConfig = {
  url: "https://nyrpc.doken.dev",
  chainId: 61916,
  accounts: [process.env.PRIVATE_KEY!],
};

const neon: NetworkUserConfig = {
  url: "https://neon-proxy-mainnet.solana.p2p.org",
  chainId: 245022934,
  accounts: [process.env.PRIVATE_KEY!],
};

const shardeumTestnet: NetworkUserConfig = {
  url: "https://sphinx.shardeum.org",
  chainId: 8082,
  accounts: [process.env.PRIVATE_KEY!],
};

export const networks = {
  hardhat: {
    allowUnlimitedContractSize: true,
  },
  ...(process.env.PRIVATE_KEY && {
    core,
    xdc,
    shimmer,
    scroll,
    telos,
    bitgert,
    base,
    doge,
    fuse,
    xodex,
    doken,
    neon,
    shardeumTestnet,
  }),
};
