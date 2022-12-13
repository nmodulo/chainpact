// import { expect } from "chai";
// import { ethers } from "hardhat";
// import { BigNumberish, Contract } from "ethers"
// import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
// import { WordPact, WordPact__factory } from "../typechain-types";
// import { ParticipantStruct } from "../typechain-types/WordPact"
// const Signer = ethers.Signer
// const BigNumber = ethers.BigNumber
// const formatBytes32String = ethers.utils.formatBytes32String
// let pact: WordPact

// let [creator, participant1, participant2, participant3, participant4, participant5, arbitrator2]: SignerWithAddress[] = []

// async function setSigners() {
//     [creator, participant1, participant2, participant3, participant4, participant5, arbitrator2] = await ethers.getSigners()
// }

// type party = {
//     addr: string
//     canVote: boolean
//     beneficiaryType: number

// }

// //Helper functions
// async function createNewPact(
//     value = BigNumber.from(0),
//     isEditable_ = false,
//     pactText_ = "Test pact",
//     secondsToMaturity_ = 0,
//     votingEnabled_ = true,
//     particpantAddresses_ = [],
//     participantsCanVoteArray_ = [],
//     beneficiaryTypes = [],
// ) {
//     let participants: ParticipantStruct[] = []
//     for (let i = 0; i < particpantAddresses_.length; i++) {
//         participants.push({
//             addr: particpantAddresses_[i],
//             canVote: participantsCanVoteArray_[i],
//             beneficiaryType: beneficiaryTypes[i]
//         })
//     }
//     let tx = await (await pact.createPact(isEditable_, pactText_, secondsToMaturity_, votingEnabled_, participantsCanVoteArray_, participants, { value })).wait()

//     let resultingEvent = tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data)

//     // console.log("result: ", "\n creator: ", resultingEvent.creator, "\n uid: ", resultingEvent.uid)
//     return { resultingEvent, tx }
// }

// const [testCreatePact, testWithBalance, testWithParticipants, testVoting] = [false, false, false, false]

// describe("WordPact", function () {

//     this.beforeAll(async () => {
//         await setSigners()
//         let pactFactory: WordPact__factory = await ethers.getContractFactory("WordPact")
//         pact = await pactFactory.deploy()
//     })

//     if (testCreatePact)
//         describe("Create And edit text", function () {
//             it("Should allow creating a pact with various inputs", async function () {
//                 let { resultingEvent } = await createNewPact()
//                 expect(resultingEvent.creator).to.eq(creator.address)
//                 expect(resultingEvent.uid).to.have.length(66)
//                 // let pactCreated = await pact.getPact(resultingEvent.uid)
//                 // console.log(pactCreated)
//             })
//             it("should allow editing an editable pact", async function () {
//                 let { resultingEvent } = await createNewPact(BigNumber.from(0), true)
//                 let newText = "New text 01"
//                 await pact.setText(resultingEvent.uid || "", newText)
//                 expect((await pact.getPact(resultingEvent.uid)).pactText).to.eq(newText)
//                 await pact.setText(resultingEvent.uid || "", newText + "2")
//                 expect((await pact.getPact(resultingEvent.uid)).pactText).to.eq(newText + "2")
//             })
//             it("should not allow editing a non-editable pact", async function () {
//                 let { resultingEvent } = await createNewPact(BigNumber.from(0), false)
//                 let newText = "New text 01"
//                 await expect(pact.setText(resultingEvent.uid || "", newText)).to.be.reverted
//             })
//         })

//     if (testWithBalance) describe("With Balance", function () {
//         it("should allow adding value to the pact while deploying", async function () {
//             let value = BigNumber.from(1000)
//             let balanceBefore = await ethers.provider.getBalance(pact.address)
//             let { resultingEvent } = await createNewPact(value)
//             let balanceAfter = await ethers.provider.getBalance(pact.address)
//             let contributionAfter = await pact.contributions(resultingEvent.uid, creator.address)
//             expect(balanceAfter).to.eq(balanceBefore.add(value))
//             expect(contributionAfter).to.eq(value)
//         })

//         it("should allow withdrawing when no timelock", async function () {
//             let value = BigNumber.from(1000)
//             let pactDetails = await createNewPact(value)
//             let balanceBefore = await ethers.provider.getBalance(creator.address)
//             let tx = await (await pact.withdraw(pactDetails.resultingEvent.uid, value)).wait()
//             let balanceAfter = await ethers.provider.getBalance(creator.address)
//             expect(balanceAfter).to.eq(balanceBefore.add(value).sub(tx.gasUsed.mul(tx.effectiveGasPrice)))
//         })

//         it("should lock the balance with timelock enabled", async function () {
//             let maturitySeconds = 1000
//             let value = BigNumber.from(1000)
//             let { resultingEvent } = await createNewPact(value, false, "t", maturitySeconds)
//             expect((await pact.pacts(resultingEvent.uid)).maturityTimeStamp).to.eq(
//                 (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
//                 + maturitySeconds
//             )
//             await expect(pact.withdraw(resultingEvent.uid, value)).to.be.reverted
//         })

//         it("should allow withdrawals post the timelock period", async function () {
//             let maturitySeconds = 1
//             let value = BigNumber.from(1000)
//             let { resultingEvent } = await createNewPact(value, false, "t", maturitySeconds)

//             console.log("Waiting...")
//             //Creating a 1.5 second delay in thread
//             await new Promise(f => setTimeout(f, 2000));
//             let balanceBefore = await ethers.provider.getBalance(creator.address)
//             let tx = await (await pact.withdraw(resultingEvent.uid, value)).wait()
//             let balanceAfter = await ethers.provider.getBalance(creator.address)
//             expect(balanceAfter).to.eq(balanceBefore.add(value).sub(tx.gasUsed.mul(tx.effectiveGasPrice)))
//         })

//     })


//     if (testWithParticipants) describe("Adding and managing participants", function () {
//         it("should allow deploying with mutliple participants", async function () {
//             let maturitySeconds = 1000
//             let value = BigNumber.from(1000)
//             let particpantAddresses_: any = [participant1.address, participant2.address]
//             let participantsCanVoteArray_: any = [false, false]
//             let beneficiaryTypes: any = [0, 0]
//             let { resultingEvent } = await createNewPact(value, false, "t", maturitySeconds, false, particpantAddresses_, participantsCanVoteArray_, beneficiaryTypes)
//             let createdPact = await pact.getPact(resultingEvent.uid)
//             expect(createdPact.participants.length).to.eq(2)
//             expect(createdPact.participants[0].addr).to.eq(participant1.address)
//             expect(createdPact.participants[1].addr).to.eq(participant2.address)
//         })

//         it("should allow adding participants to a deployed pact", async function () {
//             let { resultingEvent } = await createNewPact()
//             await pact.addParticipants(resultingEvent.uid, [{ addr: participant1.address, canVote: false, beneficiaryType: 0 }], [false])
//             let createdPact = await pact.getPact(resultingEvent.uid)
//             expect(createdPact.participants.length).to.eq(1)
//             expect(createdPact.participants[0].addr).to.eq(participant1.address)
//         })

//         it("should allow authorized participants to withdraw", async function () {
//             let value = BigNumber.from(1000)
//             let { resultingEvent } = await createNewPact(value)
//             await pact.addParticipants(resultingEvent.uid, [{ addr: participant1.address, canVote: false, beneficiaryType: 0 }], [true])
//             let balanceBefore = await ethers.provider.getBalance(participant1.address)
//             let tx = await (await pact.connect(participant1).withdraw(resultingEvent.uid, value.div(2))).wait()
//             let balanceAfter = await ethers.provider.getBalance(participant1.address)
//             expect(balanceAfter).to.eq(balanceBefore.add(value.div(2)).sub(tx.gasUsed.mul(tx.effectiveGasPrice)))
//             await pact.addParticipants(resultingEvent.uid, [{ addr: participant2.address, canVote: false, beneficiaryType: 0 }], [false])
//             expect(pact.connect(participant2).withdraw(resultingEvent.uid, value.div(2))).to.be.revertedWith("Unauthorized")
//         })
//     })

//     if(testVoting) describe("Test Voting", async function(){
//         let party1: party, party2: party, party3: party, party4: party

//         this.beforeAll(async () => {
//             party1 = { addr: participant1.address, canVote: true, beneficiaryType: 1 }  //YES Ben
//             party2 = { addr: participant2.address, canVote: true, beneficiaryType: 2 }  //NO  Ben
//             party3 = { addr: participant3.address, canVote: true, beneficiaryType: 1 }  //YES Ben
//             party4 = { addr: participant4.address, canVote: true, beneficiaryType: 1 }  //YES Ben
//         })

//         it("should allow choosing and retrieving yes and no vote outcomes", async function() {
//             let value = BigNumber.from(1000)
//             let { resultingEvent } = await createNewPact(value)
//             await pact.addParticipants(resultingEvent.uid, [party1, party2], [false, false])
//             let createdPact = await pact.getPact(resultingEvent.uid)
//             expect(createdPact.participants[0].beneficiaryType).to.eq(1)
//             expect(createdPact.participants[1].beneficiaryType).to.eq(2)
//         })

//         it("should allow starting vote with a fixed timeline, not allow voting after that", async function(){
//             let value = BigNumber.from(1000)
//             let { resultingEvent } = await createNewPact(value)
//             await pact.addParticipants(resultingEvent.uid, [party1, party2], [false, false])

//             await expect(pact.connect(participant1).voteOnPact(resultingEvent.uid, true)).to.be.reverted
//             await pact.startVotingWindow(resultingEvent.uid, 2)
//             await expect(await pact.connect(participant2).voteOnPact(resultingEvent.uid, false)).to.not.be.reverted
//             await new Promise(f => setTimeout(f, 2200));
//             await expect(pact.connect(participant3).voteOnPact(resultingEvent.uid, true)).to.be.reverted

//             let resultingNoVotes = (await pact.getPact(resultingEvent.uid)).noVotes
//             let resultingYesVotes = (await pact.getPact(resultingEvent.uid)).yesVotes
//             expect(resultingNoVotes).to.eq(1)
//             expect(resultingYesVotes).to.eq(0)
//         })

//         it("should disburse the yes and no vote beneficiaries after voting ends", async function(){
//             let value = BigNumber.from(1000)
//             let { resultingEvent } = await createNewPact(value)
            
//             await pact.addParticipants(resultingEvent.uid, [party1, party2, party3, party4], [false, false, false, false])
            
//             await pact.startVotingWindow(resultingEvent.uid, 8)

//             await expect(await pact.connect(participant1).voteOnPact(resultingEvent.uid, true)).to.not.be.reverted
//             await expect(await pact.connect(participant2).voteOnPact(resultingEvent.uid, true)).to.not.be.reverted
//             await expect(await pact.connect(participant3).voteOnPact(resultingEvent.uid, true)).to.not.be.reverted
//             await expect(await pact.connect(participant4).voteOnPact(resultingEvent.uid, false)).to.not.be.reverted
            
//             await new Promise(f => setTimeout(f, 4000));

//             let balancesBefore = [
//                 await ethers.provider.getBalance(participant1.address),
//                 await ethers.provider.getBalance(participant2.address),
//                 await ethers.provider.getBalance(participant3.address),
//                 await ethers.provider.getBalance(participant4.address),
//             ]

//             await pact.endVoting(resultingEvent.uid);
//             // Count votes
//             let resultingNoVotes = (await pact.getPact(resultingEvent.uid)).noVotes
//             let resultingYesVotes = (await pact.getPact(resultingEvent.uid)).yesVotes
//             expect(resultingNoVotes).to.eq(1)
//             expect(resultingYesVotes).to.eq(3)

//             let balancesAfter = [
//                 await ethers.provider.getBalance(participant1.address),
//                 await ethers.provider.getBalance(participant2.address),
//                 await ethers.provider.getBalance(participant3.address),
//                 await ethers.provider.getBalance(participant4.address),
//             ]
//             //Check balances
//             expect(balancesAfter[0].sub(balancesBefore[0])).to.eq(value.div(3).toBigInt())
//             expect(balancesAfter[1].sub(balancesBefore[1])).to.eq(0)
//             expect(balancesAfter[2].sub(balancesBefore[2])).to.eq(value.div(3).toBigInt())
//             expect(balancesAfter[3].sub(balancesBefore[3])).to.eq(value.div(3).toBigInt())
//         })
//         it("should allow pitching in and refund all amounts on no vote, if refundOnVotedNo selected", async function(){
//             let value = ethers.utils.parseUnits("1", "ether")
//             let { resultingEvent } = await createNewPact(value)
        
            
//             await pact.addParticipants(resultingEvent.uid, [party1, party2, party3, party4], [false, false, false, false])
//             await pact.connect(participant1).pitchIn(resultingEvent.uid, {value})

//             await pact.setRefundOnVotedNo(resultingEvent.uid, true)

//             await pact.startVotingWindow(resultingEvent.uid, 4)
//             await expect(await pact.connect(participant1).voteOnPact(resultingEvent.uid, false)).to.not.be.reverted
//             await expect(await pact.connect(participant2).voteOnPact(resultingEvent.uid, false)).to.not.be.reverted

//             let balancesBefore = [
//                 await ethers.provider.getBalance(participant1.address),
//                 await ethers.provider.getBalance(participant2.address),
//                 await ethers.provider.getBalance(participant3.address),
//                 await ethers.provider.getBalance(participant4.address),
//             ]

//             await new Promise(f => setTimeout(f, 4000));
//             await pact.endVoting(resultingEvent.uid)

//             let balancesAfter = [
//                 await ethers.provider.getBalance(participant1.address),
//                 await ethers.provider.getBalance(participant2.address),
//                 await ethers.provider.getBalance(participant3.address),
//                 await ethers.provider.getBalance(participant4.address),
//             ]

//             for(let i=0; i<balancesAfter.length; i++) expect(balancesBefore[i]).to.eq(balancesAfter[i])

//             let tx = await (await pact.connect(participant1).withdrawContribution(resultingEvent.uid)).wait()
//             expect(await ethers.provider.getBalance(participant1.address)).to.eq(balancesAfter[0].add(value).sub( tx.gasUsed.mul(tx.effectiveGasPrice)))

//         })
//         it("should not allow participants to be added during voting", async function(){
//             let { resultingEvent } = await createNewPact()
//             await pact.addParticipants(resultingEvent.uid, [party1], [false])
//             await pact.startVotingWindow(resultingEvent.uid, 2)
//             await expect (pact.addParticipants(resultingEvent.uid, [party2], [false])).to.be.reverted
//         })
//     })
// });
