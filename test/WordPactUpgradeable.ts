// import { expect } from "chai";
// import { ethers } from "hardhat";
// import { BigNumberish } from "ethers"
// import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
// import { WordPactUpgradeable, WordPactUpgradeable__factory } from "../typechain-types";
// import { DisputeHelper } from "../typechain-types/contracts/GigPactUpgradeable/libraries/DisputeHelper";
// import { ERC20, IERC20 } from "../typechain-types/@openzeppelin/contracts/token/ERC20";
// import { erc20 } from "../typechain-types/factories/@openzeppelin/contracts/token";
// import { AbiCoder, arrayify, formatEther, formatUnits, hexValue, parseBytes32String, parseEther, solidityPack, toUtf8Bytes, toUtf8String } from "ethers/lib/utils";

// const Signer = ethers.Signer
// const BigNumber = ethers.BigNumber
// const formatBytes32String = ethers.utils.formatBytes32String
// let pact: WordPactUpgradeable
// enum PactState {
//     DEPLOYED,
//     RETRACTED,
//     SIGNING_IN_PROCESS,
//     ALL_SIGNED,
//     DISPUTED
// }

// let [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2]: SignerWithAddress[] = []

// async function setSigners() {
//     [employer, employee, employerDelegate, employeeDelegate, thirdParty, arbitrator1, arbitrator2] = await ethers.getSigners()
// }

// let defaultValues = {
//     documentHash: ethers.utils.sha256(ethers.utils.toUtf8Bytes("Untitled document 1")),
//     pactName: "Test Words",
//     signatories: ["0x70997970C51812dc3A010C7d01b50e0d17dc79C8", "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"],
//     additionalData: "Additional Data"
// }

// async function createNewPact(
//     documentHash = defaultValues.documentHash,
//     pactName = defaultValues.pactName,
//     signatories = defaultValues.signatories,
//     additionalData = defaultValues.additionalData
// ) {
//     let tx = await (await pact.createPact(
//         formatBytes32String(pactName),
//         documentHash,
//         signatories,
//         additionalData,
//         ethers.constants.HashZero,
//         ethers.constants.AddressZero)).wait()
//     let resultingEvent = tx.events && tx.events[0].decode && tx.events[0].decode(tx.events[0].data)
//     return { resultingEvent, tx }
// }

// if(false)
// describe("Word pact test", function () {
//     this.beforeAll(async () => {
//         await setSigners()

//         let wordPactFactory: WordPactUpgradeable__factory = await ethers.getContractFactory("WordPactUpgradeable")
//         pact = await (await wordPactFactory.deploy()).deployed()
//     })

//     describe("Create WP", function () {
//         it("should create a new wp using params and return new pactid", async function () {
//             let { resultingEvent } = await createNewPact()
//             expect(resultingEvent.pactid).to.have.length(66)
//         })
//         it("should set the status correctly while signing", async function () {
//             let { resultingEvent } = await createNewPact()
//             let signTime = Math.ceil(new Date().getTime() / 1000)
//             // let signScript = await pact.getSignScript(resultingEvent.pactid, signTime)
//             // let signScript = ethers.utils.concat(["PactId: ",
//             //     resultingEvent.pactid,
//             //     "Pact Name: ",
//             //     defaultValues.pactName,
//             //     "Sign Time: ",
//             //     signTime + '',
//             //     "Additional Data: ",
//             //     defaultValues.additionalData])


//              let signScript = ethers.utils.concat([toUtf8Bytes("PactId: "),
//                 resultingEvent.pactid,
//                 toUtf8Bytes("Pact Name: "),
//                 formatBytes32String(defaultValues.pactName),
//                 toUtf8Bytes("Sign Time: "),
//                 hexValue(signTime),
//                 toUtf8Bytes("Additional Data: "),
//                 toUtf8Bytes(defaultValues.additionalData)])

//             // signScript = solidityPack([
//             //     "string", "bytes32", "string", "bytes32",
//             // // ], 
                
//             //     "string", "uint", "string", "string"],
//             //     [
//             //         "PactId: ",
//             //         resultingEvent.pactid,
//             //         "Pact Name: ",
//             //         formatBytes32String(defaultValues.pactName),
//             //     // ])
//             // "Sign Time: ",
//             // signTime + '',
//             // "Additional Data: ",
//             // defaultValues.additionalData])
//             // console.log(toUtf8String(await pact.getSignScript(resultingEvent.pactid, signTime)))
//             // console.log(await employee.signMessage("Test"))
//             // console.log(await employee.signMessage(toUtf8Bytes("Test")))

//             console.log(toUtf8String(signScript))
//             let signature = await employee.signMessage(signScript)
//             await pact.signPact(resultingEvent.pactid, signTime, signature, signScript)
//             // let pactData = await pact.pactData(resultingEvent.pactid)
//             // console.log(pactData)
//         })
//         it("should allow retracting a pact before ALL_SIGNED", async function () {

//         })
//         it("should allow delegating and sign as delegate")
//         it("should allow disputing a signed pact by all parties")
//         it("shouldn't allow creating a pact with wrong external pactid")
//         it("should allow creating a pact with correct pactID/contract address")
//     })
// })