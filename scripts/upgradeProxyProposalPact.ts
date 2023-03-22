import { ethers, network, upgrades } from "hardhat";

import * as fs from 'fs'
import * as path from 'path'
const deployedFilePath = path.join(__dirname, "toUpgraded.json")

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

    // console.log((await ethers.provider.getNetwork()).chainId)
    const chainId = (await ethers.provider.getNetwork()).chainId

    const ProposalPactV2 = await ethers.getContractFactory("ProposalPactUpgradeable");
    console.log("Upgrading ProposalPact on chainId ", chainId, "...");
    let address = deployedContracts.proposalPact[chainId].address
    let upgradedContract = await upgrades.upgradeProxy(address, ProposalPactV2);
    await upgradedContract.deployed()

    console.log("ProposalPact upgraded successfully on chainId ", chainId);
}

main();