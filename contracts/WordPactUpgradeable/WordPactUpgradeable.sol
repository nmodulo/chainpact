// //SPDX-License-Identifier: MIT

// import "hardhat/console.sol";
// pragma solidity 0.8.16;
// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// // import "@openzeppelin/contracts/interfaces/IERC20.sol";
// import "../Interface/ChainPact.sol";


// enum PactState {
//     UNDEFINED,
//     DEPLOYED,
//     SIGNING_IN_PROCESS,
//     ALL_SIGNED,
//     RETRACTED,
//     DISPUTED
// }

// struct Signatory {
//     address addr;
//     bool hasSigned;
// }

// struct PactData {
//     address creator;
//     bytes32 pactName;
//     bytes32 documentHash;
//     PactState pactState;
//     Signatory[] signatories;
//     address[] attestors;
//     string additionalData;
//     address externalPactAddress;
// }

// contract WordPactUpgradeable is
//     Initializable,
//     UUPSUpgradeable,
//     OwnableUpgradeable
// {
//     ///@dev required by the OZ UUPS module
//     function _authorizeUpgrade(address) internal override onlyOwner {}

//     constructor(){
//         _disableInitializers();
//     }
//     function initialize() public initializer {
//         ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly

//         __Ownable_init();
//     }

//     event LogPactCreated(address indexed creator, bytes32 pactid);

//     //Data
//     uint private pactsCounter;
//     mapping(bytes32 => PactData) public pactData;
//     mapping(address => mapping(address => bool)) public isDelegate;
//     mapping(bytes32 => mapping(address => bool)) internal isSignatory;

//     function createPact(
//         bytes32 pactName_,
//         bytes32 documentHash_,
//         address[] calldata signatories_,
//         string calldata additionalData_,
//         bytes32 pactId,
//         address externalPactAddress_
//     ) external {
//         if (pactId != 0) {
//             require(
//                 ChainPact(externalPactAddress_).isParty(pactId, msg.sender)
//             );
//             pactData[pactId].externalPactAddress = externalPactAddress_;
//         } else {
//             pactId = keccak256(
//                 abi.encodePacked(
//                     address(this),
//                     msg.sender,
//                     "chainpact_wordpact",
//                     pactsCounter
//                 )
//             );
//         }
//         pactData[pactId].pactName = pactName_;
//         pactData[pactId].documentHash = documentHash_;
//         pactData[pactId].pactState = PactState.DEPLOYED;
//         for (uint i = 0; i < signatories_.length; i++) {
//             pactData[pactId].signatories.push(
//                 Signatory({addr: signatories_[i], hasSigned: false})
//             );
//             isSignatory[pactId][signatories_[i]] = true;
//         }
//         if (bytes(additionalData_).length > 0) {
//             pactData[pactId].additionalData = additionalData_;
//         }

//         // pactData[pactId].signatories =
//         emit LogPactCreated(msg.sender, pactId);
//     }

//     function isParty(bytes32 pactid, address party) public view returns (bool) {
//         return (isSignatory[pactid][party]);
//     }

//     function getSignScript(
//         bytes32 pactid,
//         uint signTime
//     ) public view returns (bytes memory) {
//         PactData memory pactData_ = pactData[pactid];
//         return
//             // string(
//                 abi.encodePacked(
//                     "PactId: ",
//                     pactid,
//                     "Pact Name: ",
//                     pactData_.pactName,
//                     "Sign Time: ",
//                     signTime,
//                     "Additional Data: ",
//                     pactData_.additionalData
//                 );
//             // );
//     }

//     function getSomeString(bytes32 pactid, uint signTime) public pure returns (string memory){
//         return string(abi.encodePacked("should allow creating a pact with correct pactID/contract address","swall"));
//     }

//     function _signPact(
//         bytes32 pactid,
//         uint signTime,
//         bytes calldata signature,
//         address signatory
//     ) internal {
//         address signer = ECDSA.recover(
//             ECDSA.toEthSignedMessageHash(
//                 bytes(getSignScript(pactid, signTime))
//             ),
//             signature
//         );

//         require(signer == msg.sender, "Invalid signature");
//         require(pactData[pactid].pactState < PactState.ALL_SIGNED);
//         bool allSigned = true;
//         Signatory[] memory signatories_ = pactData[pactid].signatories;
//         for (uint i = 0; i < signatories_.length; i++) {
//             if (signatory == signatories_[i].addr) {
//                 if(signatories_[i].hasSigned) revert ("Already signed");
//                 pactData[pactid].signatories[i].hasSigned = true;
//             } else {
//                 allSigned = allSigned && signatories_[i].hasSigned;
//             }
//         }
//         if (allSigned) {
//             pactData[pactid].pactState = PactState.ALL_SIGNED;
//         } else if (pactData[pactid].pactState == PactState.DEPLOYED) {
//             pactData[pactid].pactState = PactState.SIGNING_IN_PROCESS;
//         }
//     }

//     function signPact(
//         bytes32 pactid,
//         uint signTime,
//         bytes calldata signature,
//         bytes calldata signScriptUsed

//     ) external {
//         require(isSignatory[pactid][msg.sender], "Unauthorized");
//         console.log("_signPact contract");
//         console.log("Local: ");
//         console.logBytes(signScriptUsed);

//         console.log("On-Chain: ");
//         console.logBytes(getSignScript(pactid, signTime));
//         _signPact(pactid, signTime, signature, msg.sender);
//     }

//     function delegatePacts(address delegate) external {
//         isDelegate[delegate][msg.sender] = true;
//     }

//     function signAsPactDelegate(
//         bytes32 pactid,
//         uint signTime,
//         bytes calldata signature,
//         address delegator
//     ) external {
//        require(isDelegate[msg.sender][delegator], "Not a delegate");
//        _signPact(pactid, signTime, signature, delegator);
//     }

//     function disputePact(bytes32 pactid) external {
//         require(isSignatory[pactid][msg.sender], "Unauthorized");
//         require(pactData[pactid].pactState == PactState.ALL_SIGNED);
//         pactData[pactid].pactState = PactState.DISPUTED;
//     }

//     function retractPact(bytes32 pactid) external {
//         require(pactData[pactid].pactState < PactState.ALL_SIGNED);
//         require(pactData[pactid].creator == msg.sender);
//         pactData[pactid].pactState = PactState.RETRACTED;
//     }
// }
