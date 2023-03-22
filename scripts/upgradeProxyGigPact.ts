import { ethers, network, upgrades } from "hardhat";
import * as fs from 'fs'
import * as path from 'path'
import { DisputeHelper__factory, GigPactUpgradeable__factory, PactSignature__factory } from "../typechain-types";

const deployedFilePath = path.join(__dirname, "toUpgraded.json")
// const upgradedFilePath = path.join(__dirname, "upgradedContractsNew.json")

async function main() {
    let deployedContracts: any = {}
    let deployedContractsJson: any = undefined
    try {
        deployedContractsJson = fs.readFileSync(deployedFilePath)
        if (!deployedContractsJson || deployedContractsJson.length === 0) return
        deployedContracts = JSON.parse(deployedContractsJson)
        
    } catch {
        console.log("Error reading old json")
        return
    }
    if (!deployedContractsJson || deployedContractsJson.length === 0) return
    const chainId = (await ethers.provider.getNetwork()).chainId
    //Use the existing libraries
    let libraries = {
        PactSignature: deployedContracts.pactSignatureLib[chainId].address,
        DisputeHelper: deployedContracts.disputeHelperLib[chainId].address,
        PaymentHelper: deployedContracts.payHelperLib[chainId].address,
    }

    // //Re-deploy libraries
    // let pactSigFactory: PactSignature__factory = await ethers.getContractFactory("PactSignature")
    // console.log("Deploying pactSignature library...")
    // let pactSigLib = await pactSigFactory.deploy()
    // pactSigLib = await pactSigLib.deployed()
    // console.log("PactSignature library deployed at address ", pactSigLib.address)
   
    // let disputeHelperFactory = await ethers.getContractFactory("DisputeHelper")
    // console.log("Deploying DisputeHelper library...")
    // let disputeHelperLib = await disputeHelperFactory.deploy()
    // disputeHelperLib = await disputeHelperLib.deployed()
    // console.log("DisputeHelper library deployed at address ", disputeHelperLib.address)
   
    // let payHelperFactory = await ethers.getContractFactory("PaymentHelper")
    // console.log("Deploying PaymentHelper library...")
    // let payHelperLib = await payHelperFactory.deploy()
    // payHelperLib = await payHelperLib.deployed()
    // console.log("PaymentHelper library deployed at address ", payHelperLib.address)

    // let libraries = {
    //     PactSignature: pactSigLib.address,
    //     DisputeHelper: disputeHelperLib.address,
    //     PaymentHelper: payHelperLib.address,
    // }

    const GigPactV2 = await ethers.getContractFactory("GigPactUpgradeable", {libraries});
    console.log("Upgrading Gig Pact...");
    let address = deployedContracts.gigPact[chainId].address
    let upgradedContract = await upgrades.upgradeProxy(
        address, 
        GigPactV2, 
        {unsafeAllowLinkedLibraries: true}
    )
    await upgradedContract.deployed()
    console.log("Gig Pact upgraded successfully to ", upgradedContract.address);

    if (!deployedContractsJson || deployedContractsJson.length === 0) {
        return
        // deployedContracts = { proposalPact: {}, gigPact: {}, pactSignatureLib: {}, disputeHelperLib: {}, payHelperLib: {}, localUsdc: {} }
    } else {   
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
    deployedContracts.gigPact[chainId] = { address: upgradedContract.address, config: deployedContracts.gigPact[chainId].config }
    // deployedContracts.pactSignatureLib[chainId] = { address: pactSigLib.address }
    // deployedContracts.disputeHelperLib[chainId] = { address: disputeHelperLib.address }
    // deployedContracts.payHelperLib[chainId] = { address: payHelperLib.address}  

    deployedContracts.pactSignatureLib[chainId] = { address: libraries.PactSignature }
    deployedContracts.disputeHelperLib[chainId] = { address: libraries.DisputeHelper}
    deployedContracts.payHelperLib[chainId] = { address: libraries.PaymentHelper}
    const finalJson = JSON.stringify(deployedContracts, undefined, 2)
    fs.writeFileSync(deployedFilePath, finalJson)
    console.log("Deployed to chain ", chainId, "\nWritten to file", deployedFilePath)
}
main();