import { assert, expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { BigNumberish, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { ProposalPactUpgradeable, ProposalPactUpgradeable__factory } from "../typechain-types";
import { VotingInfoStruct, ConfigStruct } from "../typechain-types/contracts/ProposalPactUpgradeable"
import { parseUnits } from "ethers/lib/utils";
const Signer = ethers.Signer
const BigNumber = ethers.BigNumber
const formatBytes32String = ethers.utils.formatBytes32String
let pact: ProposalPactUpgradeable

let [creator, participant1, participant2, participant3, participant4, participant5, arbitrator2, groupDummy]: SignerWithAddress[] = []

async function setSigners() {
    [creator, participant1, participant2, participant3, participant4, participant5, arbitrator2, groupDummy] = await ethers.getSigners()
}

let defaultVoters: string[]
let defaultFixedBeneficiaries: string[]
const defaultPactText = "Test pact"
const defaultVotingInfo = {
    votingEnabled: true,
    openParticipation: false,
    refundOnVotedYes: false,
    refundOnVotedNo: true,
    votingConcluded: false,
    duration: BigNumber.from("16"),
    votingStartTimestamp: BigNumber.from("0"),
    minContribution: BigNumber.from("0")
}

let config: ConfigStruct = {
    maxVotingPeriod: BigNumber.from(10000),
    minOpenParticipationVotingPeriod: BigNumber.from(4),
    groupsContract: "0x0",
    minOpenParticipationAmount: BigNumber.from(1000),
    commissionPerThousand: 5,
    commissionSink: "0x2526794f211aBF71F56eAbc54bC1D65B768CB678"
}

// const [testCreatePact, testWithBalance, testVotingActive, testAfterCreation, testVotingResults] = [true, true, true, true, true]
const [testStress] = [false,]

//Helper functions
// By default creates a pact with refundOnVotedNo, 2 yesBeneficiaries and 3 voters
async function createNewPact(
    value = BigNumber.from(0),
    votingInfo: VotingInfoStruct = defaultVotingInfo,
    voterAddresses: string[] = defaultVoters,
    yesBeneficiaries: string[] = defaultFixedBeneficiaries,
    noBeneficiaries: string[] = [],
    isEditable_ = false,
    pactText_: string = defaultPactText,
    memberListName = "",
) {
    let tx = await (await pact.createPact(votingInfo, isEditable_, formatBytes32String("test"), pactText_, voterAddresses, yesBeneficiaries, noBeneficiaries, { value })).wait()

    let resultingEvent = tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data)

    // console.log("result: ", "\n creator: ", resultingEvent.creator, "\n uid: ", resultingEvent.uid)
    return { resultingEvent, tx }
}

async function pitchInThousand(pactIds: string[]) {
    for (let i in pactIds) {
        await pact.connect(participant1).pitchIn(pactIds[i], { value: BigNumber.from(1000) })
        await pact.connect(participant2).pitchIn(pactIds[i], { value: BigNumber.from(1000) })
        await pact.connect(participant3).pitchIn(pactIds[i], { value: BigNumber.from(1000) })
    }
}

function compareVotingInfo(votingInfo: VotingInfoStruct, votingInfoAfter: any) {
    expect(votingInfo.votingEnabled).to.eq(votingInfoAfter.votingEnabled)
    expect(votingInfo.openParticipation).to.eq(votingInfoAfter.openParticipation)
    expect(votingInfo.refundOnVotedYes).to.eq(votingInfoAfter.refundOnVotedYes)
    expect(votingInfo.refundOnVotedNo).to.eq(votingInfoAfter.refundOnVotedNo)
    expect(votingInfo.votingConcluded).to.eq(votingInfoAfter.votingConcluded)
    expect(votingInfo.duration).to.eq(votingInfoAfter.duration)
    expect(votingInfo.votingStartTimestamp).to.eq(votingInfoAfter.votingStartTimestamp)
    expect(votingInfo.minContribution).to.eq(votingInfoAfter.minContribution)
}


describe("PP Stress test", function () {
    this.beforeAll(async () => {
      await setSigners();
      defaultVoters = [
        participant1.address,
        participant2.address,
        participant3.address,
      ];
      defaultFixedBeneficiaries = [participant4.address, participant5.address];
      config.groupsContract = groupDummy.address;
  
      let pactFactory: ProposalPactUpgradeable__factory =
        await ethers.getContractFactory("ProposalPactUpgradeable");
  
      pact = (await upgrades.deployProxy(pactFactory, [config], {initializer: "initialize"})) as ProposalPactUpgradeable
      // pact = await pactFactory.deploy();
      pact = await pact.deployed();
      // await pact.initialize(config);
    });

    if (testStress)
        describe("Too many Yes/No beneficiaries", function () {
            it("test with ", async function () {
                let votingInfo: VotingInfoStruct = {
                    votingEnabled: true,
                    openParticipation: true,
                    refundOnVotedYes: false,
                    refundOnVotedNo: true,
                    votingConcluded: false,
                    duration: BigNumber.from(3600),
                    votingStartTimestamp: BigNumber.from(1000),
                    minContribution: BigNumber.from(1000)
                }

                let yesBeneficiaries = []
                for(let i=0; i< 100; i++){
                    yesBeneficiaries.push(creator.address)
                }
                await expect(createNewPact(BigNumber.from(0), votingInfo, [], yesBeneficiaries)).to.be.revertedWith("too many")

                votingInfo.refundOnVotedYes = true
                votingInfo.refundOnVotedNo = false
                //Passing in 100 addresses in yesBeneficiaries array to noBeneficiaries
                await expect(createNewPact(BigNumber.from(0), votingInfo, [], [], yesBeneficiaries)).to.be.revertedWith("too many")
            })
        })


});
