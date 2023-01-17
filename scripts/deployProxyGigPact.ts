import { ethers, network, upgrades } from "hardhat";
import { DisputeHelper__factory, GigPactUpgradeable__factory, PactSignature__factory } from "../typechain-types";
const BigNumber = ethers.BigNumber


//Deploying to the network chosen through command line
async function main() {
 let pactSigFactory: PactSignature__factory = await ethers.getContractFactory("PactSignature")
 console.log("Deploying pactSignature library...")
 let pactSigLib = await pactSigFactory.deploy()
 pactSigLib = await pactSigLib.deployed()
 console.log("PactSignature library deployed at address ", pactSigLib.address)

 let disputeHelperFactory = await ethers.getContractFactory("DisputeHelper")
 console.log("Deploying DisputeHelper library...")
 let disputeHelperLib = await disputeHelperFactory.deploy()
 disputeHelperLib = await disputeHelperLib.deployed()
 console.log("DisputeHelper library deployed at address ", disputeHelperLib.address)

 let gigPactFactory = await ethers.getContractFactory("GigPactUpgradeable", {
   libraries: {
     PactSignature: pactSigLib.address,
     DisputeHelper: disputeHelperLib.address,
   }
 })

 console.log("Deploying GigPactUpgradeable contract through upgrades plugin ")
 const gigpactUpgradeable = await upgrades.deployProxy(gigPactFactory, [], {
    unsafeAllowLinkedLibraries: true
 });
 await gigpactUpgradeable.deployed()
 console.log("GigPactUpgradeable contract deployed at address ", gigpactUpgradeable.address)

}

main();

/**
 * In order to run this do:
 * npx hardhat --network hardhat run deployProxyProposalPact.ts
 * Replace --network hardhat with the network you want to deploy this to
 * The chosen network can be configured in hardhat.config.ts on the root older 
 */