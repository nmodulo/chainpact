//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library PactSignature {
    function contractDataHash(
       bytes32 pactName,
       bytes32 pactid,
       address employee,
       address employer,
       uint payScheduleDays,
       uint payAmount,
       uint256 signingDate_) public pure returns (bytes32) {
            // PactData memory pactData_ = pactData[pactid];
        return
            keccak256(
                abi.encodePacked(
                    "ChainPact - Simple Gig pact - I hereby agree with the following ",
                    "For this pact named "
                    ,
                    pactName,
                    "Pact ID",
                    pactid,
                    "Employee ",
                    employee,
                    "Employer ",
                    employer,
                    "Pay Schedule in days ",
                    payScheduleDays,
                    "payAmount in native ",
                    payAmount,
                    "Signing DateTime ",
                    signingDate_
                )
            );
    }

    function recoverContractSigner(
        bytes memory signature,
        bytes32 dataHash
    ) public pure returns (address) {
        return
            ECDSA.recover(
                ECDSA.toEthSignedMessageHash(dataHash),
                signature
            );
    }
}

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
    END_ACCEPTED,
    FNF_EMPLOYER,
    FNF_EMPLOYEE,
    DISPUTED,
    ARBITRATED,
    FNF_SETTLED,
    DISPUTE_RESOLVED,
    ENDED
}

struct PactData {
    bytes32 pactName;
    address employee;
    uint40 employeeSignDate;
    PactState pactState;
    bool arbitratorAccepted;
    bool arbitratorProposed;
    uint32 payScheduleDays; 
    
    address employer;
    uint128 payAmount;
    uint128 stakeAmount;
    address arbitratorProposer;
    Arbitrator[] proposedArbitrators;
}

struct PayData{
    uint40 pauseDuration;
    uint40 pauseResumeTime;
    uint40 lastPayTimeStamp;
    uint128 lastPayAmount;
    uint128 proposedAmount;
}

struct Arbitrator {
    address addr;
    bool hasResolved;
}


contract GigPactUpgradeable {
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
    event LogPactCreated(
        address indexed creator,
        bytes32 pactid
    );

    //BAU
    mapping(bytes32 => PactData) internal pactData;
    mapping(bytes32 => PayData) internal payData;
    uint pactsCounter;

    //Constraint flags
    mapping(bytes32 => mapping(address => bool)) public isEmployeeDelegate;
    mapping(bytes32 => mapping(address => bool)) public isEmployerDelegate;

    function getAllPactData(bytes32 pactid) external view returns (
        PactData memory, PayData memory, Arbitrator[] memory){
        return (pactData[pactid], payData[pactid], pactData[pactid].proposedArbitrators);
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

    modifier onlyParties(bytes32 pactid) {
        require(
            isEmployeeDelegate[pactid][msg.sender] ||
                isEmployerDelegate[pactid][msg.sender],
            "only parties"
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

    //done dec 29
    function createPact(
        bytes32 pactName_,
        address employee_,
        address employer_,
        uint32 payScheduleDays_,
        uint128 payAmount_
    ) external {
        require(payAmount_ > 0 && pactName_ != 0);
        bytes32 uid = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                "chainpact_gigpact",
                pactsCounter
            )
        );
        pactData[uid].pactName = pactName_ ;
        pactData[uid].employee = employee_ ;
        pactData[uid].employer = employer_ ;
        pactData[uid].payScheduleDays = payScheduleDays_ ;
        pactData[uid].payAmount = payAmount_ ;
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
        PactData memory pactData_ = pactData[pactid];
        require(pactData_.pactState < PactState.ALL_SIGNED, "Already signed");
        bytes32 contractDataHash_ = PactSignature.contractDataHash(
            pactData_.pactName, 
            pactid, pactData_.employee, 
            pactData_.employer, 
            pactData_.payScheduleDays, 
            pactData_.payAmount, 
            signingDate_);
        address signer_ = PactSignature.recoverContractSigner(signature, contractDataHash_);

        PactState newPactState = PactState.EMPLOYER_SIGNED;
        if(msg.sender == pactData_.employer ){
            require(msg.value >= pactData_.payAmount, "Less Stake");
            require(signer_ == pactData_.employer, "Incorrect signature");
            pactData[pactid].stakeAmount = uint128(msg.value);
        } else if (msg.sender == pactData_.employee ){
            require(signer_ == pactData_.employee, "Incorrect signature");
            newPactState = PactState.EMPLOYEE_SIGNED;
            pactData[pactid].employeeSignDate = uint40(signingDate_);
        } else revert("Unauthorized");
        
        if(pactData_.pactState >= PactState.EMPLOYER_SIGNED){
            newPactState = PactState.ALL_SIGNED;
        }
        pactData[pactid].pactState = newPactState;
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

    function delegate(
        bytes32 pactid,
        address[] calldata delegates, 
        bool addOrRevoke) external {
        require(pactData[pactid].pactState >= PactState.ALL_SIGNED);
        if (msg.sender == pactData[pactid].employer) {
            for (uint i = 0; i < delegates.length; i++) {
                isEmployerDelegate[pactid][delegates[i]] = addOrRevoke;
            }
        }
        else if (msg.sender == pactData[pactid].employee) {
            for (uint i = 0; i < delegates.length; i++) {
                isEmployeeDelegate[pactid][delegates[i]] = addOrRevoke;
            }
        }
        else {
            revert();
        }
    }

    function startPause(bytes32 pactid, bool toStart) external onlyEmployer(pactid){
        PayData memory payData_ = payData[pactid];
        PactState updatedState_ = pactData[pactid].pactState;

        if(toStart){
            if(updatedState_ == PactState.ALL_SIGNED){
                updatedState_ = PactState.ACTIVE;
                payData_.lastPayTimeStamp = uint40(block.timestamp);
                payData_.lastPayAmount = 0;
            } else if(updatedState_ == PactState.PAUSED){
                payData_.pauseDuration += uint40(block.timestamp) - payData_.pauseResumeTime;
                payData_.pauseResumeTime = uint40(block.timestamp);
            } else revert();
            updatedState_ = PactState.ACTIVE;
        } else if (pactData[pactid].pactState == PactState.ACTIVE){
            updatedState_ = PactState.PAUSED;
            payData_.pauseResumeTime = uint40(block.timestamp);
        } else revert();
        payData[pactid] = payData_;
        pactData[pactid].pactState = updatedState_;
        emit LogStateUpdate(pactid, updatedState_, msg.sender);
    }

    // function start(bytes32 pactid) external onlyEmployer(pactid) {
    //     require(pactData[pactid].pactState == PactState.ALL_SIGNED || pactData[pactid].pactState == PactState.PAUSED);
    //     pactData[pactid].pactState = PactState.ACTIVE;

    //     payData[pactid].lastPayTimeStamp = uint40(block.timestamp);
    //     payData[pactid].lastPayAmount = 0;
    //     emit LogStateUpdate(pactid,PactState.ACTIVE, msg.sender);
    // }

    // function pause(bytes32 pactid) external onlyParties(pactid) isActive(pactid) {
    //     pactData[pactid].pactState = PactState.PAUSED;
    //     payData[pactid].pauseResumeTime = uint40(block.timestamp);
    //     emit LogStateUpdate(pactid, PactState.PAUSED, msg.sender);
    // }

    // function resume(bytes32 pactid) external onlyParties(pactid) {
    //     require(pactData[pactid].pactState == PactState.PAUSED);
    //     pactData[pactid].pactState = PactState.ACTIVE;
    //     payData[pactid].pauseDuration += uint40(block.timestamp) - payData[pactid].pauseResumeTime;
    //     payData[pactid].pauseResumeTime = uint40(block.timestamp);
    //     emit LogStateUpdate(pactid, PactState.ACTIVE, msg.sender);
    // }

    function approvePayment(bytes32 pactid) external payable onlyEmployer(pactid) isActive(pactid) {
        require(msg.value >= pactData[pactid].payAmount, "Amount less than payAmount");
        payData[pactid].lastPayTimeStamp = uint40(block.timestamp);
        payData[pactid].lastPayAmount = uint128(msg.value);
        payData[pactid].pauseDuration = 0;
        payable(pactData[pactid].employee).transfer(msg.value);
        emit LogPaymentMade(pactid, msg.value, msg.sender);
    }

    function terminate(bytes32 pactid) external isEOA isActive(pactid) {
        PactData memory pactData_ = pactData[pactid];
        PayData memory payData_ = payData[pactid];
        if(isEmployeeDelegate[pactid][msg.sender]){
            pactData_.pactState = PactState.RESIGNED;
        } else if( isEmployerDelegate[pactid][msg.sender]){
            // Payment due assumed
            uint paymentDue = (pactData_.payAmount *
            (block.timestamp - payData_.lastPayTimeStamp - payData_.pauseDuration)) /
            (pactData_.payScheduleDays * 86400);
            if (paymentDue >= pactData_.stakeAmount) paymentDue = pactData_.stakeAmount;

            uint refundAmount_ = pactData_.stakeAmount - paymentDue;
            pactData[pactid].stakeAmount = uint128(paymentDue);
            pactData_.pactState = PactState.TERMINATED;
            payable(pactData_.employer).transfer(refundAmount_);
        } else revert("Unauthorized");
        pactData[pactid].pactState = pactData_.pactState;
        emit LogStateUpdate(pactid, pactData_.pactState, msg.sender);
    }

    /* Full and Final Settlement FnF can be initiated by both parties in case they owe something.*/
    function fNf(bytes32 pactid) external payable {
        PactState oldPactState_ = pactData[pactid].pactState;
        PactState pactState_ = oldPactState_;
        address receiver = address(0);

        require(
            pactState_ >= PactState.TERMINATED && pactState_ <= PactState.ENDED,
            "Wrong State"
        );

        if (isEmployeeDelegate[pactid][msg.sender]) {
            if (
                pactState_ == PactState.TERMINATED ||
                pactState_ == PactState.RESIGNED
            ) {
                pactState_ = PactState.FNF_EMPLOYEE;
            } else if (
                pactState_ == PactState.DISPUTED ||
                pactState_ == PactState.ARBITRATED
            ) {
                pactState_ = PactState.DISPUTE_RESOLVED;
            } else if (pactState_ == PactState.FNF_EMPLOYER) {
                pactState_ = PactState.FNF_SETTLED;
            }
            if (msg.value > 0) {
                receiver = pactData[pactid].employer;
            }
        } else if (isEmployerDelegate[pactid][msg.sender]) {
            if (
                pactState_ == PactState.TERMINATED ||
                pactState_ == PactState.RESIGNED
            ) {
                pactState_ = PactState.FNF_EMPLOYER;
            } else if (pactState_ == PactState.FNF_EMPLOYEE) {
                pactState_ = PactState.FNF_SETTLED;
            }
            if (msg.value > 0) {
                if (
                    pactState_ == PactState.DISPUTED &&
                    msg.value >= payData[pactid].proposedAmount
                ) {
                    pactState_ = PactState.FNF_SETTLED;
                }
                receiver = pactData[pactid].employee;
            }
        } else {
            revert("Unauthorized");
        }
        if (oldPactState_ != pactState_) {
            pactData[pactid].pactState = pactState_;
            emit LogStateUpdate(pactid, pactState_, msg.sender);
        }
        if (receiver != address(0)) {
            emit LogPaymentMade(pactid, msg.value, msg.sender);
            payable(receiver).transfer(msg.value);
        }
    }

    function dispute(
        bytes32 pactid, 
        uint suggestedAmountClaim) external onlyEmployee(pactid) {
        require(pactData[pactid].pactState == PactState.FNF_EMPLOYER);
        pactData[pactid].pactState = PactState.DISPUTED;
        payData[pactid].proposedAmount = uint128(suggestedAmountClaim);
        emit LogStateUpdate(pactid, PactState.DISPUTED, msg.sender);
    }

    function proposeArbitrators(
        bytes32 pactid, 
        address[] calldata proposedArbitrators_
    ) external onlyParties(pactid) {
        PactData storage pactData_ = pactData[pactid];
        require(!(pactData_.arbitratorAccepted), "Already Accepted");
        require(proposedArbitrators_.length > 0);
        require(pactData_.pactState == PactState.DISPUTED, "Not Disputed");
        pactData[pactid].arbitratorProposer = msg.sender;
        pactData[pactid].arbitratorProposed = true;
        delete pactData[pactid].proposedArbitrators;
        for (uint i = 0; i < proposedArbitrators_.length; i++) {
            pactData[pactid].proposedArbitrators.push(
                Arbitrator({addr: proposedArbitrators_[i], hasResolved: false})
            );
        }
    }

    function acceptOrRejectArbitrators(
        bytes32 pactid, 
        bool acceptOrReject) external onlyParties(pactid) {
        
        PactData memory pactData_ = pactData[pactid];
        require(
            pactData_.pactState == PactState.DISPUTED && pactData_.arbitratorProposed
        );

        if (isEmployeeDelegate[pactid][pactData[pactid].arbitratorProposer]) {
            require(isEmployerDelegate[pactid][msg.sender]);
        } else {
            require(isEmployeeDelegate[pactid][msg.sender]);
        }
        pactData[pactid].arbitratorAccepted = acceptOrReject;
        if (!acceptOrReject) {
            pactData[pactid].arbitratorProposed = false;
            delete pactData[pactid].proposedArbitrators;
        } else {
            pactData[pactid].pactState = PactState.ARBITRATED;
            emit LogStateUpdate(pactid, PactState.ARBITRATED, msg.sender);
        }
    }

    // function getArbitratorsList(bytes32 pactid)
    //     external
    //     view
    //     returns (Arbitrator[] memory arbitrators)
    // {
    //     return pactData[pactid].proposedArbitrators;
    // }

    function arbitratorResolve(bytes32 pactid) public {
        require(pactData[pactid].pactState == PactState.ARBITRATED, "Not arbitrated");
        require(pactData[pactid].arbitratorAccepted, "Arbitrator not accepted");
        bool allResolved = true;
        Arbitrator[] memory proposedArbitrators_ = pactData[pactid]
            .proposedArbitrators;
        for (uint i = 0; i < proposedArbitrators_.length; i++) {
            if (msg.sender == proposedArbitrators_[i].addr) {
                pactData[pactid].proposedArbitrators[i].hasResolved = true;
                proposedArbitrators_[i].hasResolved = true;
            }
            allResolved = allResolved && proposedArbitrators_[i].hasResolved;
        }
        if (allResolved) {
            pactData[pactid].pactState = PactState.DISPUTE_RESOLVED;
            emit LogStateUpdate(pactid, PactState.DISPUTE_RESOLVED, msg.sender);
        }
    }

    /** To get the remaining stake by the employer when the contract has been ended. */
    function reclaimStake(
        bytes32 pactid,
        address payable payee) external onlyEmployer(pactid) isEOA {
        PactState pactState_ = pactData[pactid].pactState;
        require(payee != address(0));
        uint stakeAmount_ = pactData[pactid].stakeAmount;
        require(stakeAmount_ > 0);
        if(pactState_ >= PactState.FNF_SETTLED){
            pactState_ = PactState.ENDED;
        } else if(pactData[pactid].pactState < PactState.EMPLOYEE_SIGNED){
            pactState_ = PactState.RETRACTED;
        } else revert();
        emit LogPaymentMade(pactid, stakeAmount_, address(this));
        emit LogStateUpdate(pactid, pactState_, msg.sender);
        pactData[pactid].pactState = pactState_;
        pactData[pactid].stakeAmount = 0;
        payee.transfer(stakeAmount_);
    }

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
