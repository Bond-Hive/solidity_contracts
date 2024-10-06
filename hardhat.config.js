require('dotenv').config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

const { SEPOLIA_API_URL, ARBITRUM_API_URL, SONIC_API_URL, PRIVATE_KEY, ETHERSCAN_API_KEY, ARBISCAN_API_KEY, MAINNET_API_URL } = process.env;

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  defaultNetwork: "sepolia",
  networks: {
    hardhat: {},
    sepolia: {
      url: SEPOLIA_API_URL,
      accounts: [`0x${PRIVATE_KEY}`]
    },
    arbitrum: {
      url: ARBITRUM_API_URL,
      accounts: [`0x${PRIVATE_KEY}`]
    },
    mainnet: {
      url: MAINNET_API_URL,
      accounts: [`0x${PRIVATE_KEY}`]
    },
    sonic: {
      url: SONIC_API_URL,
      accounts: [`0x${PRIVATE_KEY}`]
    }
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_API_KEY,
      sepolia: ETHERSCAN_API_KEY,
      arbitrum: ARBISCAN_API_KEY
    },
    customChains: [
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api",
          browserURL: "https://sepolia.etherscan.io"
        }
      },
      {
        network: "arbitrum",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io"
        }
      }
    ]
  },
}