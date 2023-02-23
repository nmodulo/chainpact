import { ethers, network, upgrades } from "hardhat";
import { ConfigStruct } from "../typechain-types/contracts/ProposalPactUpgradeable"
const BigNumber = ethers.BigNumber


//Configuration for the contract
let config: ConfigStruct = {
  maxVotingPeriod: BigNumber.from(180 * 86400),
  minOpenParticipationVotingPeriod: BigNumber.from(12 * 60 * 60),
  groupsContract: "0x0000000000000000000000000000000000000000",
  minOpenParticipationAmount: ethers.utils.parseEther("0.01"),
  commissionPerThousand: 5,
  commissionSink: "0x2526794f211aBF71F56eAbc54bC1D65B768CB678"
}

if(["ethereumMainnet", "kovan", "ropsten", "goerli", "sepolia"].includes(network.name)){
  config.minOpenParticipationAmount = ethers.utils.parseEther("0.001")
}


//Deploying to the network chosen through command line
async function main() {
 const ProposalPactUpgradeable = await ethers.getContractFactory("ProposalPactUpgradeable");

 console.log("Deploying ProposalPactUpgradeable ...");

 const proposalPactUpgradeable = await upgrades.deployProxy(ProposalPactUpgradeable, [config], {
   initializer: "initialize",
 });
 await proposalPactUpgradeable.deployed();

 console.log("ProposalPactUpgradeable deployed to:", proposalPactUpgradeable.address);
//  console.log(proposalPactUpgradeable)
}

main();

/**
 * In order to run this do:
 * npx hardhat --network hardhat run deployProxyProposalPact.ts
 * Replace --network hardhat with the network you want to deploy this to
 * The chosen network can be configured in hardhat.config.ts on the root older 
 */