import { ethers, upgrades } from "hardhat";

const PROXY = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";

async function main() {
 const WordPactV2 = await ethers.getContractFactory("WordPactV2");
 console.log("Upgrading WordPact...");
 await upgrades.upgradeProxy(PROXY, WordPactV2);
 console.log("WordPact upgraded successfully");
}

main();