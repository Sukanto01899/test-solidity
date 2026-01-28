require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const {
  SEPOLIA_RPC_URL,
  BASE_RPC_URL,
  BASE_SEPOLIA_RPC_URL,
  OP_RPC_URL,
  ARB_RPC_URL,
  CELO_RPC_URL,
  PRIVATE_KEY,
  ETHERSCAN_API_KEY,
  BASESCAN_API_KEY,
  BLOCKSCOUT_API_KEY,
  BASE_EXPLORER,
} = process.env;

// Choose which explorer to use for Base / Base-Sepolia verification.
// Options: "basescan" (default) or "blockscout".
const baseExplorer = (BASE_EXPLORER || "basescan").toLowerCase();

const baseExplorerUrls =
  baseExplorer === "blockscout"
    ? {
        base: {
          apiURL: "https://base.blockscout.com/api",
          browserURL: "https://base.blockscout.com",
        },
        baseSepolia: {
          apiURL: "https://base-sepolia.blockscout.com/api",
          browserURL: "https://base-sepolia.blockscout.com",
        },
      }
    : {
        // Use Etherscan V2 endpoints for Base
        base: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org",
        },
        baseSepolia: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      };

// Single API key string (required for Etherscan V2). Reuse whichever is provided.
const explorerApiKey =
  (baseExplorer === "blockscout" ? BLOCKSCOUT_API_KEY : BASESCAN_API_KEY) ||
  ETHERSCAN_API_KEY ||
  "";

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
    },
  },
  networks: {
    sepolia: {
      url: SEPOLIA_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    base: {
      url: BASE_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    "base-sepolia": {
      url: BASE_SEPOLIA_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    op: {
      url: OP_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    arb: {
      url: ARB_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
    celo: {
      url: CELO_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
  },
  etherscan:
    baseExplorer === "blockscout"
      ? {
          apiKey: explorerApiKey,
          customChains: [
            {
              network: "base",
              chainId: 8453,
              urls: baseExplorerUrls.base,
            },
            {
              network: "base-sepolia",
              chainId: 84532,
              urls: baseExplorerUrls.baseSepolia,
            },
          ],
        }
      : {
          // Use built-in Etherscan V2 routing (single apiKey, no customChains)
          apiKey: explorerApiKey,
        },
};
