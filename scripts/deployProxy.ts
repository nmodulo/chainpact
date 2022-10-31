import { ethers, upgrades } from "hardhat";

const maxVotingPeriod = 180 * 86400
const maxLockingPeriod = 900 * 86400
async function main() {
 const WordPactUpgradeable = await ethers.getContractFactory("WordPactUpgradeable");

 console.log("Deploying WordPactUpgradeable ...");

 const wordPactUpgradeable = await upgrades.deployProxy(WordPactUpgradeable, [maxLockingPeriod, maxVotingPeriod], {
   initializer: "initialize",
 });
 await wordPactUpgradeable.deployed();

 console.log("WordPactUpgradeable deployed to:", wordPactUpgradeable.address);
}

main();