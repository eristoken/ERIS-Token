import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-verify";
import { defineConfig } from "hardhat/config";
import * as dotenv from "dotenv";

dotenv.config();

if (!process.env.PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY not set in .env file");
}

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    "base-sepolia": {
      type: "http",
      chainType: "op",
      url: "https://sepolia.base.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    "arbitrum-sepolia": {
      type: "http",
      chainType: "generic",
      url: "https://arbitrum-sepolia-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    "ink-sepolia": {
      type: "http",
      chainType: "op",
      url: "https://rpc-gel-sepolia.inkonchain.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    "unichain-sepolia": {
      type: "http",
      chainType: "op",
      url: "https://sepolia.unichain.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    "op-sepolia": {
      type: "http",
      chainType: "op",
      url: "https://optimism-sepolia-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: "https://sepolia.drpc.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    bscTestnet: {
      type: "http",
      chainType: "l1",
      url: "https://bsc-testnet-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    base: {
      type: "http",
      chainType: "op",
      url: "https://base-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    bsc: {
      type: "http",
      chainType: "l1",
      url: "https://bsc-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    polygon: {
      type: "http",
      chainType: "generic",
      url: "https://polygon-bor-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    worldChain: {
      type: "http",
      chainType: "op",
      url: "https://worldchain-mainnet.g.alchemy.com/public",
      accounts: [process.env.PRIVATE_KEY],
    },
    mantle: {
      type: "http",
      chainType: "generic",
      url: "https://mantle-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    mainnet: {
      type: "http",
      chainType: "l1",
      url: "https://eth.meowrpc.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    optimisticEthereum: {
      type: "http",
      chainType: "op",
      url: "https://optimism-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    arbitrumOne: {
      type: "http",
      chainType: "generic",
      url: "https://arbitrum-one-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    Avalanche: {
      type: "http",
      chainType: "op",
      url: "https://avalanche-c-chain-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    Blast: {
      type: "http",
      chainType: "op",
      url: "https://blast-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    XLayer: {
      type: "http",
      chainType: "generic",
      url: "https://xlayer.drpc.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    Unichain: {
      type: "http",
      chainType: "op",
      url: "https://mainnet.unichain.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    ink: {
      type: "http",
      chainType: "op",
      url: "https://rpc-gel.inkonchain.com",
      accounts: [process.env.PRIVATE_KEY],
    },
    Soneium: {
      type: "http",
      chainType: "op",
      url: "https://rpc.soneium.org/",
      accounts: [process.env.PRIVATE_KEY],
    },
    Zora: {
      type: "http",
      chainType: "op",
      url: "https://rpc.zora.energy",
      accounts: [process.env.PRIVATE_KEY],
    },
    Mode: {
      type: "http",
      chainType: "op",
      url: "https://mode.drpc.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    metalL2: {
      type: "http",
      chainType: "op",
      url: "https://metall2.drpc.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    Bob: {
      type: "http",
      chainType: "op",
      url: "https://bob.drpc.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    Shape: {
      type: "http",
      chainType: "op",
      url: "https://shape-mainnet.g.alchemy.com/public",
      accounts: [process.env.PRIVATE_KEY],
    },
    moonbeam: {
      type: "http",
      chainType: "op",
      url: "https://moonbeam-rpc.publicnode.com",
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  chainDescriptors: {
    // Arbitrum One
    42161: {
      name: "Arbitrum One",
      chainType: "generic",
      blockExplorers: {
        etherscan: {
          name: "ArbitrumScan",
          url: "https://arbiscan.io/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
        blockscout: {
          name: "Arbitrum Explorer",
          url: "https://arbitrum.blockscout.com/",
          apiUrl: "https://arbitrum.blockscout.com/api",
        },
      },
    },
    // Base
    8453: {
      name: "Base",
      chainType: "op",
      blockExplorers: {
        etherscan: {
          name: "BaseScan",
          url: "https://basescan.org/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
        blockscout: {
          name: "Base Explorer",
          url: "https://base.blockscout.com/",
          apiUrl: "https://base.blockscout.com/api",
        },
      },
    },
    // Ethereum
    1: {
      name: "Ethereum",
      chainType: "l1",
      blockExplorers: {
        etherscan: {
          name: "Etherscan",
          url: "https://etherscan.io/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
        blockscout: {
          name: "Ethereum Explorer",
          url: "https://eth.blockscout.com/",
          apiUrl: "https://eth.blockscout.com/api",
        },
      },
    },
    // Polygon
    137: {
      name: "Polygon",
      chainType: "op",
      blockExplorers: {
        etherscan: {
          name: "PolygonScan",
          url: "https://polygonscan.com/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
        blockscout: {
          name: "Polygon Explorer",
          url: "https://polygon.blockscout.com/",
          apiUrl: "https://polygon.blockscout.com/api",
        },
      },
    },
    // World Chain
    480: {
      name: "World Chain",
      chainType: "op",
      blockExplorers: {
        etherscan: {
          name: "WorldScan",
          url: "https://worldscan.org/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
        blockscout: {
          name: "World Chain Explorer",
          url: "https://worldchain-mainnet.explorer.alchemy.com/",
          apiUrl: "https://worldchain-mainnet.explorer.alchemy.com/api",
        },
      },
    },
    // Mantle
    5000: {
      name: "Mantle",
      chainType: "generic",
      blockExplorers: {
        etherscan: {
          name: "MantleScan",
          url: "https://mantlescan.xyz/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
      },
    },
    // Ink
    57073: {
      name: "Ink",
      chainType: "op",
      blockExplorers: {
        blockscout: {
          name: "Ink Explorer",
          url: "https://explorer.inkonchain.com",
          apiUrl: "https://explorer.inkonchain.com/api",
        },
      },
    },
    // Soneium
    1868: {
      name: "Soneium",
      chainType: "op",
      blockExplorers: {
        blockscout: {
          name: "Soneium Explorer",
          url: "https://soneium.blockscout.com/",
          apiUrl: "https://soneium.blockscout.com/api",
        },
      },
    },
    // Unichain
    130: {
      name: "Unichain",
      chainType: "op",
      blockExplorers: {
        etherscan: {
          name: "UniScan",
          url: "https://uniscan.xyz/",
          apiUrl: "https://api.etherscan.io/v2/api",
        },
        blockscout: {
          name: "Unichain Explorer",
          url: "https://unichain.blockscout.com/",
          apiUrl: "https://unichain.blockscout.com/api",
        },
      },
    },
    // Metal L2
    1750: {
      name: "Metal L2",
      chainType: "op",
      blockExplorers: {
        blockscout: {
          name: "Metal Explorer",
          url: "https://explorer-metal-mainnet-0.t.conduit.xyz:443",
          apiUrl: "https://explorer-metal-mainnet-0.t.conduit.xyz/api",
        },
      },
    },
  },
  verify: {
    // Type assertion needed: runtime supports apiKey as object with network names
    // and customChains property, but TypeScript types are more restrictive
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY ?? '',
    },
    blockscout: {
      enabled: true,
    },
  },
  ignition: {
    strategyConfig: {
      create2: {
        salt: process.env.SALT ?? "0x0000000000000000000000000000000000000000000000000000000000000000",
      },
    },
  },
});
