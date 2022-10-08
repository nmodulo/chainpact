import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
// require("hardhat-gas-reporter");
const config: HardhatUserConfig = {
  solidity: "0.8.16",
  gasReporter: {
    enabled: false
  },
};

export default config;
