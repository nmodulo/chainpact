import { assert, expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { WordPactUpgradeable, WordPactUpgradeable__factory } from "../typechain-types";
import { VotingInfoStruct, ConfigStruct } from "../typechain-types/contracts/WordPactUpgradeable"
import { parseUnits } from "ethers/lib/utils";
const Signer = ethers.Signer
const BigNumber = ethers.BigNumber
const formatBytes32String = ethers.utils.formatBytes32String
let pact: WordPactUpgradeable

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
    minOpenParticipationAmount: BigNumber.from(1000)
}

const [testCreatePact, testWithBalance, testVotingActive, testAfterCreation, testVotingResults] = [true, true, true, true, true]

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


describe("WordPactUpgradeable", function () {

    this.beforeAll(async () => {
        await setSigners()
        defaultVoters = [participant1.address, participant2.address, participant3.address]
        defaultFixedBeneficiaries = [participant4.address, participant5.address]
        config.groupsContract = groupDummy.address

        let pactFactory: WordPactUpgradeable__factory = await ethers.getContractFactory("WordPactUpgradeable")
        pact = await pactFactory.deploy()
        pact = await pact.deployed()
        await pact.initialize(config)
    })

    if (testCreatePact)
        describe("Create a pact", function () {
            it("Should create a pact with with voting disabled", async function () {
                let votingInfo: VotingInfoStruct = {
                    votingEnabled: false,
                    openParticipation: false,
                    refundOnVotedYes: false,
                    refundOnVotedNo: false,
                    votingConcluded: false,
                    duration: BigNumber.from(3600),
                    votingStartTimestamp: BigNumber.from(0),
                    minContribution: BigNumber.from(0)
                }
                let { resultingEvent } = await createNewPact(BigNumber.from(0), votingInfo)
                expect(resultingEvent.uid).to.have.length(66)

                //Check all obtainaible details
                let pactData = await pact.pacts(resultingEvent.uid)
                let votingInfoAfter = await pact.votingInfo(resultingEvent.uid)
                let pactParticipants = await pact.getParticipants(resultingEvent.uid)

                expect(pactData.creator).to.eq(creator.address)
                compareVotingInfo(votingInfo, votingInfoAfter)
                expect(pactParticipants[0].length).to.eq(0)
                expect(pactParticipants[1].length).to.eq(0)
                expect(pactParticipants[2].length).to.eq(0)
            })

            it("should create a pact with fixed participants, fixed yes and no beneficiaries", async function () {
                let votingInfo: VotingInfoStruct = {
                    votingEnabled: true,
                    openParticipation: false,
                    refundOnVotedYes: false,
                    refundOnVotedNo: false,
                    votingConcluded: true,
                    duration: BigNumber.from(3600),
                    votingStartTimestamp: BigNumber.from(0),
                    minContribution: BigNumber.from(0)
                }
                let { resultingEvent } = await createNewPact(BigNumber.from(0), votingInfo, [participant1.address, participant2.address], [participant3.address], [participant5.address])
                let pactParticipants = await pact.getParticipants(resultingEvent.uid)

                expect(pactParticipants).to.eql([[participant1.address, participant2.address], [participant3.address], [participant5.address]])
            })

            it("should create a pact with open participation, fixed yes and refund no, and vice versa", async function () {
                let votingInfo: VotingInfoStruct = {
                    votingEnabled: true,
                    openParticipation: true,
                    refundOnVotedYes: true,
                    refundOnVotedNo: false,
                    votingConcluded: true,  //Should overwrite this
                    duration: BigNumber.from(3600),
                    votingStartTimestamp: BigNumber.from(0),
                    minContribution: BigNumber.from(1000)
                }
                let { resultingEvent, tx } = await createNewPact(BigNumber.from(0), votingInfo, [], [participant2.address], [participant5.address])

                let pactParticipants = await pact.getParticipants(resultingEvent.uid)
                expect(pactParticipants).to.eql([[], [], [participant5.address]])

                votingInfo.votingConcluded = false
                votingInfo.votingStartTimestamp = BigNumber.from((await ethers.provider.getBlock(tx.blockNumber)).timestamp).add(30 * 60)
                compareVotingInfo(votingInfo, await pact.votingInfo(resultingEvent.uid))

                votingInfo.refundOnVotedNo = true
                resultingEvent = (await createNewPact(BigNumber.from(0), votingInfo, [], [participant2.address], [participant5.address])).resultingEvent
                votingInfo.votingStartTimestamp = BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber() - 1)).timestamp).add(30 * 60)
                compareVotingInfo(votingInfo, (await pact.votingInfo(resultingEvent.uid)))
                pactParticipants = await pact.getParticipants(resultingEvent.uid)
                expect(pactParticipants).to.eql([[], [], []])
            })

            it("should create a pact with closed participation", async function () {
                //Closed participation
                let { resultingEvent, tx } = (await createNewPact())
                let votingInfo = Object.assign({}, defaultVotingInfo)
                votingInfo.votingStartTimestamp = BigNumber.from((await ethers.provider.getBlock(tx.blockNumber)).timestamp + 30 * 60)
                compareVotingInfo(votingInfo, await pact.votingInfo(resultingEvent.uid))
                let pactParticipants = await pact.getParticipants(resultingEvent.uid)
                expect(pactParticipants).to.eql([defaultVoters, defaultFixedBeneficiaries, []])
            })

            it("should revert on less than min contribution on open participation", async function () {
                let votingInfo = Object.assign({}, defaultVotingInfo)
                votingInfo.openParticipation = true
                votingInfo.minContribution = BigNumber.from(10)
                await expect(createNewPact(BigNumber.from(0), votingInfo)).to.be.reverted

                votingInfo.minContribution = BigNumber.from(1000)
                await expect(await createNewPact(BigNumber.from(0), votingInfo)).to.not.be.reverted
            })

            it("should revert on not having yes or no beneficiaries", async function () {
                let votingInfo = Object.assign({}, defaultVotingInfo)
                await expect(createNewPact(BigNumber.from(0), votingInfo, defaultVoters, [])).to.be.reverted

                await expect(await createNewPact(BigNumber.from(0), votingInfo, defaultVoters, defaultFixedBeneficiaries)).to.not.be.reverted

                votingInfo.refundOnVotedNo = false
                await expect(createNewPact(BigNumber.from(0), votingInfo, defaultVoters, defaultFixedBeneficiaries, [])).to.be.reverted

                await expect(await createNewPact(BigNumber.from(0), votingInfo, defaultVoters, defaultFixedBeneficiaries, [participant1.address])).to.not.be.reverted
            })

            it("should revert on incorrect voting duration", async function () {
                let votingInfo = Object.assign({}, defaultVotingInfo)
                votingInfo.duration = BigNumber.from(config.minOpenParticipationVotingPeriod).div(3)
                await expect(createNewPact(BigNumber.from(0), votingInfo)).to.be.reverted

                votingInfo.duration = BigNumber.from(config.maxVotingPeriod).add(10)
                await expect(createNewPact(BigNumber.from(0), votingInfo)).to.be.reverted

                votingInfo.duration = BigNumber.from(config.maxVotingPeriod).sub(1)
                await expect(await createNewPact(BigNumber.from(0), votingInfo)).to.not.be.reverted
            })

            it("should let edit a pact if it is editble", async function () {
                let { resultingEvent, tx } = await createNewPact(BigNumber.from(0), defaultVotingInfo, defaultVoters, defaultFixedBeneficiaries, [], true)
                await expect(await pact.setText(resultingEvent.uid, "New text")).to.not.be.reverted

                expect((await pact.pacts(resultingEvent.uid)).pactText).to.eq("New text")

                resultingEvent = (await createNewPact(BigNumber.from(0), defaultVotingInfo, defaultVoters, defaultFixedBeneficiaries, [], false)).resultingEvent

                await expect(pact.setText(resultingEvent.uid, "new text")).to.be.reverted
            })
        })

    if (testWithBalance) describe("With Balance", function () {
        it("should allow adding value to the pact while deploying", async function () {
            let value = BigNumber.from(1000)

            let balanceBefore = await ethers.provider.getBalance(pact.address)

            let { resultingEvent } = await createNewPact(value)

            let balanceAfter = await ethers.provider.getBalance(pact.address)
            expect(balanceAfter).to.eq(balanceBefore.add(value))

            let contributionAfter = (await pact.userInteractionData(resultingEvent.uid, creator.address)).contribution
            expect(contributionAfter).to.eq(value)

            expect((await pact.pacts(resultingEvent.uid)).totalValue).to.eq(value)
        })

        it("should allow pitching in and withdrawing contribution", async function () {
            let value = parseUnits("1", "ether")
            let votingInfo = Object.assign({}, defaultVotingInfo)
            //Adding 20 to the previous block timestamp to ensure sufficient gap before next block
            // votingInfo.votingStartTimestamp = BigNumber.from((await ethers.provider.getBlock(ethers.provider.blockNumber)).timestamp).add(20)
            let { resultingEvent, tx } = await createNewPact(BigNumber.from(0), votingInfo)
            //Pitch in first time
            await pact.connect(participant2).pitchIn(resultingEvent.uid, { value })
            expect((await pact.pacts(resultingEvent.uid)).totalValue).to.eq(value)

            //Check balance after withdrawal
            let accBalanceBefore = await ethers.provider.getBalance(participant2.address);
            let withdrawTxReceipt = await (await pact.connect(participant2).
                withDrawContribution(resultingEvent.uid, value)).wait()
            expect((await pact.pacts(resultingEvent.uid)).totalValue).to.eq(BigNumber.from(0))
            let accBalanceAfter = await ethers.provider.getBalance(participant2.address)
            expect(accBalanceAfter.add(withdrawTxReceipt.gasUsed.mul(withdrawTxReceipt.effectiveGasPrice))).to.eq(accBalanceBefore.add(value))

            //Pitch in again
            await pact.connect(participant2).pitchIn(resultingEvent.uid, { value })
            expect((await pact.pacts(resultingEvent.uid)).totalValue).to.eq(value)
        })
    })

    if (testAfterCreation) describe("After creation", function () {
        it("should allow adding voters", async function () {
            let { resultingEvent, tx } = await createNewPact()
            let voters = (await pact.getParticipants(resultingEvent.uid))[0]
            expect(voters).to.eql(defaultVoters)
            await pact.addVoters(resultingEvent.uid, [participant4.address, participant5.address])
            voters = (await pact.getParticipants(resultingEvent.uid))[0]
            expect(voters).to.eql([...defaultVoters, participant4.address, participant5.address])
        })

        it("should not allow adding voters by address other than creator", async function () {
            let { resultingEvent, tx } = await createNewPact()
            await expect(pact.connect(participant2).addVoters(resultingEvent.uid, [participant4.address, participant5.address])).to.be.reverted
        })

        it("should allow postponing start voting timestamp by 24 hours", async function () {
            let { resultingEvent, tx } = await createNewPact()
            let currVotingStartTs = (await pact.votingInfo(resultingEvent.uid)).votingStartTimestamp
            await pact.postponeVotingWindow(resultingEvent.uid)
            expect(currVotingStartTs + 24 * 60 * 60).eq((await pact.votingInfo(resultingEvent.uid)).votingStartTimestamp)
        })
    })

    if (testVotingActive) describe("Test Voting Active", function () {
        let resultingEvent: any, tx: any;
        this.beforeAll(async function () {
            let votingInfo = Object.assign({}, defaultVotingInfo)
            //Adding 20 to the previous block timestamp to ensure sufficient gap before next block
            votingInfo.votingStartTimestamp = BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp).add(5)
            // votingInfo.votingStartTimestamp = BigNumber.from(Math.ceil(new Date().getTime() / 1000)).add(10)
            votingInfo.duration = BigNumber.from(1000)

            let createdPact = await createNewPact(BigNumber.from(0), votingInfo)
            resultingEvent = createdPact.resultingEvent
            tx = createdPact.tx
            console.log("Waiting for 5 seconds...")
            await new Promise(f => setTimeout(f, 5 * 1000));
        })

        it("should not allow withdraw contribution", async function () {
            await pact.connect(participant2).pitchIn(resultingEvent.uid, { value: BigNumber.from(1000) })
            expect((await pact.pacts(resultingEvent.uid)).totalValue).to.eq(BigNumber.from(1000))
            await expect(pact.connect(participant2).withDrawContribution(resultingEvent.uid, BigNumber.from(1000))).to.be.reverted
        })

        it("should not allow adding voters", async function () {
            await expect(pact.addVoters(resultingEvent.uid, [participant4.address])).to.be.reverted
        })
        it("should not allow postponing voting window", async function () {
            await expect(pact.postponeVotingWindow(resultingEvent.uid)).to.be.reverted
        })

        it("should allow pitching in, but should not allow withdraw", async function () {
            await pact.connect(participant2).pitchIn(resultingEvent.uid, { value: BigNumber.from(1000) })
            //Voting should be active by now
            await expect(pact.connect(participant2).withDrawContribution(resultingEvent.uid, BigNumber.from(1000))).to.be.reverted
        })

        it("should allow added voters to cast vote, but only once", async function () {
            let pactData = await pact.pacts(resultingEvent.uid)
            await expect(await pact.connect(participant1).voteOnPact(resultingEvent.uid, true)).to.not.be.reverted
            await expect(await pact.connect(participant2).voteOnPact(resultingEvent.uid, false)).to.not.be.reverted


            let pactDataAfter = await pact.pacts(resultingEvent.uid)
            expect(pactData.yesVotes + 1).to.eq(pactDataAfter.yesVotes)
            expect(pactData.noVotes + 1).to.eq(pactDataAfter.noVotes)

            await expect(pact.connect(participant1).voteOnPact(resultingEvent.uid, true)).to.be.reverted
            await expect(await pact.connect(participant3).voteOnPact(resultingEvent.uid, true)).to.not.be.reverted
        })

        it("should not allow non-voters to cast vote", async function () {
            await expect(pact.connect(participant5).voteOnPact(resultingEvent.uid, false)).to.be.reverted
        })

    })

    if (testVotingResults) describe("Test voting results", function () {
        let openVotedYesFixed: any, openVotedYesRefund: any, openVotedNoFixed: any, openVotedNoRefund: any
        let closedVotedYesFixed: any, closedVotedYesRefund: any, closedVotedNoFixed: any, closedVotedNoRefund: any
        this.beforeAll(async function () {
            let votingInfo = {
                votingEnabled: true,
                openParticipation: false,
                refundOnVotedYes: true,
                refundOnVotedNo: true,
                votingConcluded: false,
                duration: BigNumber.from("40"),
                // votingStartTimestamp: BigNumber.from(Math.ceil(new Date().getTime() / 1000)).add(25),
                votingStartTimestamp: BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp).add(10),
                minContribution: BigNumber.from("0")
            }

            //Four Scenarios for closed voting

            //1
            votingInfo.refundOnVotedYes = false
            closedVotedYesFixed = (await createNewPact(BigNumber.from(0), votingInfo, defaultVoters, defaultFixedBeneficiaries)).resultingEvent

            //2
            votingInfo.refundOnVotedYes = true
            closedVotedYesRefund = (await createNewPact(BigNumber.from(0), votingInfo)).resultingEvent

            //3
            votingInfo.refundOnVotedNo = true
            closedVotedNoRefund = (await createNewPact(BigNumber.from(0), votingInfo)).resultingEvent

            //4 - with added min contribution
            votingInfo.refundOnVotedNo = false
            votingInfo.minContribution = BigNumber.from(config.minOpenParticipationAmount)
            closedVotedNoFixed = (await createNewPact(BigNumber.from(0), votingInfo, defaultVoters, [], defaultFixedBeneficiaries)).resultingEvent

            //Four scenarios for open voting
            votingInfo.openParticipation = true
            votingInfo.minContribution = BigNumber.from(config.minOpenParticipationAmount)

            votingInfo.refundOnVotedYes = false
            votingInfo.refundOnVotedNo = true
            openVotedYesFixed = (await createNewPact(BigNumber.from(0), votingInfo, defaultVoters, defaultFixedBeneficiaries)).resultingEvent

            votingInfo.refundOnVotedYes = true
            openVotedYesRefund = (await createNewPact(BigNumber.from(0), votingInfo)).resultingEvent

            votingInfo.refundOnVotedNo = false

            openVotedNoFixed = (await createNewPact(BigNumber.from(0), votingInfo, [], [], defaultFixedBeneficiaries)).resultingEvent

            votingInfo.refundOnVotedNo = true
            openVotedNoRefund = (await createNewPact(BigNumber.from(0), votingInfo)).resultingEvent

            await pitchInThousand(
                [
                    openVotedYesFixed.uid,
                    openVotedYesRefund.uid,
                    openVotedNoFixed.uid,
                    openVotedNoRefund.uid,
                    closedVotedYesFixed.uid,
                    closedVotedYesRefund.uid,
                    closedVotedNoRefund.uid,
                ]
            )

            // console.log("Waiting for 4 seconds...")
            // await new Promise(f => setTimeout(f, 4 * 1000));

            //Vote on closed vote pacts - 3 participant voters
            await pact.connect(participant1).voteOnPact(closedVotedYesFixed.uid, true)
            await pact.connect(participant2).voteOnPact(closedVotedYesFixed.uid, true)
            await pact.connect(participant3).voteOnPact(closedVotedYesFixed.uid, false)

            await pact.connect(participant1).voteOnPact(closedVotedYesRefund.uid, true)
            await pact.connect(participant2).voteOnPact(closedVotedYesRefund.uid, true)
            await pact.connect(participant3).voteOnPact(closedVotedYesRefund.uid, false)

            await pact.connect(participant1).voteOnPact(closedVotedNoRefund.uid, false)
            await pact.connect(participant2).voteOnPact(closedVotedNoRefund.uid, false)
            await pact.connect(participant3).voteOnPact(closedVotedNoRefund.uid, true)

            //This one has min contribution
            await pact.connect(participant1).pitchIn(closedVotedNoFixed.uid, { value: votingInfo.minContribution })
            await pact.connect(participant1).voteOnPact(closedVotedNoFixed.uid, false)
            await expect(pact.connect(participant2).voteOnPact(closedVotedNoFixed.uid, false)).to.be.reverted
            await pact.connect(participant2).pitchIn(closedVotedNoFixed.uid, { value: votingInfo.minContribution })
            await expect(await pact.connect(participant2).voteOnPact(closedVotedNoFixed.uid, false)).to.not.be.reverted
            await expect(pact.connect(participant3).voteOnPact(closedVotedNoFixed.uid, true)).to.be.reverted
            await pact.connect(participant3).pitchIn(closedVotedNoFixed.uid, { value: votingInfo.minContribution })
            await expect(await pact.connect(participant3).voteOnPact(closedVotedNoFixed.uid, true)).to.not.be.reverted

            //Vote on Open pacts
            await pact.connect(participant1).voteOnPact(openVotedYesFixed.uid, true)
            await pact.connect(participant1).voteOnPact(openVotedYesRefund.uid, true)
            await pact.connect(participant1).voteOnPact(openVotedNoFixed.uid, false)
            await pact.connect(participant1).voteOnPact(openVotedNoRefund.uid, false)

            console.log("Waiting for 8 seconds...")
            await new Promise(f => setTimeout(f, 8 * 1000));
        })


        it("should not let non-voters conclude", async function () {
            await expect(pact.connect(participant5).concludeVoting(closedVotedYesFixed.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(closedVotedYesFixed.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(closedVotedNoFixed.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(closedVotedYesRefund.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(closedVotedNoRefund.uid)).to.be.reverted
        })


        it("should let a voter conclude results, and disburse correctly for closed voters", async function () {
            let closedVotedYesFixedData = await pact.pacts(closedVotedYesFixed.uid)
            let closedVotedNoFixedData = await pact.pacts(closedVotedNoFixed.uid)
            let closedVotedYesRefundData = await pact.pacts(closedVotedYesRefund.uid)
            let closedVotedNoRefundData = await pact.pacts(closedVotedNoRefund.uid)
            let grants

            expect(closedVotedYesFixedData.totalValue).to.eq(3000)
            expect(closedVotedNoFixedData.totalValue).to.eq(3000)
            expect(closedVotedYesRefundData.totalValue).to.eq(3000)
            expect(closedVotedNoRefundData.totalValue).to.eq(3000)
            grants = await Promise.all(defaultFixedBeneficiaries.map(async function (e) { return await pact.grants(e) }))

            //Conclude voting - and keep checking grants
            let grantDelta = 3000 / grants.length
            await pact.connect(participant1).concludeVoting(closedVotedYesFixed.uid)
            grants = await Promise.all(defaultFixedBeneficiaries.map(async function (e) { return await pact.grants(e) }))
            expect(grants[0]).to.eq(grantDelta)
            expect(grants[1]).to.eq(grantDelta)

            grantDelta += 3000 / grants.length
            await pact.connect(participant1).concludeVoting(closedVotedNoFixed.uid)
            grants = await Promise.all(defaultFixedBeneficiaries.map(async function (e) { return await pact.grants(e) }))
            expect(grants[0]).to.eq(grantDelta)
            expect(grants[1]).to.eq(grantDelta)

            await pact.connect(participant1).concludeVoting(closedVotedYesRefund.uid)
            await pact.connect(participant1).concludeVoting(closedVotedNoRefund.uid)

            //check the grants
            expect(closedVotedYesFixedData.yesVotes).to.eq(2)
            expect(closedVotedYesRefundData.noVotes).to.eq(1)
            expect(closedVotedNoFixedData.noVotes).to.eq(2)
            expect(closedVotedNoRefundData.yesVotes).to.eq(1)
        })

        it("should not let someone without minimum contribution to conclude for open voting", async function () {
            await expect(pact.connect(participant5).concludeVoting(openVotedYesFixed.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(openVotedYesRefund.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(openVotedNoFixed.uid)).to.be.reverted
            await expect(pact.connect(participant5).concludeVoting(openVotedNoRefund.uid)).to.be.reverted
        })

        it("should let a voter with min contribution to conclude for openParticipation", async function () {
            let grants = await Promise.all(defaultFixedBeneficiaries.map(async function (e) { return await pact.grants(e) }))
            let pactValue = (await pact.pacts(openVotedYesFixed.uid)).totalValue
            let grantDelta = grants[0]

            await pact.connect(participant1).concludeVoting(openVotedYesFixed.uid)
            grants = await Promise.all(defaultFixedBeneficiaries.map(async function (e) { return await pact.grants(e) }))
            grantDelta = grantDelta.add(pactValue.div(grants.length))
            expect(grants[0]).to.eq(grantDelta)
            expect(grants[1]).to.eq(grantDelta)

            pactValue = (await pact.pacts(openVotedNoFixed.uid)).totalValue
            await pact.connect(participant1).concludeVoting(openVotedNoFixed.uid)
            grants = await Promise.all(defaultFixedBeneficiaries.map(async function (e) { return await pact.grants(e) }))
            grantDelta = grantDelta.add(pactValue.div(grants.length))
            expect(grants[0]).to.eq(grantDelta)
            expect(grants[1]).to.eq(grantDelta)

            expect((await pact.pacts(openVotedYesFixed.uid)).yesVotes).to.eq(1)
            expect((await pact.pacts(openVotedYesRefund.uid)).yesVotes).to.eq(1)
            expect((await pact.pacts(openVotedNoFixed.uid)).noVotes).to.eq(1)
            expect((await pact.pacts(openVotedNoRefund.uid)).noVotes).to.eq(1)

            await pact.connect(participant1).concludeVoting(openVotedYesRefund.uid)
            expect((await pact.pacts(openVotedYesRefund.uid)).refundAvailable).to.be.true

            await pact.connect(participant1).concludeVoting(openVotedNoRefund.uid)
            expect((await pact.pacts(openVotedNoRefund.uid)).refundAvailable).to.be.true

        })
    })

});
