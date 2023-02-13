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
import "../Interface/ChainPact.sol";

/**
 * @title ChainPact main logic contract
 * @author Somnath B
 * @notice Still in pre-alpha stage, report issues to chainpact@nmodulo.com
 * 
 */

contract GigPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ChainPact
{
    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        uint commissionPercentage_,
        address commissionSink_
    ) public initializer {
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

    //Data

    uint private pactsCounter;
    mapping(bytes32 => PactData) public pactData;
    mapping(bytes32 => PayData) public payData;
    mapping(bytes32 => mapping(address => bool)) public isEmployeeDelegate;
    mapping(bytes32 => mapping(address => bool)) public isEmployerDelegate;
    mapping(bytes32 => bytes32) public externalDocumentHash;
    uint private commissionPercentage; //
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

    function isParty(bytes32 pactid, address party) public view returns (bool) {
        return
            isEmployeeDelegate[pactid][party] ||
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
    ) external isEOA {
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
        require(pactData[uid].pactState == PactState.NULL);
        pactData[uid].pactState = PactState.DEPLOYED;
        pactData[uid].pactName = pactName_;
        pactData[uid].employee = employee_;
        pactData[uid].payScheduleDays = payScheduleDays_;
        pactData[uid].employer = employer_;
        if (erc20TokenAddress_ != address(0))
            pactData[uid].erc20TokenAddress = erc20TokenAddress_;
        pactData[uid].payAmount = payAmount_;
        if (externalDocumentHash_ != 0)
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

    function addExternalPayClaim(
        bytes32 pactid,
        uint payTime,
        bool confirm
    ) external isActive(pactid) {

        PaymentHelper.addExternalPayClaim(pactid, payTime, confirm, payData[pactid]);
    }

    function approvePayment(
        bytes32 pactid
    ) external payable onlyEmployer(pactid) isActive(pactid) {
        (address employee, uint payAmount, address erc20TokenAddress) = (
            pactData[pactid].employee,
            pactData[pactid].payAmount,
            pactData[pactid].erc20TokenAddress
        );

        bool result;
        if (erc20TokenAddress == address(0)) {
            require(
                msg.value >=
                    payAmount + (payAmount * commissionPercentage) / 100,
                "Amount less than payAmount"
            );
            require(
                payable(commissionSink).send(
                    (payAmount * commissionPercentage) / 100
                )
            );
            result = payable(employee).send(
                msg.value - (payAmount * commissionPercentage) / 100
            );
            // require(result);
            // result = true;
        } else {
            // IERC20 tokenContract = IERC20(pactData_.erc20TokenAddress);
            require(
                IERC20(erc20TokenAddress).transferFrom(
                    msg.sender,
                    commissionSink,
                    (payAmount * commissionPercentage) / 100
                )
            );
            result = IERC20(erc20TokenAddress).transferFrom(
                msg.sender,
                employee,
                payAmount
            );
        }
        if (result) {
            payData[pactid].lastPayTimeStamp = uint40(block.timestamp);
            payData[pactid].lastPayAmount = uint128(
                erc20TokenAddress == address(0)
                    ? msg.value - (payAmount * commissionPercentage) / 100
                    : payAmount
            );
            payData[pactid].pauseDuration = 0;
            emit LogPaymentMade(pactid, msg.value, msg.sender);
        } else {
            revert();
        }
    }

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
        } else if (pactState_ == PactState.EMPLOYER_SIGNED) {
            pactState_ = PactState.RETRACTED;
        } else revert();
        // emit LogPaymentMade(pactid, stakeAmount_, address(this));
        bool result;

        pactData[pactid].stakeAmount = 0;
        pactData[pactid].pactState = pactState_;
        emit LogStateUpdate(pactid, pactState_, msg.sender);

        if (pactData[pactid].erc20TokenAddress == address(0)) {
            result = payee.send(stakeAmount_);
        } else {
            result = IERC20(pactData[pactid].erc20TokenAddress).transfer(
                payee,
                stakeAmount_
            );
        }
        if(!result) revert();
    }

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

        uint refundAmount_ = 0;
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
        if (erc20TokenAddress == address(0)) {
            payable(employer).transfer(refundAmount_);
        } else {
            require(IERC20(erc20TokenAddress).transfer(employer, refundAmount_));
        }
    }

    function fNf(bytes32 pactid, uint tokenAmount) external payable {
        PaymentHelper.fNf(
            pactid,
            tokenAmount,
            pactData[pactid],
            payData[pactid]
        );
    }

    function dispute(bytes32 pactid, uint suggestedAmountClaim) external {
        DisputeHelper.dispute(
            pactid,
            pactData[pactid],
            payData[pactid],
            suggestedAmountClaim
        );
    }


    function proposeArbitrators(
        bytes32 pactid,
        address[] calldata proposedArbitrators_
    ) external {
        DisputeHelper.proposeArbitrators(
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
            pactid,
            pactData[pactid],
            acceptOrReject
        );
    }

    function arbitratorResolve(bytes32 pactid) external {
        DisputeHelper.arbitratorResolve(pactid, pactData[pactid]);
    }
}
