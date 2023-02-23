import { ethers, network, upgrades } from "hardhat";
import * as fs from 'fs'
import * as path from 'path'
import { DisputeHelper__factory, GigPactUpgradeable__factory, PactSignature__factory } from "../typechain-types";

const BigNumber = ethers.BigNumber
const deployedFilePath = path.join(__dirname, "deployedContracts.json")

const config = {
    "commissionSink": "0x2526794f211aBF71F56eAbc54bC1D65B768CB678",
    "commissionPerCent": 1
  }

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

 let payHelperFactory = await ethers.getContractFactory("PaymentHelper")
 console.log("Deploying PaymentHelper library...")
 let payHelperLib = await payHelperFactory.deploy()
 payHelperLib = await payHelperLib.deployed()
 console.log("PaymentHelper library deployed at address ", payHelperLib.address)

 let gigPactFactory = await ethers.getContractFactory("GigPactUpgradeable", {
   libraries: {
     PactSignature: pactSigLib.address,
     DisputeHelper: disputeHelperLib.address,
     PaymentHelper: payHelperLib.address
   }
 })

 console.log("Deploying GigPactUpgradeable contract through upgrades plugin ")
 const gigpactUpgradeable = await upgrades.deployProxy(gigPactFactory, [1, '0x2526794f211aBF71F56eAbc54bC1D65B768CB678'], {
    unsafeAllowLinkedLibraries: true,
    initializer: "initialize",
 });
 await gigpactUpgradeable.deployed()
 console.log("GigPactUpgradeable contract deployed at address ", gigpactUpgradeable.address)


 const chainId = ethers.provider.network.chainId
 let deployedContractsJson: any = undefined
 try {
     deployedContractsJson = fs.readFileSync(deployedFilePath)
 } catch {
     // console.log("Error reading deployedContracts.json")
 }
 let deployedContracts: any = {}
 if (!deployedContractsJson || deployedContractsJson.length === 0) {
     deployedContracts = { proposalPact: {}, gigPact: {}, pactSignatureLib: {}, disputeHelperLib: {}, payHelperLib: {}, localUsdc: {} }
 } else {
     deployedContracts = JSON.parse(deployedContractsJson)

     if (!deployedContracts.gigPact) {
         deployedContracts.gigPact = {}
     }
     if (!deployedContracts.pactSignatureLib) {
         deployedContracts.pactSignatureLib = {}
     }
     if (!deployedContracts.disputeHelperLib) {
         deployedContracts.disputeHelperLib = {}
     }
     if (!deployedContracts.payHelperLib) {
         deployedContracts.payHelperLib = {}
     }
 }
 deployedContracts.gigPact[chainId] = { address: gigpactUpgradeable.address, config }
 deployedContracts.pactSignatureLib[chainId] = { address: pactSigLib.address }
 deployedContracts.disputeHelperLib[chainId] = { address: disputeHelperLib.address }
 deployedContracts.payHelperLib[chainId] = { address: payHelperLib.address}
 const finalJson = JSON.stringify(deployedContracts, undefined, 2)
 fs.writeFileSync(deployedFilePath, finalJson)
 console.log("Deployed to chain ", chainId, "\nWritten to file", deployedFilePath)
}

main();

/**
 * In order to run this do:
 * npx hardhat --network hardhat run deployProxyProposalPact.ts
 * Replace --network hardhat with the network you want to deploy this to
 * The chosen network can be configured in hardhat.config.ts on the root older 
 */