import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { WordPact, WordPact__factory } from "../typechain-types";
const Signer = ethers.Signer
const BigNumber = ethers.BigNumber
const formatBytes32String = ethers.utils.formatBytes32String
let pact: WordPact

let [creator, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2]: SignerWithAddress[] = []

async function setSigners() {
    [creator, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2] = await ethers.getSigners()
}

async function createNewPact(
    value = 0,
    isEditable_ = false,
    pactText_ = "Test pact",
    secondsToMaturity_ = 0,
    votingEnabled_ = true,
    particpantAddresses_ = ["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"],
    participantsCanVoteArray_ = [false],
    beneficiaryTypes = [0],
) {

    let tx = await (await pact.createPact(isEditable_, pactText_, secondsToMaturity_, votingEnabled_, particpantAddresses_, participantsCanVoteArray_, beneficiaryTypes, { value })).wait()
    let resultingEvent = tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data)

    // console.log("result: ", "\n creator: ", resultingEvent.creator, "\n uid: ", resultingEvent.uid)
    return {resultingEvent, tx}
}

const [testCreatePact, testSigning, testPactions, testdispute] = [true, false, true, false]

describe("WordPact", function () {

    this.beforeAll(async () => {
        await setSigners()
        let pactFactory: WordPact__factory = await ethers.getContractFactory("WordPact")
        pact = await pactFactory.deploy()
    })

    if (testCreatePact)
        describe("Create And edit", function () {
            it("Should allow creating a pact with various inputs", async function () {
                let {resultingEvent} = await createNewPact()
                expect(resultingEvent.creator).to.eq(creator.address)
                expect(resultingEvent.uid).to.have.length(66)
                // let pactCreated = await pact.getPact(resultingEvent.uid)
                // console.log(pactCreated)
            })
            it("should allow editing an editable pact", async function () {
                let {resultingEvent} = await createNewPact(0, true)
                let newText = "New text 01"
                await pact.setText(resultingEvent.uid || "", newText)
                expect((await pact.getPact(resultingEvent.uid)).pactText).to.eq(newText)
                await pact.setText(resultingEvent.uid || "", newText+"2")
                expect((await pact.getPact(resultingEvent.uid)).pactText).to.eq(newText+"2")
            })
            it("should not allow editing a non-editable pact", async function() {
                let {resultingEvent} = await createNewPact(0, false)
                let newText = "New text 01"
                await expect(pact.setText(resultingEvent.uid || "", newText)).to.be.reverted
            })
        })

    describe("With Balance", function () {
        it("should allow adding value to the pact while deploying", async function(){
            let value = 1000
            let balanceBefore = await ethers.provider.getBalance(pact.address)
            let {resultingEvent} = await createNewPact(value)
            let balanceAfter = await ethers.provider.getBalance(pact.address)
            let contributionAfter = await pact.contributions(resultingEvent.uid, creator.address)
            expect(balanceAfter).to.eq(balanceBefore.add(value))
            expect(contributionAfter).to.eq(value)
        })

        it("should allow withdrawing when no timelock", async function() {
            let value = 1000
            let pactDetails = await createNewPact(value)
            let balanceBefore = await ethers.provider.getBalance(creator.address)
            let tx = await (await pact.withdraw(pactDetails.resultingEvent.uid, value)).wait()
            let balanceAfter = await ethers.provider.getBalance(creator.address)
            expect(balanceAfter).to.eq(balanceBefore.add(value).sub(tx.gasUsed.mul(tx.effectiveGasPrice)))
        })

        it("should allow adding a timelock to the balance while deploying", async function(){
            let maturitySeconds = 1
            let {resultingEvent} = await createNewPact(10, false, "t", maturitySeconds)
            expect((await pact.pacts(resultingEvent.uid)).maturityTimeStamp).to.eq(
                (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
                + maturitySeconds
            )
        })
    })
});
