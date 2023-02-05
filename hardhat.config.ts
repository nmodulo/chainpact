import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import 'hardhat-contract-sizer'
import '@openzeppelin/hardhat-upgrades';
require("hardhat-gas-reporter");

require("dotenv").config();


const config: HardhatUserConfig = {
  solidity: "0.8.16",
  gasReporter: {
    enabled: true
  },
  networks: {
    hardhat: {
    },
    local: {
      url: "http://127.0.0.1:8545",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"]
    },
    fuji: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: [process.env.FUJI_PRIVATE_KEY_0 ?? "0x0"]
    }, 
    goerli: {
      url: "https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      accounts: [process.env.GOERLI_PRIVATE_KEY_0 ?? "0x0"]
    },
    mumbai: {
      url: "https://rpc-mumbai.maticvigil.com",
      accounts: [process.env.FUJI_PRIVATE_KEY_0 ?? "0x0"]    
    },
    bsctest: {
      url: "https://data-seed-prebsc-2-s1.binance.org:8545",
      accounts: [process.env.FUJI_PRIVATE_KEY_0 ?? "0X0"]
    }
  }
};

export default config;
