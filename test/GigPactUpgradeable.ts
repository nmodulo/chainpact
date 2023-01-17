import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { GigPactUpgradeable, GigPactUpgradeable__factory, PactSignature, PactSignature__factory, DisputeHelper__factory, PaymentHelper__factory, PaymentHelper, IERC20__factory, ERC20__factory, ERC20PresetFixedSupply__factory, ERC20PresetFixedSupply } from "../typechain-types";
import { DisputeHelper } from "../typechain-types/contracts/GigPactUpgradeable/libraries/DisputeHelper";
import { ERC20, IERC20 } from "../typechain-types/@openzeppelin/contracts/token/ERC20";
import { erc20 } from "../typechain-types/factories/@openzeppelin/contracts/token";
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";

const Signer = ethers.Signer
const BigNumber = ethers.BigNumber
const formatBytes32String = ethers.utils.formatBytes32String
let pact: GigPactUpgradeable
let pactSigLib: PactSignature
let disputeHelperLib: DisputeHelper
let payHelperLib: PaymentHelper
let erc20Contract: ERC20PresetFixedSupply
enum PactState {
  DEPLOYED,
  RETRACTED,
  EMPLOYER_SIGNED,
  EMPLOYEE_SIGNED,
  ALL_SIGNED,
  ACTIVE,
  PAUSED,
  TERMINATED,
  RESIGNED,
  FNF_EMPLOYER,
  FNF_EMPLOYEE,
  DISPUTED,
  ARBITRATED,
  FNF_SETTLED,
  DISPUTE_RESOLVED,
  ENDED
}


let [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2]: SignerWithAddress[] = []

async function setSigners() {
  [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2] = await ethers.getSigners()
}

let defaultValues = {
  erc20TokenAddress: "0x0000000000000000000000000000000000000000",
  pactName: "Test Gig",
  employee: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  employer: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  payScheduleDays: 1,
  payAmount: ethers.utils.parseEther("1"),
}

async function createNewPact(
  erc20TokenAddress = defaultValues.erc20TokenAddress,
  pactName = defaultValues.pactName,
  employee = defaultValues.employee,
  employer = defaultValues.employer,
  payScheduleDays = defaultValues.payScheduleDays,
  payAmount = defaultValues.payAmount,
) {
  let tx = await (await pact.createPact(ethers.utils.formatBytes32String(pactName), employee, employer, payScheduleDays, payAmount, erc20TokenAddress)).wait()
  let resultingEvent = tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data)
  return { resultingEvent, tx }
}

async function createAndSignRandomPact( erc20TokenAddress = "0x0000000000000000000000000000000000000000",
) {
  let { resultingEvent } = await createNewPact(erc20TokenAddress)
  let signingDate = new Date().getTime()
  let pactData = await pact.getAllPactData(resultingEvent.pactid)
  let messageToSgin = ethers.utils.arrayify(
    await pactSigLib.contractDataHash(
      pactData[0].pactName,
      resultingEvent.pactid,
      pactData[0].employee,
      pactData[0].employer,
      pactData[0].payScheduleDays,
      pactData[0].payAmount,
      signingDate)
  )
  let signature = await employer.signMessage(
    messageToSgin
  )
  let stake = (await pact.getAllPactData(resultingEvent.pactid))[0].payAmount
  await pact.signPact(resultingEvent.pactid, signature, signingDate, { value: stake })
  signature = await employee.signMessage(messageToSgin)
  await pact.connect(employee).signPact(resultingEvent.pactid, signature, signingDate)

  return { resultingEvent }
}

async function deployToDisputePact(suggestedAmt: BigNumberish) {
  let {resultingEvent} = await createAndSignRandomPact()
  await pact.delegatePact(resultingEvent.pactid, [employerDelegate.address], true)
  await pact.connect(employee).delegatePact(resultingEvent.pactid, [employeeDelegate.address], true)
  await pact.connect(employerDelegate).startPause(resultingEvent.pactid, true)
  await pact.connect(employerDelegate).terminate(resultingEvent.pactid)
  await pact.connect(employerDelegate).fNf(resultingEvent.pactid, 0, { value: suggestedAmt })
  await pact.connect(employeeDelegate).dispute(resultingEvent.pactid, suggestedAmt)
  return {resultingEvent}
}

const [testCreate, testSigning, testPactions, testdispute, testErc] = [false, false, false, false, true]

describe("Gig Pact Test", function () {

  this.beforeAll(async () => {
    await setSigners()
    
    let pactSigFactory: PactSignature__factory = await ethers.getContractFactory("PactSignature")
    pactSigLib = await pactSigFactory.deploy()
    pactSigLib = await pactSigLib.deployed()
    
    let disputeHelperFactory: DisputeHelper__factory = await ethers.getContractFactory("DisputeHelper")
    disputeHelperLib = await disputeHelperFactory.deploy()
    disputeHelperLib = await disputeHelperLib.deployed()

    let paymentHelperFactory: PaymentHelper__factory = await ethers.getContractFactory("PaymentHelper")
    payHelperLib = await paymentHelperFactory.deploy()
    payHelperLib = await payHelperLib.deployed()

    let erc20factory: ERC20PresetFixedSupply__factory = await ethers.getContractFactory("ERC20PresetFixedSupply")
    erc20Contract = await erc20factory.deploy('USDN', 'USDN', parseEther("1000"), employer.address)
    erc20Contract = await erc20Contract.deployed()
    
    
    let pactFactory: GigPactUpgradeable__factory = await ethers.getContractFactory("GigPactUpgradeable", {
      libraries: {
        PactSignature: pactSigLib.address,
        DisputeHelper: disputeHelperLib.address,
        PaymentHelper: payHelperLib.address
      }
    })
    pact = await pactFactory.deploy()
    pact = await pact.deployed()
    await erc20Contract.approve(pact.address, parseEther("500"))
  })

  if (testCreate)
    describe("Create", function () {
      it("Should allow creating a gig pact with normal happy values", async function () {
        let { resultingEvent } = await createNewPact()
        expect(resultingEvent.pactid).to.have.length(66)
      })

      it("shouldn't allow 0 in payment value", async function () {
        await expect(createNewPact("0x0000000000000000000000000000000000000000", "Test", employer.address, employee.address, 2, BigNumber.from("0"))).to.be.reverted
      })

      it("shouldn't allow null pact name", async function () {
        await expect(createNewPact("0x0000000000000000000000000000000000000000", "", employer.address, employee.address, 2, BigNumber.from("200"))).to.be.reverted
      })

      it("shouldn't allow invalid address values in employer or employee address", async function () {
        let errorFlag = false
        try {
          await createNewPact("0x0000000000000000000000000000000000000000","Pactt", "0x0", employee.address, 2, BigNumber.from("200"))
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
        let { resultingEvent } = await createNewPact()
        let signingDate = new Date().getTime()
        let pactData = await pact.getAllPactData(resultingEvent.pactid)
        let contractDataHash = await pactSigLib.contractDataHash(
          pactData[0].pactName.toLowerCase(),
          resultingEvent.pactid,
          pactData[0].employee.toLowerCase(),
          pactData[0].employer.toLowerCase(),
          pactData[0].payScheduleDays,
          pactData[0].payAmount.toHexString(),
          signingDate)
        let messageToSign = ethers.utils.arrayify(contractDataHash)
        //Employer Signs first
        let signature = await employer.signMessage(messageToSign)
        await pact.connect(employer).signPact(resultingEvent.pactid, signature, signingDate, { value: pactData[0].payAmount })
        let currStatus = (await pact.getAllPactData(resultingEvent.pactid))[0].pactState
        expect(currStatus).to.eq(PactState.EMPLOYER_SIGNED)

        signature = await employee.signMessage(messageToSign)

        await pact.connect(employee).signPact(resultingEvent.pactid, signature, signingDate)
        currStatus = (await pact.getAllPactData(resultingEvent.pactid))[0].pactState
        expect(currStatus).eq(PactState.ALL_SIGNED)
      })

      it("should let employee sign first", async function () {
        let { resultingEvent } = await createNewPact()
        let signingDate = new Date().getTime()
        let pactData = await pact.getAllPactData(resultingEvent.pactid)
        let contractDataHash = await pactSigLib.contractDataHash(
          pactData[0].pactName.toLowerCase(),
          resultingEvent.pactid,
          pactData[0].employee.toLowerCase(),
          pactData[0].employer.toLowerCase(),
          pactData[0].payScheduleDays,
          pactData[0].payAmount.toHexString(),
          signingDate)
        let messageToSign = ethers.utils.arrayify(contractDataHash)

        //Employee Signs first
        let signature = await employee.signMessage(messageToSign)
        await pact.connect(employee).signPact(resultingEvent.pactid, signature, signingDate)
        let currStatus = (await pact.getAllPactData(resultingEvent.pactid))[0].pactState
        expect(currStatus).to.eq(PactState.EMPLOYEE_SIGNED)

        signature = await employer.signMessage(messageToSign)
        await pact.connect(employer).signPact(resultingEvent.pactid, signature, signingDate, { value: pactData[0].payAmount })
        currStatus = (await pact.getAllPactData(resultingEvent.pactid))[0].pactState
        expect(currStatus).to.eq(PactState.ALL_SIGNED)
      })

      it("should not allow parties apart from employer or employee to sign", async function () {
        let { resultingEvent } = await createNewPact()
        let signingDate = new Date().getTime()
        let pactData = await pact.getAllPactData(resultingEvent.pactid)

        let contractDataHash = await pactSigLib.contractDataHash(
          pactData[0].pactName.toLowerCase(),
          resultingEvent.pactid,
          pactData[0].employee.toLowerCase(),
          pactData[0].employer.toLowerCase(),
          pactData[0].payScheduleDays,
          pactData[0].payAmount.toHexString(),
          signingDate)
        let messageToSign = ethers.utils.arrayify(contractDataHash)

        let signature = await thirdParty.signMessage(messageToSign)

        await expect(pact.connect(thirdParty).signPact(resultingEvent.pactid, signature, signingDate, { value: pactData[0].payAmount })).to.be.revertedWith('Unauthorized')
        await expect(pact.connect(thirdParty).signPact(resultingEvent.pactid, signature, signingDate)).to.be.revertedWith('Unauthorized')
      })

      it("should allow retracting offer before employee sign", async function () {
        let { resultingEvent } = await createNewPact()
        let signingDate = new Date().getTime()
        let pactData = await pact.getAllPactData(resultingEvent.pactid)
        let contractDataHash = await pactSigLib.contractDataHash(
          pactData[0].pactName.toLowerCase(),
          resultingEvent.pactid,
          pactData[0].employee.toLowerCase(),
          pactData[0].employer.toLowerCase(),
          pactData[0].payScheduleDays,
          pactData[0].payAmount.toHexString(),
          signingDate)
        let messageToSign = ethers.utils.arrayify(contractDataHash)
        //Employer Signs first
        let signature = await employer.signMessage(messageToSign)
        await pact.connect(employer).signPact(resultingEvent.pactid, signature, signingDate, { value: pactData[0].payAmount })
        let currStatus = (await pact.getAllPactData(resultingEvent.pactid))[0].pactState
        expect(currStatus).to.eq(PactState.EMPLOYER_SIGNED)
        await pact.reclaimStake(resultingEvent.pactid, employer.address)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.RETRACTED)
      })

    })

  if (testPactions)
    describe("Pact Actions", function () {
      it("should allow starting a pact", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await expect(pact.connect(employee).startPause(resultingEvent.pactid, true)).to.be.revertedWith("employer delegate only")
        await pact.delegatePact(resultingEvent.pactid, [thirdParty.address], true)
        await pact.connect(thirdParty).startPause(resultingEvent.pactid, true)
      })

      it("should not allow starting unless all signed", async function () {
        let { resultingEvent } = await createNewPact()
        await expect(pact.startPause(resultingEvent.pactid, true)).to.be.reverted
      })

      it("should not allow starting if status is active or beyond", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await pact.startPause(resultingEvent.pactid, true)
        await expect(pact.startPause(resultingEvent.pactid, true)).to.be.reverted
      })

      it("should record last Payment Made, and let withdraw", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await pact.startPause(resultingEvent.pactid, true)
        let pactData = (await pact.getAllPactData(resultingEvent.pactid))

        let balanceBefore = await ethers.provider.getBalance(employee.address)
        // let availableBefore = pactData[1].availableToWithdraw
        await pact.approvePayment(resultingEvent.pactid, { value: pactData[0].payAmount })

        pactData = (await pact.getAllPactData(resultingEvent.pactid))
        // expect(availableBefore.add(payAmount)).to.eq(pactData[1].availableToWithdraw)
        expect(pactData[1].lastPayTimeStamp).to.eq((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp)
        expect(pactData[1].lastPayAmount).to.eq(pactData[0].payAmount)
        expect(balanceBefore.add(pactData[0].payAmount)).to.eq(await ethers.provider.getBalance(pactData[0].employee))

        // let txReceipt = await (await pact.connect(employee).withdrawPayment(resultingEvent.pactid, payAmount.div(2))).wait()
        // expect(balanceBefore.add(payAmount.div(2))).to.eq(
        //   (await ethers.provider.getBalance(employee.address))
        //     .add(txReceipt.cumulativeGasUsed.mul(txReceipt.effectiveGasPrice)))

      })

      it("should not allow pay on non-active pact", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        let balanceBefore = await employee.getBalance()
        let payAmount = (await pact.getAllPactData(resultingEvent.pactid))[0].payAmount
        await expect(pact.approvePayment(resultingEvent.pactid, { value: payAmount })).to.be.revertedWith("not active")
        expect(balanceBefore).to.eq((await employee.getBalance()))
      })

      it("should allow pausing and unpausing", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await pact.startPause(resultingEvent.pactid, true)
        await pact.startPause(resultingEvent.pactid, false)
        await pact.startPause(resultingEvent.pactid, true)
        await pact.startPause(resultingEvent.pactid, false)
        let payAmount = (await pact.getAllPactData(resultingEvent.pactid))[0].payAmount
        await expect(pact.approvePayment(resultingEvent.pactid, { value: payAmount })).to.be.revertedWith("not active")
        await expect(pact.connect(thirdParty).startPause(resultingEvent.pactid, true)).to.be.revertedWith('employer delegate only')
      })

      it("should not allow delegating before core parties have signed", async function () {
        let { resultingEvent } = await createNewPact()
        await expect(pact.delegatePact(resultingEvent.pactid, [thirdParty.address], true)).to.be.revertedWithoutReason()
      })
      it("should allow terminating active pact", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await pact.startPause(resultingEvent.pactid, true)
        await pact.terminate(resultingEvent.pactid)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.TERMINATED)
      })
      it("should not allow terminating non-active part", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await expect(pact.terminate(resultingEvent.pactid)).to.be.revertedWith("not active")
      })

      it("should refund the correct amount after terminating", async function () {
        let { resultingEvent } = await createAndSignRandomPact()
        await pact.startPause(resultingEvent.pactid, true)
        let startTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
        // await sleep(1000)
        await pact.startPause(resultingEvent.pactid, false)
        let pauseTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
        await pact.startPause(resultingEvent.pactid, true)
        let resumeTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp

        let balanceBefore = await employer.getBalance()


        let tx = await pact.terminate(resultingEvent.pactid)
        let receipt = await tx.wait()

        let terminateTime = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp


        let balanceAfter = await employer.getBalance()
        let expectedRefund = BigNumber.from(0)
        let activeTime = (pauseTime - startTime) + (terminateTime - resumeTime)

        let pactData = await pact.getAllPactData(resultingEvent.pactid)
        let payAmount = pactData[0].payAmount
        let payScheduleMs = pactData[0].payScheduleDays * (86400) // days in ms

        expectedRefund = payAmount.sub((payAmount.mul(activeTime)).div(payScheduleMs))

        expect((balanceAfter).sub(balanceBefore)).to.eq(expectedRefund.sub(receipt.gasUsed.mul(receipt.effectiveGasPrice)))
      })

      it("should allow resigning and accept resign on active pact", async function () {
        let { resultingEvent } = await createAndSignRandomPact()

        await expect(pact.connect(employee).terminate(resultingEvent.pactid)).to.be.reverted
        await pact.startPause(resultingEvent.pactid, true)

        await pact.connect(employee).terminate(resultingEvent.pactid)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.RESIGNED)

        await pact.connect(employer).fNf(resultingEvent.pactid, 0)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.FNF_EMPLOYER)

        await pact.connect(employee).fNf(resultingEvent.pactid, 0)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.FNF_SETTLED)

        let balanceBefore = await employer.getBalance()
        let stakeAmount = (await pact.getAllPactData(resultingEvent.pactid))[0].stakeAmount
        let tx = await pact.reclaimStake(resultingEvent.pactid, employer.address)
        await expect(tx).to.not.be.reverted

        let receipt = await tx.wait()
        let expectedBalance = balanceBefore.add(stakeAmount).sub(receipt.gasUsed.mul(receipt.effectiveGasPrice))
        expect(await employer.getBalance()).to.eq(expectedBalance)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.ENDED)
      })
    })

  if (testdispute)
    describe("Dispute", function () {
      it("should allow employee to raise a dispute on terminate and fNf", async function () {
        let {resultingEvent} = await createAndSignRandomPact()
        await pact.delegatePact(resultingEvent.pactid, [employerDelegate.address], true)
        await pact.connect(employee).delegatePact(resultingEvent.pactid, [employeeDelegate.address], true)
        await pact.connect(employerDelegate).startPause(resultingEvent.pactid, true)

        await pact.connect(employerDelegate).terminate(resultingEvent.pactid)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.TERMINATED)

        let suggestedAmt = ethers.utils.parseUnits("0.1", "ether")
        await expect(pact.connect(employerDelegate).dispute(resultingEvent.pactid, suggestedAmt)).to.be.revertedWith("employee delegate only")
        await expect(pact.connect(employer).dispute(resultingEvent.pactid, suggestedAmt)).to.be.revertedWith("employee delegate only")
        await expect(pact.connect(employeeDelegate).dispute(resultingEvent.pactid, suggestedAmt)).to.be.revertedWithoutReason()
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.TERMINATED)

        resultingEvent = (await createAndSignRandomPact()).resultingEvent
        await pact.delegatePact(resultingEvent.pactid, [employerDelegate.address], true)
        await pact.connect(employee).delegatePact(resultingEvent.pactid, [employeeDelegate.address], true)
        await pact.connect(employerDelegate).startPause(resultingEvent.pactid, true)
        await pact.connect(employerDelegate).terminate(resultingEvent.pactid)
        await pact.connect(employerDelegate).fNf(resultingEvent.pactid, 0, { value: suggestedAmt })
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.FNF_EMPLOYER)
        await pact.connect(employeeDelegate).dispute(resultingEvent.pactid, suggestedAmt)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.DISPUTED)

      })


      it("should not allow employer to reclaim, pay, destroy, sign when disputed", async function () {
        let suggestedAmt = BigNumber.from(100)
        let {resultingEvent} = await deployToDisputePact(suggestedAmt)
        await expect(pact.reclaimStake(resultingEvent.pactid, employer.address)).to.be.reverted
      })

      it("should not allow adding arbitrators after arbitrators accepted", async function () {
        let suggestedAmt = BigNumber.from(100)
        let {resultingEvent} = await deployToDisputePact(suggestedAmt)
        await pact.connect(employee).proposeArbitrators(resultingEvent.pactid, [arbitrator1.address])
        await pact.connect(employer).acceptOrRejectArbitrators(resultingEvent.pactid, true)


        resultingEvent = (await deployToDisputePact(suggestedAmt)).resultingEvent
        await expect(await pact.connect(employee).proposeArbitrators(resultingEvent.pactid, [arbitrator2.address])).to.not.be.reverted
        await expect( await pact.connect(employer).acceptOrRejectArbitrators(resultingEvent.pactid,false)).to.not.be.reverted
        await expect(pact.connect(employee).proposeArbitrators(resultingEvent.pactid,[arbitrator2.address])).to.not.be.reverted
      })

      it("should correctly perform arbitration", async function () {
        let suggestedAmt = BigNumber.from(100)
        let {resultingEvent} = await deployToDisputePact(suggestedAmt)
        await pact.connect(employee).proposeArbitrators(resultingEvent.pactid,[arbitrator1.address, arbitrator2.address])
        await pact.connect(employer).acceptOrRejectArbitrators(resultingEvent.pactid,true)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.ARBITRATED)

        await pact.connect(thirdParty).arbitratorResolve(resultingEvent.pactid,)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.ARBITRATED)

        await expect(await pact.connect(arbitrator1).arbitratorResolve(resultingEvent.pactid)).to.not.be.reverted
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.ARBITRATED)
        await expect(pact.reclaimStake(resultingEvent.pactid,employer.address)).to.be.reverted

        await expect(await pact.connect(arbitrator2).arbitratorResolve(resultingEvent.pactid,)).to.not.be.reverted
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.DISPUTE_RESOLVED)

        await expect(pact.connect(employee).dispute(resultingEvent.pactid,suggestedAmt)).to.be.reverted

        let balanceBefore = await employer.getBalance()
        let stakeAmount = (await pact.getAllPactData(resultingEvent.pactid))[0].stakeAmount
        let tx = await pact.reclaimStake(resultingEvent.pactid,employer.address)
        await expect(tx).to.not.be.reverted

        let receipt = await tx.wait()
        let expectedBalance = balanceBefore.add(stakeAmount).sub(receipt.gasUsed.mul(receipt.effectiveGasPrice))
        expect(await employer.getBalance()).to.eq(expectedBalance)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.ENDED)

        await expect(pact.connect(employee).dispute(resultingEvent.pactid, suggestedAmt)).to.be.reverted
      })
      it("should allow fNf to both parties during arbitration and no dispute", async function () {
        let suggestedAmt = BigNumber.from(100)
        let {resultingEvent} = await deployToDisputePact(suggestedAmt)
        await pact.connect(employee).proposeArbitrators(resultingEvent.pactid,[arbitrator1.address, arbitrator2.address])
        await pact.connect(employer).acceptOrRejectArbitrators(resultingEvent.pactid, true)
        expect((await pact.getAllPactData(resultingEvent.pactid))[0].pactState).to.eq(PactState.ARBITRATED)
        await expect(await pact.fNf(resultingEvent.pactid, 0, { value: 100 })).to.not.be.reverted
        await expect(await pact.connect(employee).fNf(resultingEvent.pactid, 0, { value: 100 })).to.not.be.reverted
      })
    })
  
  if(testErc)
  describe("ERC", function() {
    it("should allow creating, signing, reclaim pact with erc20", async function () {
      let tokensToLock = parseEther("10")
      let tokenBalanceBefore = await erc20Contract.balanceOf(employer.address)
      let { resultingEvent } = await createNewPact(erc20Contract.address,
        "Test ERC", employee.address, employer.address, 7, tokensToLock
      )
      expect(resultingEvent.pactid).to.have.length(66)
      let signingDate = new Date().getTime()
        let pactData = await pact.getAllPactData(resultingEvent.pactid)
        let contractDataHash = await pactSigLib.contractDataHash(
          pactData[0].pactName.toLowerCase(),
          resultingEvent.pactid,
          pactData[0].employee.toLowerCase(),
          pactData[0].employer.toLowerCase(),
          pactData[0].payScheduleDays,
          pactData[0].payAmount.toHexString(),
          signingDate)
        let messageToSign = ethers.utils.arrayify(contractDataHash)
        //Employer Signs first
        let signature = await employer.signMessage(messageToSign)
        await pact.connect(employer).signPact(resultingEvent.pactid, signature, signingDate)

        pactData = await pact.getAllPactData(resultingEvent.pactid)
        expect(pactData[0].pactState).to.eq(PactState.EMPLOYER_SIGNED)
        expect(pactData[0].stakeAmount).to.eq(tokensToLock)
        expect(await erc20Contract.balanceOf(employer.address)).to.eq(tokenBalanceBefore.sub(tokensToLock))
        
        await pact.reclaimStake(resultingEvent.pactid, employer.address)
        pactData = await pact.getAllPactData(resultingEvent.pactid)
        expect(pactData[0].pactState).to.eq(PactState.RETRACTED)
        expect(await  erc20Contract.balanceOf(employer.address)).to.eq(tokenBalanceBefore)
    })

    it("should allow payment, terminate, fnf with amount, reclaim with erc20", async function () {
      let {resultingEvent} = await createAndSignRandomPact(erc20Contract.address)
      expect(resultingEvent.pactid).to.have.length(66)
      await pact.startPause(resultingEvent.pactid, true)
      let pactData = await pact.getAllPactData(resultingEvent.pactid)
      expect(pactData[0].pactState).to.eq(PactState.ACTIVE)

      let employeeTokenBalance = await erc20Contract.balanceOf(employee.address)
      await pact.approvePayment(resultingEvent.pactid)
      pactData = await pact.getAllPactData(resultingEvent.pactid)
      employeeTokenBalance = employeeTokenBalance.add(defaultValues.payAmount)
      expect(employeeTokenBalance).to.eq(await erc20Contract.balanceOf(employee.address))
      expect(pactData[1].lastPayAmount).to.eq(defaultValues.payAmount)

      await pact.terminate(resultingEvent.pactid)
      pactData = await pact.getAllPactData(resultingEvent.pactid)
      expect(pactData[0].pactState).to.eq(PactState.TERMINATED)


      await pact.fNf(resultingEvent.pactid, defaultValues.payAmount)
      employeeTokenBalance = employeeTokenBalance.add(defaultValues.payAmount)
      expect(employeeTokenBalance).to.eq(await erc20Contract.balanceOf(employee.address))
      pactData = await pact.getAllPactData(resultingEvent.pactid)
      expect(pactData[0].pactState).to.eq(PactState.FNF_EMPLOYER)

      let employerTokenBalance = await erc20Contract.balanceOf(employer.address)
      await erc20Contract.connect(employee).approve(pact.address, defaultValues.payAmount)
      await pact.connect(employee).fNf(resultingEvent.pactid, defaultValues.payAmount)
      employerTokenBalance = employerTokenBalance.add(defaultValues.payAmount)
      expect(employerTokenBalance).to.eq(await erc20Contract.balanceOf(employer.address))
      pactData = await pact.getAllPactData(resultingEvent.pactid)
      expect(pactData[0].pactState).to.eq(PactState.FNF_SETTLED)

      employerTokenBalance = await erc20Contract.balanceOf(employer.address)
      await pact.reclaimStake(resultingEvent.pactid, employer.address)
      employerTokenBalance = employerTokenBalance.add(pactData[0].stakeAmount)
      expect(employerTokenBalance).to.eq(await erc20Contract.balanceOf(employer.address))
      pactData = await pact.getAllPactData(resultingEvent.pactid)
      expect(pactData[0].pactState).to.eq(PactState.ENDED)

    })

    it("should allow disputing, resolving with erc20", async function () {
      
    })
  })
});
