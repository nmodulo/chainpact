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

async function deployToDisputePact(suggestedAmt: BigNumberish) {
    // let pact = await deployAndSignRandomPact()
    // await pact.delegate([employerDelegate.address], true)
    // await pact.connect(employee).delegate([employeeDelegate.address], true)
    // await pact.connect(employerDelegate).start()
    // await pact.connect(employerDelegate).terminate()
    // await pact.connect(employerDelegate).fNf({ value: suggestedAmt })
    // await pact.connect(employeeDelegate).dispute(suggestedAmt)
    // return pact
}

const [testCreatePact, testSigning, testPactions, testdispute] = [true, false, true, false]

describe("WordPact", function () {

    this.beforeAll(async () => {
        await setSigners()
        let pactFactory: WordPact__factory = await ethers.getContractFactory("WordPact")
        pact = await pactFactory.deploy()
    })

    if (testCreatePact)
        describe("Create Pact", function () {
            it("Should allow creating a pact with various inputs", async function () {

                let isEditable_ = false
                let  pactText_ = "Test pact"
                let maturityTimeStamp_ = 0
                let votingEnabled_ = true
                let particpantAddresses_ = ["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"]
                let participantsCanVoteArray_ = [false]
                let beneficiaryTypes = [0]

                let tx = await (await pact.createPact(isEditable_, pactText_, maturityTimeStamp_, votingEnabled_, particpantAddresses_, participantsCanVoteArray_, beneficiaryTypes, {value: 0})).wait()
                let resultingEvent = tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data)
                
                console.log("result: ", "\n creator: ", resultingEvent.creator, "\n uid: ", resultingEvent.uid )

                expect(resultingEvent.creator).to.eq(creator.address)
                expect(resultingEvent.uid).to.have.length(66)

                let pactCreated = await pact.getPact(resultingEvent.uid)
                console.log(pactCreated)
            })
        })
});
