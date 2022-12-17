import { ethers, network, upgrades } from "hardhat";

//Initializing values
const maxVotingPeriod = 180 * 86400
const maxLockingPeriod = 900 * 86400
const donationAccount = "0xcF9ebF877688Ed88a7479A6e63457Fd78D4275cE"
let donationMaxAmount = ethers.utils.parseEther("1000")

if(["ethereumMainnet", "kovan", "ropsten"].includes(network.name)){
  donationMaxAmount = ethers.utils.parseEther("1")
}

async function main() {
 const ProposalPactUpgradeable = await ethers.getContractFactory("ProposalPactUpgradeable");

 console.log("Deploying ProposalPactUpgradeable ...");

 const proposalPactUpgradeable = await upgrades.deployProxy(ProposalPactUpgradeable, [maxLockingPeriod, maxVotingPeriod, donationMaxAmount, donationAccount ], {
   initializer: "initialize",
 });
 await proposalPactUpgradeable.deployed();

 console.log("ProposalPactUpgradeable deployed to:", proposalPactUpgradeable.address);
 console.log(proposalPactUpgradeable)
}

main();