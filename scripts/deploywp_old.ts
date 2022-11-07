import { ethers, network, upgrades } from "hardhat";

async function main() {
 const WordPactFactory = await ethers.getContractFactory("WordPact");

 console.log("Deploying Vanilla Wordpact ...");

 const wordpact = await WordPactFactory.deploy()
 await wordpact.deployed();

 console.log("Wordpact deployed to:", wordpact.address);
//  console.log(wordpact)
}

main();