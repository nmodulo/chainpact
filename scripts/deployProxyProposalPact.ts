import { ethers, network, upgrades } from "hardhat";
import { ConfigStruct } from "../typechain-types/contracts/ProposalPactUpgradeable";
import * as fs from 'fs'
import * as path from 'path'
const BigNumber = ethers.BigNumber;
const deployedFilePath = path.join(__dirname, "deployedContracts.json")

//Configuration for the contract
let config: ConfigStruct = {
  maxVotingPeriod: BigNumber.from(180 * 86400).toString(),
  minOpenParticipationVotingPeriod: BigNumber.from(12 * 60 * 60).toString(),
  groupsContract: "0x0000000000000000000000000000000000000000",
  minOpenParticipationAmount: ethers.utils.parseEther("0.01").toString(),
  commissionPerThousand: 5,
  commissionSink: "0x2526794f211aBF71F56eAbc54bC1D65B768CB678",
};

if (
  ["ethereumMainnet", "kovan", "ropsten", "goerli", "sepolia"].includes(
    network.name
  )
) {
  config.minOpenParticipationAmount = ethers.utils.parseEther("0.001");
}

//Deploying to the network chosen through command line
async function main() {
  const ProposalPactUpgradeable = await ethers.getContractFactory(
    "ProposalPactUpgradeable"
  );

  console.log("Deploying ProposalPactUpgradeable ...");

  const proposalPactUpgradeable = await upgrades.deployProxy(
    ProposalPactUpgradeable,
    [config],
    {
      initializer: "initialize",
    }
  );
  await proposalPactUpgradeable.deployed();

  console.log(
    "ProposalPactUpgradeable deployed to:",
    proposalPactUpgradeable.address
  );
  //  console.log(proposalPactUpgradeable)
  const chainId = ethers.provider.network.chainId;
  let deployedContractsJson: any = undefined;
  try {
    deployedContractsJson = fs.readFileSync(deployedFilePath);
  } catch {
    // console.log("Error reading deployedContracts.json")
  }
  let deployedContracts: any = {};
  if (!deployedContractsJson || deployedContractsJson.length === 0) {
    deployedContracts = { proposalPact: {} };
  } else {
    deployedContracts = JSON.parse(deployedContractsJson);

    if (!deployedContracts.proposalPact) {
      deployedContracts.proposalPact = {};
    }
  }
  deployedContracts.proposalPact[chainId] = {
    address: proposalPactUpgradeable.address,
    config,
  };
  const finalJson = JSON.stringify(deployedContracts, undefined, 2);
  fs.writeFileSync(deployedFilePath, finalJson);
  console.log(
    "Deployed to chain ",
    chainId,
    "\nWritten to file",
    deployedFilePath
  );
}

main();

/**
 * In order to run this do:
 * npx hardhat --network hardhat run deployProxyProposalPact.ts
 * Replace --network hardhat with the network you want to deploy this to
 * The chosen network can be configured in hardhat.config.ts on the root older
 */
