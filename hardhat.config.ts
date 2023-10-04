import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("dotenv").config();

const { INFURA_KEY, PRIVATE_KEY } = process.env;

const config: HardhatUserConfig = {
  paths: { tests: "tests" },
  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        runs: 200,
        enabled: true,
      },
    },
  },
  defaultNetwork: "lineaTestnet",
  networks: {
    hardhat: {},
    xdai: {
       url: "https://xdai-archive.blockscout.com",
       accounts: [PRIVATE_KEY!],
       gasPrice: "auto",
       gas: "auto"
     },
     sokol: {
       url: "https://sokol.poa.network",
       accounts: [PRIVATE_KEY!],
       gasPrice: 5000000000,
       gas: "auto"
     },
     goerli: {
       url: `https://goerli.infura.io/v3/${INFURA_KEY}`,
       accounts: [PRIVATE_KEY!],
       gasPrice: 1000000000,
       gas: "auto"
     },
     bsc: {
       url: "https://bsc-dataseed1.defibit.io",
       accounts: [PRIVATE_KEY!],
       gasPrice: 5000000000,
       gas: "auto"
     },
     eth: {
       url: `https://mainnet.infura.io/v3/${INFURA_KEY}`,
       accounts: [PRIVATE_KEY!],
       gasPrice: 37000000000,
       gas: "auto"
     },
    lineaTestnet: {
      url: `https://linea-goerli.infura.io/v3/${INFURA_KEY}`,
      accounts: [PRIVATE_KEY!],
      chainId: 59140,
    },
    baseTestnet: {
      url: `https://goerli.base.org`,
      gasPrice: 600000000,
      accounts: [PRIVATE_KEY!],
      chainId: 84531,
    }
  },
};

export default config;
