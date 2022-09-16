import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
const Signer = ethers.Signer
const BigNumber = ethers.BigNumber
const formatBytes32String = ethers.utils.formatBytes32String


enum PactState {
  DEPLOYED, RETRACTED, EMPLOYER_SIGNED, EMPLOYEE_SIGNED, ALL_SIGNED, ACTIVE, PAUSED, TERMINATED, RESIGNED, END_ACCEPTED, fNf_EMPLOYER, fNf_EMPLOYEE, DISPUTED, ARBITRATED, fNf_SETTLED, DISPUTE_RESOLVED, ENDED
}


let [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2]: SignerWithAddress[] = []

async function setSigners() {
  [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2] = await ethers.getSigners()
}

// async function deployPact(args: [any, string, string, string, any]){
async function deployPact(args: [pactName: string, employee: string, employer: string, paySchedule: string, payAmount: any]) {
  let pactFactory = await ethers.getContractFactory("SimpleEmployment")
  return pactFactory.deploy(...args)
}

async function deployRandomPact() {
  await setSigners();
  let values: [string, string, string, string, any] = [ethers.utils.formatBytes32String("Pact pact"), employee.address, employer.address, "1", ethers.utils.parseUnits("1.0", "ether")]
  let tx = await deployPact(values)
  return (tx.deployed())
}

async function deployAndSignRandomPact() {
  let pact = await deployRandomPact()
  let signingDate = new Date().getTime()
  let signature = await employer.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
  let stake = (await pact.pactData()).payAmount
  await pact.employerSign(signature, signingDate, { value: stake })
  signature = await employee.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
  await pact.employeeSign(signature, signingDate)

  return pact
}

async function deployToDisputePact(suggestedAmt: BigNumberish) {
  let pact = await deployAndSignRandomPact()
  await pact.delegate([employerDelegate.address], true)
  await pact.connect(employee).delegate([employeeDelegate.address], true)
  await pact.connect(employerDelegate).start()
  await pact.connect(employerDelegate).terminate()
  await pact.connect(employerDelegate).fNf({ value: suggestedAmt })
  await pact.connect(employeeDelegate).dispute(suggestedAmt)
  return pact
}

const [testDeploy, testSigning, testPactions, testdispute] = [false, false, true, false]

describe("SimpleEmployment", function () {

  this.beforeAll(async () => {
    await setSigners()
  })

  if (testDeploy)
    describe("Deploy", function () {
      it("Should allow deploying with normal happy values", async function () {
        let tx = (await deployRandomPact())
        tx = await tx.deployed()
        expect(tx.deployTransaction.confirmations).to.be.greaterThan(0);
      })

      it("shouldn't allow 0 in payment value", async function () {
        await expect(deployPact([formatBytes32String("Test"), employer.address, employee.address, "2", BigNumber.from("0")])).to.be.be.revertedWithoutReason()
      })

      it("shouldn't allow null pact name", async function () {
        await expect(deployPact([formatBytes32String(""), employer.address, employee.address, "2", BigNumber.from("200")])).to.be.be.revertedWithoutReason()
      })

      it("shouldn't allow invalid address values in employer or employee address", async function () {
        let errorFlag = false
        try {
          await deployPact([formatBytes32String("Pactt"), "0x0", employee.address, "2", BigNumber.from("200")])
        } catch (err: any) {
          errorFlag = true
          expect(err.code).to.eq('INVALID_ARGUMENT')
        }
        expect(errorFlag).to.be.true
      })
    })

  if (testSigning)
    describe("Contract Signing", function () {
      it("should allow employer to sign first", async function () {
        let pact = await deployRandomPact()
        let signingDate = new Date().getTime()

        //Employer Signs first
        let signature = await employer.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        let stake = (await pact.pactData()).payAmount
        await pact.employerSign(signature, signingDate, { value: stake })
        let currStatus = await pact.pactState()
        expect(currStatus).to.eq(PactState.EMPLOYER_SIGNED)

        signature = await employee.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        await pact.employeeSign(signature, signingDate)
        currStatus = await pact.pactState()
        expect(currStatus).eq(PactState.ALL_SIGNED)
      })

      it("should let employee sign first", async function () {

        let pact = await deployRandomPact()
        let signingDate = new Date().getTime()
        let stake = (await pact.pactData()).payAmount

        let signature = await employee.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        await pact.employeeSign(signature, signingDate)
        let currStatus = await pact.pactState()
        expect(currStatus).eq(PactState.EMPLOYEE_SIGNED)

        signature = await employer.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        await pact.employerSign(signature, signingDate, { value: stake })
        currStatus = await pact.pactState()
        expect(currStatus).to.eq(PactState.ALL_SIGNED)
      })

      it("should not allow parties apart from employer or employee to sign", async function () {
        let pact = await deployRandomPact()
        let signingDate = new Date().getTime()
        let stake = (await pact.pactData()).payAmount

        let signature = await thirdParty.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        await expect(pact.employerSign(signature, signingDate, { value: stake })).to.be.revertedWith('Employer Sign Invalid')
      })

      it("should allow retracting offer before employee sign", async function () {
        let pact = await deployRandomPact()
        let signingDate = new Date().getTime()
        let signature = await employer.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        let stake = (await pact.pactData()).payAmount
        await pact.employerSign(signature, signingDate, { value: stake })
        await pact.retractOffer()
        expect(await pact.pactState()).to.eq(PactState.RETRACTED)

      })

    })

  if (testPactions)
    describe("Pact Actions", function () {
      it("should allow starting a pact", async function () {
        let pact = await deployAndSignRandomPact()
        await expect(pact.connect(employee).start()).to.be.revertedWith("employer delegate only")
        await pact.delegate([thirdParty.address], true)
        await pact.connect(thirdParty).start()
      })
      it("should not allow starting unless all signed", async function () {
        let pact = await deployRandomPact()
        await expect(pact.start()).to.be.revertedWithoutReason()
      })
      it("should not allow starting if status is active or beyond", async function () {
        let pact = await deployAndSignRandomPact()
        await pact.start()
        await expect(pact.start()).to.be.revertedWithoutReason()
      })
      it("should record last Payment Made, and let withdraw", async function () {
        let pact = await deployAndSignRandomPact()
        await pact.start()
        let availableBefore = await pact.availableToWithdraw()
        let payAmount = (await pact.pactData()).payAmount
        await pact.approvePayment({ value: payAmount })
        expect(availableBefore.add(payAmount)).to.eq(await pact.availableToWithdraw())
        let lastPayment = await pact.lastPaymentMade()
        expect(lastPayment.timeStamp).to.eq((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp)
        expect(lastPayment.amount).to.eq(payAmount)

        let balanceBefore = await ethers.provider.getBalance(employee.address)
        let txReceipt = await (await pact.connect(employee).withdrawPayment(payAmount.div(2))).wait()
        expect(balanceBefore.add(payAmount.div(2))).to.eq(
          (await ethers.provider.getBalance(employee.address))
            .add(txReceipt.cumulativeGasUsed.mul(txReceipt.effectiveGasPrice)))
      })
      it("should not allow pay on non-active pact", async function () {
        let pact = await deployAndSignRandomPact()
        let balanceBefore = await employee.getBalance()
        let payAmount = (await pact.pactData()).payAmount
        await expect(pact.approvePayment({ value: payAmount })).to.be.revertedWith("not active")
        expect(balanceBefore).to.eq((await employee.getBalance()))
      })

      it("should allow pausing and unpausing", async function () {
        let pact = await deployAndSignRandomPact()
        await pact.start()
        await pact.pause()
        await pact.resume()
        await pact.pause()
        let payAmount = (await pact.pactData()).payAmount
        await expect(pact.approvePayment({ value: payAmount })).to.be.revertedWith("not active")
        await expect(pact.connect(thirdParty).resume()).to.be.revertedWith('only parties')
      })

      it("should not allow delegating before core parties have signed", async function () {
        let pact = await deployRandomPact()
        await expect(pact.delegate([thirdParty.address], true)).to.be.revertedWithoutReason()
      })
      it("should allow terminating active pact", async function () {
        let pact = await deployAndSignRandomPact()
        await pact.start()
        await pact.terminate()
        expect(await pact.pactState()).to.eq(PactState.TERMINATED)
      })
      it("should not allow terminating non-active part", async function () {
        let pact = await deployAndSignRandomPact()
        await expect(pact.terminate()).to.be.revertedWith("not active")
      })

      it("should refund the correct amount after terminating", async function () {
        let pact = await deployAndSignRandomPact()
        await pact.start()
        let startTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
        // await sleep(1000)
        await pact.pause()
        let pauseTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
        await pact.resume()
        let resumeTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp

        let balanceBefore = await employer.getBalance()
        let tx = await pact.terminate()
        let receipt = await tx.wait()
        let terminateTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
        let balanceAfter = await employer.getBalance()
        let expectedRefund = BigNumber.from(0)
        let activeTime = (pauseTime - startTime) + (terminateTime - resumeTime)
        let payAmount = (await pact.pactData()).payAmount
        let payScheduleMs = (await pact.pactData()).payScheduleDays.mul(86400 * 1000) // days in ms

        expectedRefund = payAmount.sub((payAmount.mul(activeTime)).div(payScheduleMs))

        expect((balanceAfter).sub(balanceBefore).eq(expectedRefund.sub(receipt.gasUsed.mul(receipt.effectiveGasPrice)))).to.be.true
      })

      it("should allow resigning and accept resign on active pact", async function () {
        let pact = await deployAndSignRandomPact()

        await expect(pact.connect(employee).resign()).to.be.reverted
        await pact.start()

        await pact.connect(employee).resign()
        expect(await pact.pactState()).to.eq(PactState.RESIGNED)
        await pact.approveResign()
        expect(await pact.pactState()).to.eq(PactState.END_ACCEPTED)

        await pact.fNf()
        expect(await pact.pactState()).to.eq(PactState.fNf_EMPLOYER)

        await pact.connect(employee).fNf()
        expect(await pact.pactState()).to.eq(PactState.fNf_SETTLED)

        let balanceBefore = await employer.getBalance()
        let stakeAmount = await pact.stakeAmount()
        let tx = await pact.reclaimStake(employer.address)
        await expect(tx).to.not.be.reverted

        let receipt = await tx.wait()
        let expectedBalance = balanceBefore.add(stakeAmount).sub(receipt.gasUsed.mul(receipt.effectiveGasPrice))
        expect(await employer.getBalance()).to.eq(expectedBalance)
        expect(await pact.pactState()).to.eq(PactState.ENDED)
      })
    })

  if (testdispute)
    describe("Dispute", function () {
      it("should allow employee to raise a dispute on terminate and fNf", async function () {
        let pact = await deployAndSignRandomPact()
        await pact.delegate([employerDelegate.address], true)
        await pact.connect(employee).delegate([employeeDelegate.address], true)
        await pact.connect(employerDelegate).start()

        await pact.connect(employerDelegate).terminate()
        expect(await pact.pactState()).to.eq(PactState.TERMINATED)

        let suggestedAmt = ethers.utils.parseUnits("0.1", "ether")
        await expect(pact.connect(employerDelegate).dispute(suggestedAmt)).to.be.revertedWith("employee delegate only")
        await expect(pact.connect(employer).dispute(suggestedAmt)).to.be.revertedWith("employee delegate only")
        await expect(pact.connect(employeeDelegate).dispute(suggestedAmt)).to.be.revertedWithoutReason()
        expect(await pact.pactState()).to.eq(PactState.TERMINATED)

        pact = await deployAndSignRandomPact()
        await pact.delegate([employerDelegate.address], true)
        await pact.connect(employee).delegate([employeeDelegate.address], true)
        await pact.connect(employerDelegate).start()
        await pact.connect(employerDelegate).terminate()
        await pact.connect(employerDelegate).fNf({ value: suggestedAmt })
        expect(await pact.pactState()).to.eq(PactState.fNf_EMPLOYER)
        await pact.connect(employeeDelegate).dispute(suggestedAmt)
        expect(await pact.pactState()).to.eq(PactState.DISPUTED)

      })


      it("should not allow employer to reclaim, pay, destroy, sign when disputed", async function () {
        let suggestedAmt = BigNumber.from(100)
        let pact = await deployToDisputePact(suggestedAmt)
        await expect(pact.reclaimStake(employer.address)).to.be.reverted
        await expect(pact.destroy()).to.be.reverted

        let signingDate = new Date().getTime()
        let signature = await employer.signMessage(ethers.utils.arrayify(await pact.contractDataHash(signingDate)))
        let stake = (await pact.pactData()).payAmount
        await expect(pact.employerSign(signature, signingDate, { value: stake })).to.be.reverted

      })

      it("should not allow adding arbitrators after arbitrators accepted", async function () {
        let suggestedAmt = BigNumber.from(100)
        let pact = await deployToDisputePact(suggestedAmt)
        await pact.connect(employee).proposeArbitrators([arbitrator1.address])
        await pact.connect(employer).acceptOrRejectArbitrators(true)
        await expect(pact.connect(employee).proposeArbitrators([arbitrator2.address])).to.be.reverted

        await pact.acceptOrRejectArbitrators(false)
        await expect(pact.connect(employee).proposeArbitrators([arbitrator2.address])).to.not.be.reverted
      })
      it("should correctly perform arbitration", async function () {
        let suggestedAmt = BigNumber.from(100)
        let pact = await deployToDisputePact(suggestedAmt)
        await pact.connect(employee).proposeArbitrators([arbitrator1.address, arbitrator2.address])
        await pact.connect(employer).acceptOrRejectArbitrators(true)
        expect(await pact.pactState()).to.eq(PactState.ARBITRATED)

        await pact.connect(thirdParty).arbitratorResolve()
        expect(await pact.pactState()).to.eq(PactState.ARBITRATED)

        await expect(await pact.connect(arbitrator1).arbitratorResolve()).to.not.be.reverted
        expect(await pact.pactState()).to.eq(PactState.ARBITRATED)
        await expect(pact.reclaimStake(employer.address)).to.be.reverted

        await expect(await pact.connect(arbitrator2).arbitratorResolve()).to.not.be.reverted
        expect(await pact.pactState()).to.eq(PactState.DISPUTE_RESOLVED)

        await expect(pact.connect(employee).dispute(suggestedAmt)).to.be.reverted

        let balanceBefore = await employer.getBalance()
        let stakeAmount = await pact.stakeAmount()
        let tx = await pact.reclaimStake(employer.address)
        await expect(tx).to.not.be.reverted

        let receipt = await tx.wait()
        let expectedBalance = balanceBefore.add(stakeAmount).sub(receipt.gasUsed.mul(receipt.effectiveGasPrice))
        expect(await employer.getBalance()).to.eq(expectedBalance)
        expect(await pact.pactState()).to.eq(PactState.ENDED)

        await expect(pact.connect(employee).dispute(suggestedAmt)).to.be.reverted
      })
      it("should allow fNf to both parties during arbitration and no dispute", async function () {
        let suggestedAmt = BigNumber.from(100)
        let pact = await deployToDisputePact(suggestedAmt)
        await pact.connect(employee).proposeArbitrators([arbitrator1.address, arbitrator2.address])
        await pact.connect(employer).acceptOrRejectArbitrators(true)
        expect(await pact.pactState()).to.eq(PactState.ARBITRATED)
        await expect(await pact.fNf({ value: 100 })).to.not.be.reverted
        await expect(await pact.connect(employee).fNf({ value: 100 })).to.not.be.reverted
      })
    })
});
