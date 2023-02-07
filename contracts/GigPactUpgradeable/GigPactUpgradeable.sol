//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./libraries/PactSignature.sol";
import "./libraries/DisputeHelper.sol";
import "./libraries/PaymentHelper.sol";
import "./Structs.sol";

contract GigPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(uint commissionPercentage_, address commissionSink_) public initializer {
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        commissionPercentage = commissionPercentage_;
        commissionSink = commissionSink_;
        __Ownable_init();
    }

    //Events
    event LogPaymentMade(
        bytes32 indexed pactid,
        uint value,
        address indexed payer
    );

    event LogStateUpdate(
        bytes32 indexed pactid,
        PactState newState,
        address indexed updater
    );
    event LogPactCreated(address indexed creator, bytes32 pactid);


    //Data

    uint private pactsCounter;
    mapping(bytes32 => PactData) public pactData;
    mapping(bytes32 => PayData) public payData;
    mapping(bytes32 => mapping(address => bool)) public isEmployeeDelegate;
    mapping(bytes32 => mapping(address => bool)) public isEmployerDelegate;
    mapping(bytes32 => bytes32) public externalDocumentHash;
    uint private commissionPercentage;  //
    address private commissionSink;

    function getArbitratrators(
        bytes32 pactid
    ) external view returns (Arbitrator[] memory) {
        return pactData[pactid].proposedArbitrators;
    }

    //modifiers
    modifier onlyEmployer(bytes32 pactid) {
        require(
            isEmployerDelegate[pactid][msg.sender],
            "employer delegate only"
        );
        _;
    }

    modifier onlyEmployee(bytes32 pactid) {
        require(
            isEmployeeDelegate[pactid][msg.sender],
            "employee delegate only"
        );
        _;
    }

    modifier isActive(bytes32 pactid) {
        require(pactData[pactid].pactState == PactState.ACTIVE, "not active");
        _;
    }

    modifier isEOA() {
        require(msg.sender == tx.origin);
        _;
    }

    function isParty(bytes32 pactid, address party) public view returns(bool){
        return isEmployeeDelegate[pactid][party] ||
                isEmployerDelegate[pactid][party];
    }

    function createPact(
        bytes32 pactName_,
        address employee_,
        address employer_,
        uint32 payScheduleDays_,
        uint128 payAmount_,
        address erc20TokenAddress_,
        bytes32 externalDocumentHash_
    ) external {
        require(payAmount_ > 0 && pactName_ != 0);
        bytes32 uid = keccak256(
            abi.encodePacked(
                msg.sender,
                "chainpact_gigpact",
                pactsCounter,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );
        pactData[uid].pactName = pactName_;
        pactData[uid].employee = employee_;
        pactData[uid].payScheduleDays = payScheduleDays_;
        pactData[uid].employer = employer_;
        if(erc20TokenAddress_ != address(0))
            pactData[uid].erc20TokenAddress = erc20TokenAddress_;
        pactData[uid].payAmount = payAmount_;
        if(externalDocumentHash_ != 0)
            externalDocumentHash[uid] = externalDocumentHash_;
        isEmployeeDelegate[uid][employee_] = true;
        isEmployerDelegate[uid][employer_] = true;
        pactsCounter++;
        emit LogPactCreated(msg.sender, uid);
    }

    function signPact(
        bytes32 pactid,
        bytes calldata signature,
        uint256 signingDate_
    ) external payable {
        PactState newPactState = PactSignature.checkSignPact(
            pactid,
            pactData[pactid],
            signature,
            externalDocumentHash[pactid],
            signingDate_,
            commissionPercentage,
            commissionSink
        );
        emit LogStateUpdate(pactid, newPactState, msg.sender);
    }

    // // Function to retract the stake before the employee signs
    // function retractOffer(bytes32 pactid) external onlyEmployer(pactid) returns (bool) {
    //     PactData memory pactData_ = pactData[pactid];
    //     require(pactData_.pactState < PactState.ALL_SIGNED, "Contract already signed");
    //     pactData[pactid].pactState = PactState.RETRACTED;
    //     pactData[pactid].stakeAmount = 0;
    //     payable(pactData[pactid].employer).transfer(pactData_.stakeAmount);
    //     return true;
    // }

    function delegatePact(
        bytes32 pactid,
        address[] calldata delegates,
        bool addOrRevoke
    ) external {
        require(pactData[pactid].pactState >= PactState.ALL_SIGNED);
        if (msg.sender == pactData[pactid].employer) {
            for (uint i = 0; i < delegates.length; i++) {
                isEmployerDelegate[pactid][delegates[i]] = addOrRevoke;
            }
        } else if (msg.sender == pactData[pactid].employee) {
            for (uint i = 0; i < delegates.length; i++) {
                isEmployeeDelegate[pactid][delegates[i]] = addOrRevoke;
            }
        } else {
            revert();
        }
    }

    function startPause(
        bytes32 pactid,
        bool toStart
    ) external onlyEmployer(pactid) {
        PayData memory payData_ = payData[pactid];
        PactState updatedState_ = pactData[pactid].pactState;

        if (toStart) {
            if (updatedState_ == PactState.ALL_SIGNED) {
                updatedState_ = PactState.ACTIVE;
                payData_.lastPayTimeStamp = uint40(block.timestamp);
                payData_.lastPayAmount = 0;
            } else if (updatedState_ == PactState.PAUSED) {
                payData_.pauseDuration +=
                    uint40(block.timestamp) -
                    payData_.pauseResumeTime;
                payData_.pauseResumeTime = uint40(block.timestamp);
            } else revert();
            updatedState_ = PactState.ACTIVE;
        } else if (pactData[pactid].pactState == PactState.ACTIVE) {
            updatedState_ = PactState.PAUSED;
            payData_.pauseResumeTime = uint40(block.timestamp);
        } else revert();
        payData[pactid] = payData_;
        pactData[pactid].pactState = updatedState_;
        emit LogStateUpdate(pactid, updatedState_, msg.sender);
    }

    function addExternalPayClaim (bytes32 pactid, uint payTime, bool confirm) external isActive(pactid){
        if(isEmployerDelegate[pactid][msg.sender]){
            payData[pactid].lastExternalPayTimeStamp = uint40(payTime);
            payData[pactid].claimExternalPay = false;
        } else if(isEmployeeDelegate[pactid][msg.sender] && confirm){
            payData[pactid].claimExternalPay = true;
        }
    }

    // function externalPayClaim(bytes32 pactid)



    function approvePayment(
        bytes32 pactid
    ) external payable onlyEmployer(pactid) isActive(pactid) {
        // PactData memory pactData_ = pactData[pactid];
        // (uint lastPayTimeStamp, uint pauseDuration) = (
        //     payData[pactid].lastPayTimeStamp,
        //     payData[pactid].pauseDuration
        // );
        (address employee, uint payAmount, address erc20TokenAddress) = (
            pactData[pactid].employee,
            pactData[pactid].payAmount,
            pactData[pactid].erc20TokenAddress
        );
        // require(
        //     msg.value >= pactData_.payAmount,
        //     "Amount less than payAmount"
        // );
        // payData[pactid].lastPayTimeStamp = uint40(block.timestamp);
        // payData[pactid].lastPayAmount = uint128(msg.value);
        // payData[pactid].pauseDuration = 0;
        // payable(pactData[pactid].employee).transfer(msg.value);

        bool result;
        if (erc20TokenAddress == address(0)) {
            require(msg.value >= payAmount + (payAmount*commissionPercentage)/100, "Amount less than payAmount");
            require(payable(commissionSink).send((payAmount*commissionPercentage)/100));
            result = payable(employee).send(msg.value - (payAmount*commissionPercentage)/100);
            // require(result);
            // result = true;
        } else {
            // IERC20 tokenContract = IERC20(pactData_.erc20TokenAddress);
            require(IERC20(erc20TokenAddress).transferFrom(
                msg.sender,
                commissionSink,
                (payAmount*commissionPercentage)/100
            ));
            result = IERC20(erc20TokenAddress).transferFrom(
                msg.sender,
                employee,
                payAmount
            );
        }
        if (result) {
            payData[pactid].lastPayTimeStamp = uint40(block.timestamp);
            payData[pactid].lastPayAmount = uint128(
                erc20TokenAddress == address(0) ? msg.value - (payAmount*commissionPercentage)/100 : payAmount
            );
            payData[pactid].pauseDuration = 0;
            emit LogPaymentMade(pactid, msg.value, msg.sender);
        } else {
            revert();
        }
    }

    /** To get the remaining stake by the employer when the contract has been ended. */
    // function reclaimStake(
    //     bytes32 pactid,
    //     address payable payee
    // ) external onlyEmployer(pactid) isEOA {
    //     PactData memory pactData_ = pactData[pactid];
    //     require(payee != address(0));
    //     uint stakeAmount_ = pactData[pactid].stakeAmount;
    //     require(stakeAmount_ > 0);
    //     if (pactData_.pactState >= PactState.FNF_SETTLED) {
    //         pactData_.pactState = PactState.ENDED;
    //     } else if (pactData[pactid].pactState < PactState.EMPLOYEE_SIGNED) {
    //         pactData_.pactState = PactState.RETRACTED;
    //     } else revert();
    //     // emit LogPaymentMade(pactid, stakeAmount_, address(this));
    //     bool result;

    //     pactData[pactid].stakeAmount = 0;
    //     if (pactData[pactid].erc20TokenAddress == address(0)) {
    //         result = payee.send(stakeAmount_);
    //     } else {
    //         // result = IERC20(pactData[pactid].erc20TokenAddress).transferFrom(
    //         //     msg.sender,
    //         //     pactData_.employee,
    //         //     stakeAmount_
    //         // );
    //     }
    //     if (result) {
    //         pactData[pactid].pactState = pactData_.pactState;
    //         emit LogStateUpdate(pactid, pactData_.pactState, msg.sender);
    //     }
    // }

    function reclaimStake(
        bytes32 pactid,
        address payable payee
    ) external onlyEmployer(pactid) isEOA {
        // PactData memory pactData_ = pactData[pactid];
        require(payee != address(0));
        (PactState pactState_, uint stakeAmount_) = (
            pactData[pactid].pactState,
            pactData[pactid].stakeAmount
        );
        require(stakeAmount_ > 0);
        if (pactState_ >= PactState.FNF_SETTLED) {
            pactState_ = PactState.ENDED;
        } else if (pactState_ < PactState.EMPLOYEE_SIGNED) {
            pactState_ = PactState.RETRACTED;
        } else revert();
        // emit LogPaymentMade(pactid, stakeAmount_, address(this));
        bool result;

        pactData[pactid].stakeAmount = 0;
        if (pactData[pactid].erc20TokenAddress == address(0)) {
            result = payee.send(stakeAmount_);
        } else {
            result = IERC20(pactData[pactid].erc20TokenAddress).transfer(
                payee,
                stakeAmount_
            );
        }
        if (result) {
            pactData[pactid].pactState = pactState_;
            emit LogStateUpdate(pactid, pactState_, msg.sender);
        }
    }

    // function approvePayment(
    //     bytes32 pactid
    // ) external payable onlyEmployer(pactid){
    //     bool result = PaymentHelper.approvePayment(pactData[pactid], payData[pactid]);
    //     // if(result) emit LogPaymentMade(pactid, msg.value, msg.sender);
    // }

    // function terminate(bytes32 pactid) external isEOA isActive(pactid) {
    //     PactData memory pactData_ = pactData[pactid];
    //     PayData memory payData_ = payData[pactid];
    //     if (isEmployeeDelegate[pactid][msg.sender]) {
    //         pactData_.pactState = PactState.RESIGNED;
    //     } else if (isEmployerDelegate[pactid][msg.sender]) {
    //         // Payment due assumed
    //         uint paymentDue = (pactData_.payAmount *
    //             (block.timestamp -
    //                 payData_.lastPayTimeStamp -
    //                 payData_.pauseDuration)) /
    //             (pactData_.payScheduleDays * 86400);
    //         if (paymentDue >= pactData_.stakeAmount)
    //             paymentDue = pactData_.stakeAmount;

    //         uint refundAmount_ = pactData_.stakeAmount - paymentDue;
    //         pactData[pactid].stakeAmount = uint128(paymentDue);
    //         pactData_.pactState = PactState.TERMINATED;
    //         payable(pactData_.employer).transfer(refundAmount_);
    //     } else revert("Unauthorized");
    //     pactData[pactid].pactState = pactData_.pactState;
    //     emit LogStateUpdate(pactid, pactData_.pactState, msg.sender);
    // }

    function terminate(bytes32 pactid) external isEOA isActive(pactid) {
        // PayData memory payData_ = payData[pactid];
        (uint lastPayTimeStamp, uint pauseDuration) = (
            payData[pactid].lastPayTimeStamp,
            payData[pactid].pauseDuration
        );
        (
            PactState pactState_,
            uint payScheduleDays,
            address employer,
            uint payAmount,
            uint stakeAmount_
        ) = (
                pactData[pactid].pactState,
                pactData[pactid].payScheduleDays,
                pactData[pactid].employer,
                pactData[pactid].payAmount,
                pactData[pactid].stakeAmount
            );
        
        uint refundAmount_;
        if (isEmployeeDelegate[pactid][msg.sender]) {
            pactState_ = PactState.RESIGNED;
        } else if (isEmployerDelegate[pactid][msg.sender]) {
            // Payment due assumed
            uint paymentDue = (payAmount *
                (block.timestamp - lastPayTimeStamp - pauseDuration)) /
                (payScheduleDays * 86400);
            if (paymentDue >= stakeAmount_) paymentDue = stakeAmount_;

            refundAmount_ = stakeAmount_ - paymentDue;
            pactData[pactid].stakeAmount = uint128(paymentDue);
            pactState_ = PactState.TERMINATED;
        } else revert("Unauthorized");
        pactData[pactid].pactState = pactState_;
        emit LogStateUpdate(pactid, pactState_, msg.sender);

        address erc20TokenAddress = pactData[pactid].erc20TokenAddress;
        if(erc20TokenAddress == address(0)){
            payable(employer).transfer(refundAmount_);
        } else {
            IERC20(erc20TokenAddress).transfer(
                employer,
                refundAmount_
            );
        }
    }

    function fNf(bytes32 pactid, uint tokenAmount) external payable {
        PaymentHelper.fNf(
            address(this),
            pactid,
            tokenAmount,
            pactData[pactid],
            payData[pactid]
        );
    }

    // /* Full and Final Settlement FnF can be initiated by both parties in case they owe something.*/
    // function fNf(bytes32 pactid) external payable {
    //     PactState oldPactState_ = pactData[pactid].pactState;
    //     PactState pactState_ = oldPactState_;
    //     address receiver = address(0);

    //     require(
    //         pactState_ >= PactState.TERMINATED && pactState_ <= PactState.ENDED,
    //         "Wrong State"
    //     );

    //     if (isEmployeeDelegate[pactid][msg.sender]) {
    //         if (
    //             pactState_ == PactState.TERMINATED ||
    //             pactState_ == PactState.RESIGNED
    //         ) {
    //             pactState_ = PactState.FNF_EMPLOYEE;
    //         } else if (
    //             pactState_ == PactState.DISPUTED ||
    //             pactState_ == PactState.ARBITRATED
    //         ) {
    //             pactState_ = PactState.DISPUTE_RESOLVED;
    //         } else if (pactState_ == PactState.FNF_EMPLOYER) {
    //             pactState_ = PactState.FNF_SETTLED;
    //         }
    //         if (msg.value > 0) {
    //             receiver = pactData[pactid].employer;
    //         }
    //     } else if (isEmployerDelegate[pactid][msg.sender]) {
    //         if (
    //             pactState_ == PactState.TERMINATED ||
    //             pactState_ == PactState.RESIGNED
    //         ) {
    //             pactState_ = PactState.FNF_EMPLOYER;
    //         } else if (pactState_ == PactState.FNF_EMPLOYEE) {
    //             pactState_ = PactState.FNF_SETTLED;
    //         }
    //         if (msg.value > 0) {
    //             if (
    //                 pactState_ == PactState.DISPUTED &&
    //                 msg.value >= payData[pactid].proposedAmount
    //             ) {
    //                 pactState_ = PactState.FNF_SETTLED;
    //             }
    //             receiver = pactData[pactid].employee;
    //         }
    //     } else {
    //         revert("Unauthorized");
    //     }
    //     if (oldPactState_ != pactState_) {
    //         pactData[pactid].pactState = pactState_;
    //         emit LogStateUpdate(pactid, pactState_, msg.sender);
    //     }
    //     if (receiver != address(0)) {
    //         // emit LogPaymentMade(pactid, msg.value, msg.sender);
    //         payable(receiver).transfer(msg.value);
    //     }
    // }

    function dispute(bytes32 pactid, uint suggestedAmountClaim) external {
        DisputeHelper.dispute(
            address(this),
            pactid,
            pactData[pactid],
            payData[pactid],
            suggestedAmountClaim
        );
        // require(pactData[pactid].pactState == PactState.FNF_EMPLOYER);
        // pactData[pactid].pactState = PactState.DISPUTED;
        // payData[pactid].proposedAmount = uint128(suggestedAmountClaim);
        // emit LogStateUpdate(pactid, PactState.DISPUTED, msg.sender);
    }

    // function proposeArbitrators(
    //     bytes32 pactid,
    //     address[] calldata proposedArbitrators_
    // ) external onlyParties(pactid) {
    //     PactData storage pactData_ = pactData[pactid];
    //     require(!(pactData_.arbitratorAccepted), "Already Accepted");
    //     require(proposedArbitrators_.length > 0);
    //     require(pactData_.pactState == PactState.DISPUTED, "Not Disputed");
    //     pactData[pactid].arbitratorProposer = msg.sender;
    //     pactData[pactid].arbitratorProposed = true;
    //     delete pactData[pactid].proposedArbitrators;
    //     for (uint i = 0; i < proposedArbitrators_.length; i++) {
    //         pactData[pactid].proposedArbitrators.push(
    //             Arbitrator({addr: proposedArbitrators_[i], hasResolved: false})
    //         );
    //     }
    // }

    function proposeArbitrators(
        bytes32 pactid,
        address[] calldata proposedArbitrators_
    ) external {
        DisputeHelper.proposeArbitrators(
            address(this),
            pactid,
            pactData[pactid],
            proposedArbitrators_
        );
    }

    function acceptOrRejectArbitrators(
        bytes32 pactid,
        bool acceptOrReject
    ) external {
        DisputeHelper.acceptOrRejectArbitrators(
            address(this),
            pactid,
            pactData[pactid],
            acceptOrReject
        );
        // if (pactState_ == PactState.ARBITRATED)
        //     emit LogStateUpdate(pactid, pactState_, msg.sender);
    }

    // function acceptOrRejectArbitrators(
    //     bytes32 pactid,
    //     bool acceptOrReject
    // ) external onlyParties(pactid) {
    //     PactData memory pactData_ = pactData[pactid];
    //     require(
    //         pactData_.pactState == PactState.DISPUTED &&
    //             pactData_.arbitratorProposed
    //     );

    //     if (isEmployeeDelegate[pactid][pactData[pactid].arbitratorProposer]) {
    //         require(isEmployerDelegate[pactid][msg.sender]);
    //     } else {
    //         require(isEmployeeDelegate[pactid][msg.sender]);
    //     }
    //     pactData[pactid].arbitratorAccepted = acceptOrReject;
    //     if (!acceptOrReject) {
    //         pactData[pactid].arbitratorProposed = false;
    //         delete pactData[pactid].proposedArbitrators;
    //     } else {
    //         pactData[pactid].pactState = PactState.ARBITRATED;
    //         emit LogStateUpdate(pactid, PactState.ARBITRATED, msg.sender);
    //     }
    // }

    function arbitratorResolve(bytes32 pactid) external {
        DisputeHelper.arbitratorResolve(pactid, pactData[pactid]);
        // if (pactState_ == PactState.DISPUTE_RESOLVED) {
        //     emit LogStateUpdate(pactid, PactState.DISPUTE_RESOLVED, msg.sender);
        // }
    }

    // function arbitratorResolve(bytes32 pactid) public {
    //     require(
    //         pactData[pactid].pactState == PactState.ARBITRATED,
    //         "Not arbitrated"
    //     );
    //     require(pactData[pactid].arbitratorAccepted, "Arbitrator not accepted");
    //     bool allResolved = true;
    //     Arbitrator[] memory proposedArbitrators_ = pactData[pactid]
    //         .proposedArbitrators;
    //     for (uint i = 0; i < proposedArbitrators_.length; i++) {
    //         if (msg.sender == proposedArbitrators_[i].addr) {
    //             pactData[pactid].proposedArbitrators[i].hasResolved = true;
    //             proposedArbitrators_[i].hasResolved = true;
    //         }
    //         allResolved = allResolved && proposedArbitrators_[i].hasResolved;
    //     }
    //     if (allResolved) {
    //         pactData[pactid].pactState = PactState.DISPUTE_RESOLVED;
    //         emit LogStateUpdate(pactid, PactState.DISPUTE_RESOLVED, msg.sender);
    //     }
    // }

    // function autoWithdraw(bytes32 pactid) external onlyEmployee(pactid) {
    //     require(pactData[pactid].pactState >= PactState.ACTIVE);
    //     require(
    //         block.timestamp - pactData[pactid].lastPayTimeStamp >
    //             2 * pactData[pactid].payScheduleDays * 86400,
    //         "Wait"
    //     );
    //     uint stakeAmount_ = pactData[pactid].stakeAmount;
    //     pactData[pactid].stakeAmount = 0;
    //     pactData[pactid].lastPayAmount = uint128(stakeAmount_);
    //     pactData[pactid].lastPayTimeStamp = uint40(block.timestamp);
    //     pactData[pactid].pactState = PactState.PAUSED;
    //     emit LogStateUpdate(pactid, PactState.PAUSED, msg.sender);
    //     emit LogPaymentMade(pactid, stakeAmount_, address(this));
    //     payable(pactData[pactid].employee).transfer(stakeAmount_);
    // }

    // function contractDataHash(
    //     bytes32 pactid,
    //     uint256 signingDate_) public view returns (bytes32) {
    //         PactData memory pactData_ = pactData[pactid];
    //     return
    //         keccak256(
    //             abi.encodePacked(
    //                 "ChainPact - Simple Gig pact - I hereby agree with the following ",
    //                 "For this pact named ",
    //                 pactData_.pactName,
    //                 "Pact ID",
    //                 pactid,
    //                 "Employee ",
    //                 pactData_.employee,
    //                 "Employer ",
    //                 pactData_.employer,
    //                 "Pay Schedule in days ",
    //                 pactData_.payScheduleDays,
    //                 "payAmount in native ",
    //                 pactData_.payAmount,
    //                 "Signing DateTime ",
    //                 signingDate_,
    //                 "Address of this contract ",
    //                 address(this)
    //             )
    //         );
    // }

    // function recoverContractSigner(bytes32 pactid,
    //     bytes memory signature,
    //     uint256 signingDate_
    // ) internal view returns (address) {
    //     return
    //         ECDSA.recover(
    //             ECDSA.toEthSignedMessageHash(contractDataHash(pactid, signingDate_)),
    //             signature
    //         );
    // }
}
