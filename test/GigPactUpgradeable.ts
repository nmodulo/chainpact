import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { BigNumberish, utils } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  GigPactUpgradeable,
  GigPactUpgradeable__factory,
  PactSignature,
  PactSignature__factory,
  DisputeHelper,
  DisputeHelper__factory,
  PaymentHelper__factory,
  PaymentHelper,
  IERC20__factory,
  ERC20__factory,
  ERC20PresetFixedSupply__factory,
  ERC20PresetFixedSupply,
} from "../typechain-types";
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";

const Signer = ethers.Signer;
const BigNumber = ethers.BigNumber;
const formatBytes32String = ethers.utils.formatBytes32String;
let pact: GigPactUpgradeable;
let pactSigLib: PactSignature;
let disputeHelperLib: DisputeHelper;
let payHelperLib: PaymentHelper;
let erc20Contract: ERC20PresetFixedSupply;
enum PactState {
  NULL,
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
  ENDED,
}

let [
  employer,
  employee,
  employerDelegate,
  employeeDelegate,
  thirdParty,
  arbitrator1,
  arbitrator2,
]: SignerWithAddress[] = [];

async function setSigners() {
  [
    employer,
    employee,
    employerDelegate,
    employeeDelegate,
    thirdParty,
    arbitrator1,
    arbitrator2,
  ] = await ethers.getSigners();
}

let defaultValues = {
  erc20TokenAddress: ethers.constants.AddressZero,
  pactName: "Test Gig",
  employee: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  employer: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  payScheduleDays: 1,
  payAmount: ethers.utils.parseEther("1"),
  externalDocumentHash: ethers.utils.sha256(
    ethers.utils.toUtf8Bytes("Sample text")
  ),
  commissionPercent: 2,
};

async function createNewPact(
  erc20TokenAddress = defaultValues.erc20TokenAddress,
  pactName = defaultValues.pactName,
  employee = defaultValues.employee,
  employer = defaultValues.employer,
  payScheduleDays = defaultValues.payScheduleDays,
  payAmount = defaultValues.payAmount,
  externalDocumentHash = defaultValues.externalDocumentHash
) {
  let tx = await (
    await pact.createPact(
      ethers.utils.formatBytes32String(pactName),
      employee,
      employer,
      payScheduleDays,
      payAmount,
      erc20TokenAddress,
      externalDocumentHash
    )
  ).wait();
  let resultingEvent =
    tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data);
  return { resultingEvent, tx };
}

async function createAndSignRandomPact(
  erc20TokenAddress = ethers.constants.AddressZero
) {
  let { resultingEvent } = await createNewPact(erc20TokenAddress);
  let signingDate = Math.floor(new Date().getTime() / 1000);
  let pactData = await pact.pactData(resultingEvent.pactid);
  let extDocHash = await pact.externalDocumentHash(resultingEvent.pactid);
  let messageToSgin = ethers.utils.arrayify(
    await pactSigLib.contractDataHash(
      pactData.pactName,
      resultingEvent.pactid,
      pactData.employee,
      pactData.employer,
      pactData.payScheduleDays,
      pactData.payAmount,
      pactData.erc20TokenAddress.toLowerCase(),
      extDocHash,
      signingDate
    )
  );
  let signature = await employer.signMessage(messageToSgin);
  let stake = (await pact.pactData(resultingEvent.pactid)).payAmount;
  let value = BigNumber.from(0)
  if(erc20TokenAddress === ethers.constants.AddressZero){
    value = stake.mul(100 + defaultValues.commissionPercent).div(100)
  }
  await pact.signPact(resultingEvent.pactid, signature, signingDate, {
    value,
  });
  signature = await employee.signMessage(messageToSgin);
  await pact
    .connect(employee)
    .signPact(resultingEvent.pactid, signature, signingDate);

  return { resultingEvent };
}

async function deployToDisputePact(suggestedAmt: BigNumberish) {
  let { resultingEvent } = await createAndSignRandomPact();
  await pact.delegatePact(
    resultingEvent.pactid,
    [employerDelegate.address],
    true
  );
  await pact
    .connect(employee)
    .delegatePact(resultingEvent.pactid, [employeeDelegate.address], true);
  await pact.connect(employerDelegate).startPausePact(resultingEvent.pactid, true);
  await pact.connect(employerDelegate).terminate(resultingEvent.pactid);
  await pact
    .connect(employerDelegate)
    .fNf(resultingEvent.pactid, 0, { value: suggestedAmt });
  await pact
    .connect(employeeDelegate)
    .dispute(resultingEvent.pactid, suggestedAmt);
  return { resultingEvent };
}

const [testCreate, testSigning, testPactions, testdispute, testErc, panicPause] = [
  true,
  true,
  true,
  true,
  true,
  true,
];

if (true)
  describe("Gig Pact Test", function () {
    this.beforeAll(async () => {
      await setSigners();

      let pactSigFactory: PactSignature__factory =
        await ethers.getContractFactory("PactSignature");
      pactSigLib = await pactSigFactory.deploy();
      pactSigLib = await pactSigLib.deployed();

      let disputeHelperFactory: DisputeHelper__factory =
        await ethers.getContractFactory("DisputeHelper");
      disputeHelperLib = await disputeHelperFactory.deploy();
      disputeHelperLib = await disputeHelperLib.deployed();

      let paymentHelperFactory: PaymentHelper__factory =
        await ethers.getContractFactory("PaymentHelper");
      payHelperLib = await paymentHelperFactory.deploy();
      payHelperLib = await payHelperLib.deployed();

      let erc20factory: ERC20PresetFixedSupply__factory =
        await ethers.getContractFactory("ERC20PresetFixedSupply");
      erc20Contract = await erc20factory.deploy(
        "USDN",
        "USDN",
        parseEther("1000"),
        employer.address
      );
      erc20Contract = await erc20Contract.deployed();

      let pactFactory: GigPactUpgradeable__factory =
        await ethers.getContractFactory("GigPactUpgradeable", {
          libraries: {
            PactSignature: pactSigLib.address,
            DisputeHelper: disputeHelperLib.address,
            PaymentHelper: payHelperLib.address,
          },
        });

      pact = (await upgrades.deployProxy(
        pactFactory,
        [defaultValues.commissionPercent, thirdParty.address],
        {
          unsafeAllowLinkedLibraries: true,
          initializer: "initialize",
        }
      )) as GigPactUpgradeable;
      // pact = await pactFactory.deploy()
      pact = await pact.deployed();
      // await pact.initialize(2, thirdParty.address)
      await erc20Contract.approve(pact.address, parseEther("500"));
    });

    if (testCreate)
      describe("Create", function () {
        it("Should allow creating a gig pact with normal happy values", async function () {
          let { resultingEvent } = await createNewPact();
          expect(resultingEvent.pactid).to.have.length(66);
          let pactData = await pact.pactData(resultingEvent.pactid)

          expect(pactData.pactState).to.eq(PactState.DEPLOYED)
          expect(utils.parseBytes32String(pactData.pactName)).to.eq(defaultValues.pactName)
          expect(pactData.employee).to.eq(defaultValues.employee)
          expect(pactData.payScheduleDays).to.eq(defaultValues.payScheduleDays)
          expect(pactData.employer).to.eq(defaultValues.employer)
          expect(pactData.erc20TokenAddress).to.eq(defaultValues.erc20TokenAddress)
          expect(pactData.payAmount).to.eq(defaultValues.payAmount)
          expect(pactData.payAmount).to.eq(defaultValues.payAmount)
          let pactCounter = await ethers.provider.getStorageAt(pact.address, 202)
          expect(utils.hexValue(pactCounter)).to.eq("0x1")
          expect(await pact.isEmployeeDelegate(resultingEvent.pactid, employee.address)).to.be.true
          expect(await pact.isEmployerDelegate(resultingEvent.pactid, employer.address)).to.be.true
          expect(await pact.isParty(resultingEvent.pactid, employee.address)).to.be.true
          expect(await pact.isParty(resultingEvent.pactid, employer.address)).to.be.true
        });

        it("shouldn't allow 0 as pay amount", async function () {
          await expect(
            createNewPact(
              "0x0000000000000000000000000000000000000000",
              "Test",
              employer.address,
              employee.address,
              2,
              BigNumber.from("0")
            )
          ).to.be.reverted;
        });

        it("shouldn't allow empty pact name", async function () {
          await expect(
            createNewPact(
              "0x0000000000000000000000000000000000000000",
              "",
              employer.address,
              employee.address,
              2,
              BigNumber.from("200")
            )
          ).to.be.reverted;
        });

        it("shouldn't allow invalid address values in employer or employee address", async function () {
          let errorFlag = false;
          try {
            await createNewPact(
              "0x0000000000000000000000000000000000000000",
              "Pactt",
              "0x0",
              employee.address,
              2,
              BigNumber.from("200")
            );
          } catch (err: any) {
            errorFlag = true;
            expect(err.code).to.eq("INVALID_ARGUMENT");
          }
          expect(errorFlag).to.be.true;
        });
      });

    if (testSigning)
      describe("Contract Signing", function () {
        it("should allow employer to sign first", async function () {
          let { resultingEvent } = await createNewPact();
          let signingDate = Math.floor(new Date().getTime() / 1000);
          let pactData = await pact.pactData(resultingEvent.pactid);
          let extDocHash = await pact.externalDocumentHash(
            resultingEvent.pactid
          );
          let contractDataHash = await pactSigLib.contractDataHash(
            pactData.pactName.toLowerCase(),
            resultingEvent.pactid,
            pactData.employee.toLowerCase(),
            pactData.employer.toLowerCase(),
            pactData.payScheduleDays,
            pactData.payAmount.toHexString(),
            pactData.erc20TokenAddress.toLowerCase(),
            extDocHash,
            signingDate
          );
          let messageToSign = ethers.utils.arrayify(contractDataHash);
          //Employer Signs first
          let signature = await employer.signMessage(messageToSign);

          //Send less stake
          await expect( pact
          .connect(employer)
          .signPact(resultingEvent.pactid, signature, signingDate, {
            value: pactData.payAmount
              .mul(100 + defaultValues.commissionPercent)
              .div(100).sub(1),
          })).to.be.revertedWith("Less Stake");

          let commissionBalanceBefore = await ethers.provider.getBalance(thirdParty.address)
          //Send accurate stake and a little extra
          await pact
            .connect(employer)
            .signPact(resultingEvent.pactid, signature, signingDate, {
              value: pactData.payAmount
                .mul(100 + defaultValues.commissionPercent)
                .div(100).add(1),
            });
          pactData = await pact.pactData(resultingEvent.pactid)
          let currStatus = pactData.pactState;
          expect(currStatus).to.eq(PactState.EMPLOYER_SIGNED);
          expect(pactData.stakeAmount).to.eq(pactData.payAmount.add(1))

          //Signing twice
          await expect(pact
            .connect(employer)
            .signPact(resultingEvent.pactid, signature, signingDate, {
              value: pactData.payAmount
                .mul(100 + defaultValues.commissionPercent)
                .div(100).add(1),
            })).to.be.reverted;
          
          //Check commissions in
          expect(await ethers.provider.getBalance(thirdParty.address)).to.eq(commissionBalanceBefore.add(pactData.payAmount.mul(defaultValues.commissionPercent).div(100)))

          //Employee signs
          signature = await employee.signMessage(messageToSign);
          await pact
            .connect(employee)
            .signPact(resultingEvent.pactid, signature, signingDate);
            pactData = await pact.pactData(resultingEvent.pactid)
            expect(pactData.pactState).eq(PactState.ALL_SIGNED);
            expect(pactData.employeeSignDate).to.eq(signingDate)

            //Signing twice
            await expect (pact
            .connect(employee)
            .signPact(resultingEvent.pactid, signature, signingDate)).to.be.reverted;
        });

        it("should let employee sign first", async function () {
          let { resultingEvent } = await createNewPact();
          let signingDate = Math.floor(new Date().getTime() / 1000);
          let pactData = await pact.pactData(resultingEvent.pactid);
          let contractDataHash = await pactSigLib.contractDataHash(
            pactData.pactName,
            resultingEvent.pactid,
            pactData.employee.toLowerCase(),
            pactData.employer.toLowerCase(),
            pactData.payScheduleDays,
            pactData.payAmount.toHexString(),
            pactData.erc20TokenAddress.toLowerCase(),
            defaultValues.externalDocumentHash,
            signingDate
          );
          let messageToSign = ethers.utils.arrayify(contractDataHash);

          //Employee Signs first
          let signature = await employee.signMessage(messageToSign);
          await pact
            .connect(employee)
            .signPact(resultingEvent.pactid, signature, signingDate);
          let currStatus = (await pact.pactData(resultingEvent.pactid))
            .pactState;
          expect(currStatus).to.eq(PactState.EMPLOYEE_SIGNED);

          signature = await employer.signMessage(messageToSign);
          await pact
            .connect(employer)
            .signPact(resultingEvent.pactid, signature, signingDate, {
              value: pactData.payAmount
                .mul(100 + defaultValues.commissionPercent)
                .div(100),
            });
          currStatus = (await pact.pactData(resultingEvent.pactid)).pactState;
          expect(currStatus).to.eq(PactState.ALL_SIGNED);
        });

        it("should not allow parties apart from employer or employee to sign", async function () {
          let { resultingEvent } = await createNewPact();
          let signingDate = Math.floor(new Date().getTime() / 1000);
          let pactData = await pact.pactData(resultingEvent.pactid);

          let contractDataHash = await pactSigLib.contractDataHash(
            pactData.pactName.toLowerCase(),
            resultingEvent.pactid,
            pactData.employee.toLowerCase(),
            pactData.employer.toLowerCase(),
            pactData.payScheduleDays,
            pactData.payAmount.toHexString(),
            pactData.erc20TokenAddress.toLowerCase(),
            ethers.constants.HashZero,

            signingDate
          );
          let messageToSign = ethers.utils.arrayify(contractDataHash);

          let signature = await thirdParty.signMessage(messageToSign);

          await expect(
            pact
              .connect(thirdParty)
              .signPact(resultingEvent.pactid, signature, signingDate, {
                value: pactData.payAmount
                  .mul(100 + defaultValues.commissionPercent)
                  .div(100),
              })
          ).to.be.revertedWith("Unauthorized");
          await expect(
            pact
              .connect(thirdParty)
              .signPact(resultingEvent.pactid, signature, signingDate)
          ).to.be.revertedWith("Unauthorized");
        });

        it("should allow retracting offer before employee sign", async function () {
          let { resultingEvent } = await createNewPact();
          let signingDate = Math.floor(new Date().getTime() / 1000);
          let pactData = await pact.pactData(resultingEvent.pactid);
          let extDocHash = await pact.externalDocumentHash(
            resultingEvent.pactid
          );
          let contractDataHash = await pactSigLib.contractDataHash(
            pactData.pactName.toLowerCase(),
            resultingEvent.pactid,
            pactData.employee.toLowerCase(),
            pactData.employer.toLowerCase(),
            pactData.payScheduleDays,
            pactData.payAmount.toHexString(),
            pactData.erc20TokenAddress.toLowerCase(),
            extDocHash,
            signingDate
          );
          let messageToSign = ethers.utils.arrayify(contractDataHash);
          //Employer Signs first
          let signature = await employer.signMessage(messageToSign);
          await pact
            .connect(employer)
            .signPact(resultingEvent.pactid, signature, signingDate, {
              value: pactData.payAmount
                .mul(100 + defaultValues.commissionPercent)
                .div(100),
            });
          let currStatus = (await pact.pactData(resultingEvent.pactid))
            .pactState
          expect(currStatus).to.eq(PactState.EMPLOYER_SIGNED);
          await expect(pact.reclaimStake(resultingEvent.pactid, ethers.constants.AddressZero)).to.be.reverted
          await pact.reclaimStake(resultingEvent.pactid, employer.address);
          await expect (pact.reclaimStake(resultingEvent.pactid, employer.address)).to.be.reverted
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.RETRACTED
          );
        });
      });

    if (testPactions)
      describe("Pact Actions", function () {
        it("should allow starting a pact", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await expect(
            pact.connect(employee).startPausePact(resultingEvent.pactid, true)
          ).to.be.revertedWith("employer delegate only");
          await pact.delegatePact(
            resultingEvent.pactid,
            [thirdParty.address],
            true
          );
          await pact
            .connect(thirdParty)
            .startPausePact(resultingEvent.pactid, true);
          let pactData = await pact.pactData(resultingEvent.pactid)
          let payData = await pact.payData(resultingEvent.pactid)

          expect(pactData.pactState).to.eq(PactState.ACTIVE)
          expect(payData.lastPayTimeStamp).to.eq(
            (await ethers.provider.getBlock( await ethers.provider.getBlockNumber())).timestamp
          )
        });

        it("should not allow starting unless all signed", async function () {
          let { resultingEvent } = await createNewPact();
          await expect(pact.startPausePact(resultingEvent.pactid, true)).to.be
            .reverted;
        });

        it("should not allow starting if status is active or beyond", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await pact.startPausePact(resultingEvent.pactid, true);
          await expect(pact.startPausePact(resultingEvent.pactid, true)).to.be
            .reverted;
        });

        it("should record last Payment Made, and forward commissions", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await pact.startPausePact(resultingEvent.pactid, true);
          let pactData = await pact.pactData(resultingEvent.pactid);

          let balanceBefore = await ethers.provider.getBalance(
            employee.address
          );
          let commissionBalanceBefore =  await ethers.provider.getBalance(
            thirdParty.address
          );
          let commissionsEitherSide = pactData.payAmount.mul(defaultValues.commissionPercent).div(200)

          await expect (pact.approvePayment(resultingEvent.pactid, {
            value: pactData.payAmount.add(commissionsEitherSide).sub(1),
          })).to.be.reverted
          let tx = await (await pact.approvePayment(resultingEvent.pactid, {
            value: pactData.payAmount.add(commissionsEitherSide),
          })).wait();
          console.log(pactData.payAmount.add(commissionsEitherSide).toString())

          pactData = await pact.pactData(resultingEvent.pactid);
          let payData = await pact.payData(resultingEvent.pactid);
          // expect(availableBefore.add(payAmount)).to.eq(payData.availableToWithdraw)
          expect(payData.lastPayTimeStamp).to.eq(
            (
              await ethers.provider.getBlock(
                tx.blockNumber
              )
            ).timestamp
          );
          expect(payData.lastPayAmount).to.eq(pactData.payAmount);

          expect(balanceBefore.add(
            pactData.payAmount.sub(commissionsEitherSide))).to.eq(
            await ethers.provider.getBalance(pactData.employee)
          );
          expect(commissionBalanceBefore.add(commissionsEitherSide.mul(2))).to.eq(await ethers.provider.getBalance(
            thirdParty.address
          ))

        });

        it("should not allow pay on non-active pact", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          let balanceBefore = await employee.getBalance();
          let payAmount = (await pact.pactData(resultingEvent.pactid))
            .payAmount;
          await expect(
            pact.approvePayment(resultingEvent.pactid, {
              value: payAmount
                .mul(100 + defaultValues.commissionPercent)
                .div(100),
            })
          ).to.be.revertedWith("not active");
          expect(balanceBefore).to.eq(await employee.getBalance());
        });

        it("should allow pausing and unpausing", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await pact.startPausePact(resultingEvent.pactid, true);
          await pact.startPausePact(resultingEvent.pactid, false);
          await pact.startPausePact(resultingEvent.pactid, true);
          await expect(pact.startPausePact(resultingEvent.pactid, true)).to.be.reverted
          await pact.startPausePact(resultingEvent.pactid, false);
          let payAmount = (await pact.pactData(resultingEvent.pactid))
            .payAmount;
          await expect(
            pact.approvePayment(resultingEvent.pactid, {
              value: payAmount
                .mul(100 + defaultValues.commissionPercent)
                .div(100),
            })
          ).to.be.revertedWith("not active");
          await expect(
            pact.connect(thirdParty).startPausePact(resultingEvent.pactid, true)
          ).to.be.revertedWith("employer delegate only");
        });

        it("should not allow delegating before core parties have signed", async function () {
          let { resultingEvent } = await createNewPact();
          await expect(
            pact.delegatePact(resultingEvent.pactid, [thirdParty.address], true)
          ).to.be.revertedWithoutReason();
        });

        it("should allow terminating active pact", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await pact.startPausePact(resultingEvent.pactid, true);
          let balanceBefore = await ethers.provider.getBalance(employer.address)
          await pact.terminate(resultingEvent.pactid);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.TERMINATED
          );
        });

        it("should not allow terminating non-active part", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await expect(
            pact.terminate(resultingEvent.pactid)
          ).to.be.revertedWith("not active");
        });

        it("should refund the correct amount after terminating", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await pact.startPausePact(resultingEvent.pactid, true);
          let startTime = (
            await ethers.provider.getBlock(
              await ethers.provider.getBlockNumber()
            )
          ).timestamp;
          // await sleep(1000)
          await pact.startPausePact(resultingEvent.pactid, false);
          let pauseTime = (
            await ethers.provider.getBlock(
              await ethers.provider.getBlockNumber()
            )
          ).timestamp;
          await pact.startPausePact(resultingEvent.pactid, true);
          let resumeTime = (
            await ethers.provider.getBlock(
              await ethers.provider.getBlockNumber()
            )
          ).timestamp;

          let balanceBefore = await employer.getBalance();

          let tx = await pact.terminate(resultingEvent.pactid);
          let receipt = await tx.wait();
          let terminateTime = (
            await ethers.provider.getBlock(
              await ethers.provider.getBlockNumber()
            )
          ).timestamp;

          let balanceAfter = await employer.getBalance();
          let activeTime = pauseTime - startTime + (terminateTime - resumeTime);

          let pactData = await pact.pactData(resultingEvent.pactid);
          let payAmount = pactData.payAmount;
          let payScheduleSeconds = pactData.payScheduleDays * 86400; // days in ms

          let expectedRefund = payAmount.sub(
            payAmount.mul(activeTime).div(payScheduleSeconds)
          );

          expect(balanceAfter.sub(balanceBefore)).to.eq(
            expectedRefund.sub(receipt.gasUsed.mul(receipt.effectiveGasPrice))
          );
        });

        it("should allow resigning and accept resign on active pact", async function () {
          let { resultingEvent } = await createAndSignRandomPact();

          await expect(pact.connect(employee).terminate(resultingEvent.pactid))
            .to.be.reverted;
          await pact.startPausePact(resultingEvent.pactid, true);
          
          //Should not let FNF with active pact
          await expect(pact.connect(employer).fNf(resultingEvent.pactid, 0)).to.be.revertedWith("Wrong State");
          await pact.connect(employee).terminate(resultingEvent.pactid);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.RESIGNED
          );

          await pact.connect(employee).fNf(resultingEvent.pactid, 0);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.FNF_EMPLOYEE
            );
            
            await pact.connect(employer).fNf(resultingEvent.pactid, 0);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.FNF_SETTLED
          );

          let balanceBefore = await employer.getBalance();
          let stakeAmount = (await pact.pactData(resultingEvent.pactid))
            .stakeAmount;
          let tx = await pact.reclaimStake(
            resultingEvent.pactid,
            employer.address
          );
          await expect(tx).to.not.be.reverted;

          let receipt = await tx.wait();
          let expectedBalance = balanceBefore
            .add(stakeAmount)
            .sub(receipt.gasUsed.mul(receipt.effectiveGasPrice));
          expect(await employer.getBalance()).to.eq(expectedBalance);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.ENDED
          );
        });

        // it("should allow claiming external payment", async function () {
        //   let { resultingEvent } = await createAndSignRandomPact();
        //   await pact.connect(employer).startPausePact(resultingEvent.pactid, true);
        //   let lastExtPayTime = Math.floor(new Date().getTime() / 1000);

        //   await expect(
        //     await pact
        //       .connect(employer)
        //       .addExternalPayClaim(resultingEvent.pactid, lastExtPayTime, true)
        //   ).to.not.be.reverted;
        //   let payData = await pact.payData(resultingEvent.pactid);
        //   expect(payData.claimExternalPay).to.eq(false);
        //   expect(payData.lastExternalPayTimeStamp).to.eq(lastExtPayTime);

        //   expect(
        //     await pact
        //       .connect(employee)
        //       .addExternalPayClaim(
        //         resultingEvent.pactid,
        //         payData.lastExternalPayTimeStamp,
        //         true
        //       )
        //   );
        //   payData = await pact.payData(resultingEvent.pactid);
        //   expect(payData.lastExternalPayTimeStamp).to.eq(lastExtPayTime);
        //   expect(payData.claimExternalPay).to.eq(true);
        // });
      });

    if (testdispute)
      describe("Dispute", function () {
        it("should allow employee to raise a dispute on terminate and fNf", async function () {
          let { resultingEvent } = await createAndSignRandomPact();
          await pact.delegatePact(
            resultingEvent.pactid,
            [thirdParty.address, employerDelegate.address],
            true
          );
          await pact
            .connect(employee)
            .delegatePact(
              resultingEvent.pactid,
              [employeeDelegate.address],
              true
            );
          await pact
            .connect(employerDelegate)
            .startPausePact(resultingEvent.pactid, true);

          await pact.connect(employerDelegate).terminate(resultingEvent.pactid);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.TERMINATED
          );

          let suggestedAmt = ethers.utils.parseUnits("0.1", "ether");
          await expect(
            pact
              .connect(employerDelegate)
              .dispute(resultingEvent.pactid, suggestedAmt)
          ).to.be.revertedWith("employee delegate only");
          await expect(
            pact.connect(employer).dispute(resultingEvent.pactid, suggestedAmt)
          ).to.be.revertedWith("employee delegate only");

          //Shouldn't allow until state is FNF_EMPLOYER
          await expect(
            pact
              .connect(employeeDelegate)
              .dispute(resultingEvent.pactid, suggestedAmt)
          ).to.be.revertedWithoutReason();

          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.TERMINATED
          );

          resultingEvent = (await createAndSignRandomPact()).resultingEvent;
          await pact.delegatePact(
            resultingEvent.pactid,
            [employerDelegate.address],
            true
          );
          await pact
            .connect(employee)
            .delegatePact(
              resultingEvent.pactid,
              [thirdParty.address, employeeDelegate.address],
              true
            );
          await pact
            .connect(employerDelegate)
            .startPausePact(resultingEvent.pactid, true);
          await pact.connect(employerDelegate).terminate(resultingEvent.pactid);
          await pact
            .connect(employerDelegate)
            .fNf(resultingEvent.pactid, 0, { value: suggestedAmt });
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.FNF_EMPLOYER
          );

          await expect (pact.connect(employee).proposeArbitrators(resultingEvent.pactid, [arbitrator1.address])).to.be.revertedWith("Not Disputed")
          await pact
            .connect(employeeDelegate)
            .dispute(resultingEvent.pactid, suggestedAmt);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.DISPUTED
          );
          expect((await pact.payData(resultingEvent.pactid)).proposedAmount).to.eq(suggestedAmt)
        });

        it("should not allow employer to reclaim, pay, destroy, sign when disputed", async function () {
          let suggestedAmt = BigNumber.from(100);
          let { resultingEvent } = await deployToDisputePact(suggestedAmt);
          await expect(
            pact.reclaimStake(resultingEvent.pactid, employer.address)
          ).to.be.reverted;
        });

        it("should not allow adding arbitrators after arbitrators accepted, blank arbitrators, double accepting arbitrators, or double proposing arbitrators", async function () {
          let suggestedAmt = BigNumber.from(100);
          let { resultingEvent } = await deployToDisputePact(suggestedAmt);

          resultingEvent = (await deployToDisputePact(suggestedAmt))
            .resultingEvent;

          //Blank list should revert
          await expect(
              pact
                .connect(employee)
                .proposeArbitrators(resultingEvent.pactid, [])
            ).to.be.reverted;

          //Employee proposes
          await expect(
            await pact
              .connect(employee)
              .proposeArbitrators(resultingEvent.pactid, [arbitrator2.address])
          ).to.not.be.reverted;

          let pactData = await pact.pactData(resultingEvent.pactid)
          expect(pactData.arbitratorProposer).to.eq(employee.address)
          expect(pactData.arbitratorProposedFlag).to.be.true
          
          //Employer Rejects
          await expect(
            await pact
              .connect(employer)
              .acceptOrRejectArbitrators(resultingEvent.pactid, false)
          ).to.not.be.reverted;
          pactData = await pact.pactData(resultingEvent.pactid)
          expect(pactData.arbitratorProposedFlag).to.be.false

          //Third party can't propose
          await expect(
            pact
              .connect(thirdParty)
              .proposeArbitrators(resultingEvent.pactid, [arbitrator2.address])
          ).to.be.reverted;

          //Employer proposes
          await expect(
            await pact
              .connect(employer)
              .proposeArbitrators(resultingEvent.pactid, [arbitrator2.address])
          ).to.not.be.reverted;

          //Same party can't accept
          await expect(
            pact
              .connect(employer)
              .acceptOrRejectArbitrators(resultingEvent.pactid, true)
          ).to.be.reverted;
          
          //Employee accepts
          await expect(
            await pact
              .connect(employee)
              .acceptOrRejectArbitrators(resultingEvent.pactid, true)
          ).to.not.be.reverted;
          pactData = await pact.pactData(resultingEvent.pactid)
          expect(pactData.arbitratorAccepted).to.be.true

          //Can't re-accept
          await expect(
            pact
              .connect(employer)
              .acceptOrRejectArbitrators(resultingEvent.pactid, true)
          ).to.be.reverted;
          await expect(
            pact
              .connect(employee)
              .acceptOrRejectArbitrators(resultingEvent.pactid, true)
          ).to.be.reverted;

          //Can't re-propose
          await expect(
            pact
              .connect(employee)
              .proposeArbitrators(resultingEvent.pactid, [arbitrator1.address])
          ).to.be.revertedWith("Already Accepted");

          await expect(
            pact
              .connect(employer)
              .proposeArbitrators(resultingEvent.pactid, [arbitrator1.address])
          ).to.be.revertedWith("Already Accepted");
        });

        it("should correctly perform arbitration", async function () {
          let suggestedAmt = BigNumber.from(100);
          let { resultingEvent } = await deployToDisputePact(suggestedAmt);
          await pact
            .connect(employee)
            .proposeArbitrators(resultingEvent.pactid, [
              arbitrator1.address,
              arbitrator2.address,
            ]);
          
          // await expect(pact
          //   .connect(thirdParty)
          //   .arbitratorResolve(resultingEvent.pactid)).to.be.reverted;

          await pact
            .connect(employer)
            .acceptOrRejectArbitrators(resultingEvent.pactid, true);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.ARBITRATED
          );

          let arbitratorArray = await pact.getArbitratrators(resultingEvent.pactid)
          expect(arbitrator1.address).to.eq(arbitratorArray[0].addr)
          expect(false).to.eq(arbitratorArray[0].hasResolved)
          expect(arbitrator2.address).to.eq(arbitratorArray[1].addr)
          expect(false).to.eq(arbitratorArray[1].hasResolved)

          await pact
            .connect(thirdParty)
            .arbitratorResolve(resultingEvent.pactid);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.ARBITRATED
          );

          await expect(
            await pact
              .connect(arbitrator1)
              .arbitratorResolve(resultingEvent.pactid)
          ).to.not.be.reverted;
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.ARBITRATED
          );
          await expect(
            pact.reclaimStake(resultingEvent.pactid, employer.address)
          ).to.be.reverted;

          await expect(
            await pact
              .connect(arbitrator2)
              .arbitratorResolve(resultingEvent.pactid)
          ).to.not.be.reverted;
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.DISPUTE_RESOLVED
          );

          await expect(
            pact.connect(employee).dispute(resultingEvent.pactid, suggestedAmt)
          ).to.be.reverted;

          let balanceBefore = await employer.getBalance();
          let stakeAmount = (await pact.pactData(resultingEvent.pactid)).stakeAmount;
          let tx = await pact.reclaimStake(
            resultingEvent.pactid,
            employer.address
          );
          await expect(tx).to.not.be.reverted;

          let receipt = await tx.wait();
          let expectedBalance = balanceBefore
            .add(stakeAmount)
            .sub(receipt.gasUsed.mul(receipt.effectiveGasPrice));
          expect(await employer.getBalance()).to.eq(expectedBalance);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.ENDED
          );
          await expect(
            pact.connect(employee).dispute(resultingEvent.pactid, suggestedAmt)
          ).to.be.reverted;
        });
        it("should allow fNf to both parties during arbitration and no dispute", async function () {
          let suggestedAmt = BigNumber.from(100);
          let { resultingEvent } = await deployToDisputePact(suggestedAmt);
          await pact
            .connect(employee)
            .proposeArbitrators(resultingEvent.pactid, [
              arbitrator1.address,
              arbitrator2.address,
            ]);
          await pact
            .connect(employer)
            .acceptOrRejectArbitrators(resultingEvent.pactid, true);
          expect((await pact.pactData(resultingEvent.pactid)).pactState).to.eq(
            PactState.ARBITRATED
          );
          await expect(await pact.fNf(resultingEvent.pactid, 0, { value: 100 }))
            .to.not.be.reverted;
          await expect(
            await pact
              .connect(employee)
              .fNf(resultingEvent.pactid, 0, { value: 100 })
          ).to.not.be.reverted;

          await pact.connect(employer).fNf(resultingEvent.pactid, 0, {value: suggestedAmt})
          let pactData = await pact.pactData(resultingEvent.pactid)
          expect(pactData.pactState).to.eq(PactState.DISPUTE_RESOLVED)
        });
      });

    if (testErc)
      describe("ERC", function () {
        it("should allow creating, signing, reclaim pact with erc20", async function () {
          let tokensToLock = parseEther("10");
          let tokenBalanceBefore = await erc20Contract.balanceOf(
            employer.address
          );
          let { resultingEvent } = await createNewPact(
            erc20Contract.address,
            "Test ERC",
            employee.address,
            employer.address,
            7,
            tokensToLock
          );
          expect(resultingEvent.pactid).to.have.length(66);
          let signingDate = Math.floor(new Date().getTime() / 1000);
          let pactData = await pact.pactData(resultingEvent.pactid);
          let extDocHash = await pact.externalDocumentHash(
            resultingEvent.pactid
          );
          let contractDataHash = await pactSigLib.contractDataHash(
            pactData.pactName,
            resultingEvent.pactid,
            pactData.employee.toLowerCase(),
            pactData.employer.toLowerCase(),
            pactData.payScheduleDays,
            pactData.payAmount.toHexString(),
            pactData.erc20TokenAddress.toLowerCase(),
            extDocHash,
            signingDate
          );

          let messageToSign = ethers.utils.arrayify(contractDataHash);
          let commissionBalanceBefore = await erc20Contract.balanceOf(thirdParty.address)
          //Employer Signs first
          let signature = await employer.signMessage(messageToSign);
          await expect(pact
          .connect(employer)
          .signPact(resultingEvent.pactid, signature, signingDate, {value: 1})).to.be.reverted;
          await pact
            .connect(employer)
            .signPact(resultingEvent.pactid, signature, signingDate);

          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.EMPLOYER_SIGNED);
          expect(pactData.stakeAmount).to.eq(tokensToLock);

          let commissions = pactData.payAmount
            .mul(defaultValues.commissionPercent)
            .div(100)
          
          expect(await erc20Contract.balanceOf(thirdParty.address)).to.eq(commissionBalanceBefore.add(commissions))

          
          let spentAmount = pactData.payAmount.add(commissions);
          expect(await erc20Contract.balanceOf(employer.address)).to.eq(
            tokenBalanceBefore.sub(spentAmount)
          );
          await pact.reclaimStake(resultingEvent.pactid, employer.address);
          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.RETRACTED);
          expect(await erc20Contract.balanceOf(employer.address)).to.eq(
            tokenBalanceBefore.sub(commissions)
          );
        });

        it("should allow payment, terminate, fnf with amount, reclaim with erc20", async function () {
          let { resultingEvent } = await createAndSignRandomPact(
            erc20Contract.address
          );
          expect(resultingEvent.pactid).to.have.length(66);
          await pact.startPausePact(resultingEvent.pactid, true);
          let pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.ACTIVE);

          let employeeTokenBalance = await erc20Contract.balanceOf(
            employee.address
          );
          let commissionBalanceBefore = await erc20Contract.balanceOf(thirdParty.address)
          let commissions = pactData.payAmount.mul(defaultValues.commissionPercent)
          .div(200);

          await pact.approvePayment(resultingEvent.pactid);
          pactData = await pact.pactData(resultingEvent.pactid);
          let payData = await pact.payData(resultingEvent.pactid);
          employeeTokenBalance = employeeTokenBalance.add(
            defaultValues.payAmount
          ).sub(commissions);
          
          expect(employeeTokenBalance).to.eq(
            await erc20Contract.balanceOf(employee.address)
          );
          expect(commissionBalanceBefore.add(commissions.mul(2))).to.eq(await erc20Contract.balanceOf(thirdParty.address))
          expect(payData.lastPayAmount).to.eq(defaultValues.payAmount);

          await pact.terminate(resultingEvent.pactid);
          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.TERMINATED);

          await pact.fNf(resultingEvent.pactid, defaultValues.payAmount);
          employeeTokenBalance = employeeTokenBalance.add(
            defaultValues.payAmount
          );
          expect(employeeTokenBalance).to.eq(
            await erc20Contract.balanceOf(employee.address)
          );
          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.FNF_EMPLOYER);

          let employerTokenBalance = await erc20Contract.balanceOf(
            employer.address
          );
          await erc20Contract
            .connect(employee)
            .approve(pact.address, defaultValues.payAmount);
          await pact
            .connect(employee)
            .fNf(resultingEvent.pactid, defaultValues.payAmount);
          employerTokenBalance = employerTokenBalance.add(
            defaultValues.payAmount
          );
          expect(employerTokenBalance).to.eq(
            await erc20Contract.balanceOf(employer.address)
          );
          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.FNF_SETTLED);

          employerTokenBalance = await erc20Contract.balanceOf(
            employer.address
          );
          await pact.reclaimStake(resultingEvent.pactid, employer.address);
          employerTokenBalance = employerTokenBalance.add(pactData.stakeAmount);
          expect(employerTokenBalance).to.eq(
            await erc20Contract.balanceOf(employer.address)
          );
          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.ENDED);
        });

        it("should allow disputing, resolving with erc20", async function () {
          let { resultingEvent } = await createAndSignRandomPact(
            erc20Contract.address
          );
          await pact.startPausePact(resultingEvent.pactid, true);
          await pact.terminate(resultingEvent.pactid);
          let employeeTokenBalance = await erc20Contract.balanceOf(
            employee.address
          );

          await pact.fNf(resultingEvent.pactid, defaultValues.payAmount);
          employeeTokenBalance = employeeTokenBalance.add(
            defaultValues.payAmount
          );
          expect(employeeTokenBalance).to.eq(
            await erc20Contract.balanceOf(employee.address)
          );

          await pact
            .connect(employee)
            .dispute(resultingEvent.pactid, defaultValues.payAmount);
          let pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.DISPUTED);

          await pact.fNf(resultingEvent.pactid, defaultValues.payAmount);
          pactData = await pact.pactData(resultingEvent.pactid);
          expect(pactData.pactState).to.eq(PactState.DISPUTED);
        });
      });

      if (panicPause)
      describe("Panic", function () {
        it("should not allow critical operations when paused", async function () {


          

          // let tokensToLock = parseEther("10");
          // let tokenBalanceBefore = await erc20Contract.balanceOf(
          //   employer.address
          // );
          // let { resultingEvent } = await createNewPact(
          //   erc20Contract.address,
          //   "Test ERC",
          //   employee.address,
          //   employer.address,
          //   7,
          //   tokensToLock
          // );
          // expect(resultingEvent.pactid).to.have.length(66);
          // let signingDate = Math.floor(new Date().getTime() / 1000);
          // let pactData = await pact.pactData(resultingEvent.pactid);
          // let extDocHash = await pact.externalDocumentHash(
          //   resultingEvent.pactid
          // );
          // let contractDataHash = await pactSigLib.contractDataHash(
          //   pactData.pactName,
          //   resultingEvent.pactid,
          //   pactData.employee.toLowerCase(),
          //   pactData.employer.toLowerCase(),
          //   pactData.payScheduleDays,
          //   pactData.payAmount.toHexString(),
          //   pactData.erc20TokenAddress.toLowerCase(),
          //   extDocHash,
          //   signingDate
          // );

          // let messageToSign = ethers.utils.arrayify(contractDataHash);
          // //Employer Signs first
          // let signature = await employer.signMessage(messageToSign);
          // await pact
          //   .connect(employer)
          //   .signPact(resultingEvent.pactid, signature, signingDate);

          // pactData = await pact.pactData(resultingEvent.pactid);
          // expect(pactData.pactState).to.eq(PactState.EMPLOYER_SIGNED);
          // expect(pactData.stakeAmount).to.eq(tokensToLock);

          // let commissions = pactData.payAmount
          //   .mul(defaultValues.commissionPercent)
          //   .div(100);
          // let spentAmount = pactData.payAmount.add(commissions);
          // expect(await erc20Contract.balanceOf(employer.address)).to.eq(
          //   tokenBalanceBefore.sub(spentAmount)
          // );
          // await pact.reclaimStake(resultingEvent.pactid, employer.address);
          // pactData = await pact.pactData(resultingEvent.pactid);
          // expect(pactData.pactState).to.eq(PactState.RETRACTED);
          // expect(await erc20Contract.balanceOf(employer.address)).to.eq(
          //   tokenBalanceBefore.sub(commissions)
          // );
        });
      });
  });
