import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import 'hardhat-contract-sizer'
import '@openzeppelin/hardhat-upgrades';
// require("hardhat-gas-reporter");

require("dotenv").config();


const config: HardhatUserConfig = {
  solidity: "0.8.16",
  gasReporter: {
    enabled: false
  },
  networks: {
    hardhat: {
    },
    local: {
      url: "http://127.0.0.1:8545",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"]
    }
  }
};

export default config;
