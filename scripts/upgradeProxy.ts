import { ethers, network, upgrades } from "hardhat";

let deploymentDetails: any = {
    "fuji": { "address": "0xa9Fbe5372669b6297A367D7f799063c10c141b0B" }, 
    "local": { "address": "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9"}
}

async function main() {
    const WordPactV2 = await ethers.getContractFactory("WordPactUpgradeable");
    console.log("Upgrading WordPact...");
    let address = deploymentDetails[network.name]
    await upgrades.upgradeProxy(address, WordPactV2);
    console.log("WordPact upgraded successfully");
}

main();