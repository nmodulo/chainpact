import { ethers, network, upgrades } from "hardhat";

let deploymentDetails: any = {
    "local": { "address": "0x9A676e781A523b5d0C0e43731313A708CB607508"},
    "fuji": {
        "address": "0xfE73051489B13841081457935229aE130702eA19"
    }
}

let libraries = {
    PactSignature: "0xd1D7C00f3F4A0A4a5539694D1d80075d8d223A48",
    DisputeHelper: "0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0",
    PaymentHelper: "0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82"
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