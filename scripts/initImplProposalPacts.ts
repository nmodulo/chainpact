import { ethers, network, upgrades } from "hardhat";
import { ConfigStruct } from "../typechain-types/contracts/ProposalPactUpgradeable"
const BigNumber = ethers.BigNumber


//Configuration for the contract
let config: ConfigStruct = {
  maxVotingPeriod: BigNumber.from(180 * 86400),
  minOpenParticipationVotingPeriod: BigNumber.from(12 * 60 * 60),
  groupsContract: "0x0000000000000000000000000000000000000000",
  minOpenParticipationAmount: ethers.utils.parseEther("0.01")
}

if(["ethereumMainnet", "kovan", "ropsten", "goerli", "sepolia"].includes(network.name)){
  config.minOpenParticipationAmount = ethers.utils.parseEther("0.001")
}

let implAddresses: {[network: string]: string} = {
  ["fuji"]: "0x6e581fc7bcb3b4a0f407b5a282c1a243c05658fd",
  ["mumbai"]: "0xDbf04A0E94D1003d403Ab986Fa731d4F9c1506F8",
  ["goerli"]: "0xDbf04A0E94D1003d403Ab986Fa731d4F9c1506F8",
  ["bsctest"]: "0xDbf04A0E94D1003d403Ab986Fa731d4F9c1506F8"
}


//Deploying to the network chosen through command line
async function main() {
 const ProposalPactUpgradeable = await ethers.getContractFactory("ProposalPactUpgradeable");
 const proposalPactImpl = ProposalPactUpgradeable.attach(implAddresses[network.name ?? "mumbai"])

 console.log("Initializing ProposalPact impl contract at ", proposalPactImpl.address);

 const result = await (await proposalPactImpl.initialize(config)).wait()
 console.log("result");
 console.log(result)
//  console.log(proposalPactUpgradeable)
}

main();

/**
 * In order to run this do:
 * npx hardhat --network hardhat run deployProxyProposalPact.ts
 * Replace --network hardhat with the network you want to deploy this to
 * The chosen network can be configured in hardhat.config.ts on the root older 
 */