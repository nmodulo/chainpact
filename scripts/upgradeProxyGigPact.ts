import { ethers, network, upgrades } from "hardhat";

let deploymentDetails: any = {
    "local": { "address": "0x8A791620dd6260079BF849Dc5567aDC3F2FdC318"}
}

let libraries = {
    PactSignature: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
    DisputeHelper: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
}

async function main() {
    const GigPactV2 = await ethers.getContractFactory("GigPactUpgradeable", {libraries});
    console.log("Upgrading WordPact...");
    let address = deploymentDetails[network.name]
    let upgradedContract = await upgrades.upgradeProxy(
        address, 
        GigPactV2, 
        {unsafeAllowLinkedLibraries: true}
    )
    await upgradedContract.deployed()
    console.log("Gig Pact upgraded successfully to ", upgradedContract.address);
}

main();