//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
import "../Structs.sol";
import "../GigPactUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

library PaymentHelper {
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

    function approvePayment(
        PactData storage pactData,
        PayData storage payData
    ) external returns (bool) {
        PactData memory pactData_ = pactData;
        require(pactData_.pactState == PactState.ACTIVE);
        bool result;
        if (pactData_.erc20TokenAddress == address(0)) {
            require(
                msg.value >= pactData_.payAmount,
                "Amount less than payAmount"
            );
            payData.lastPayTimeStamp = uint40(block.timestamp);
            payData.lastPayAmount = uint128(msg.value);
            payData.pauseDuration = 0;
            payable(pactData_.employee).transfer(msg.value);
            result = true;
        } else {
            IERC20 tokenContract = IERC20(pactData_.erc20TokenAddress);
            result = tokenContract.transferFrom(
                msg.sender,
                pactData_.employee,
                pactData_.payAmount
            );
            if (result) {
                payData.lastPayTimeStamp = uint40(block.timestamp);
                payData.lastPayAmount = uint128(pactData_.payAmount);
                payData.pauseDuration = 0;
            }
        }
        if (result) {}
        return result;
    }

    /* Full and Final Settlement FnF can be initiated by both parties in case they owe something.*/
    function fNf(
        address gigPactAddress,
        bytes32 pactid,
        PactData storage pactData,
        PayData storage payData
    ) external {
        PactState oldPactState_ = pactData.pactState;
        PactState pactState_ = oldPactState_;
        address receiver = address(0);

        require(
            pactState_ >= PactState.TERMINATED && pactState_ <= PactState.ENDED,
            "Wrong State"
        );

        if (
            GigPactUpgradeable(gigPactAddress).isEmployeeDelegate(
                pactid,
                msg.sender
            )
        ) {
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
                receiver = pactData.employer;
            }
        } else if (
            GigPactUpgradeable(gigPactAddress).isEmployerDelegate(
                pactid,
                msg.sender
            )
        ) {
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
                    msg.value >= payData.proposedAmount
                ) {
                    pactState_ = PactState.FNF_SETTLED;
                }
                receiver = pactData.employee;
            }
        } else {
            revert("Unauthorized");
        }
        if (oldPactState_ != pactState_) {
            pactData.pactState = pactState_;
            emit LogStateUpdate(pactid, pactState_, msg.sender);
        }
        if (receiver != address(0)) {
            // emit LogPaymentMade(pactid, msg.value, msg.sender);
            payable(receiver).transfer(msg.value);
        }
    }
}
