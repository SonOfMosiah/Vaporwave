import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-solhint";
import "hardhat-docgen";

import * as dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.5.16", // VWAVE.sol | AuroraFactory.sol | Multicall.sol
      },
      {
        version: "0.6.6", // AuroraRouter.sol | AuroraChef.sol
      },
      {
        version: "0.6.12", // Trisolaris
      },
      {
        version: "0.8.17",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  networks: {
    aurora: {
      url: process.env.AURORA_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    testnet: {
      url: process.env.TESTNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    hardhat: {
      forking: {
        url: process.env.AURORA_URL || "",
        blockNumber: 70711000,
      },
    },
  },
  docgen: {
    path: "./docs",
    clear: true,
    runOnCompile: true,
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: {
      aurora: process.env.AURORASCAN_API_KEY!,
      auroraTestnet: process.env.AURORASCAN_API_KEY!,
    },
  },
};

export default config;
