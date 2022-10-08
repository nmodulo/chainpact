import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish, Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
const Signer = ethers.Signer
const BigNumber = ethers.BigNumber
const formatBytes32String = ethers.utils.formatBytes32String
let pact: Contract

let [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2]: SignerWithAddress[] = []

async function setSigners() {
    [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2] = await ethers.getSigners()
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
        let pactFactory = await ethers.getContractFactory("WordPact")
        pact = await pactFactory.deploy()
    })

    if (testCreatePact)
        describe("Create Pact", function () {
            it("Should allow creating a pact with various inputs", async function () {
                let tx = await pact.createPact()
                await tx.wait()
            })
        })
});
