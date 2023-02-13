//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
import "../Structs.sol";
import "../GigPactUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

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

    function addExternalPayClaim(
        bytes32 pactid,
        uint payTime,
        bool confirm,
        PayData storage payData
    ) external {
        uint lastExtPayTime = payData.lastExternalPayTimeStamp;
        bool existingClaim = payData.claimExternalPay;
        if (
            GigPactUpgradeable(address(this)).isEmployerDelegate(
                pactid,
                msg.sender
            )
        ) {
            if (existingClaim || lastExtPayTime == 0) {
                payData.lastExternalPayTimeStamp = uint40(payTime);
                if (existingClaim) payData.claimExternalPay = false;
            }
        } else if (
            GigPactUpgradeable(address(this)).isEmployeeDelegate(
                pactid,
                msg.sender
            )
        ) {
            if (!existingClaim && payTime != 0 && payTime == lastExtPayTime) {
                if (confirm) payData.claimExternalPay = true;
                else delete payData.lastExternalPayTimeStamp;
            }
        }
    }

    function approvePayment(
        PactData storage pactData,
        PayData storage payData,
        uint commissionPercentage_,
        address commissionSink_
    ) external returns (bool) {
        PactData memory pactData_ = pactData;
        require(pactData_.pactState == PactState.ACTIVE);
        bool result;
        if (pactData_.erc20TokenAddress == address(0)) {
            require(
                msg.value >=
                    pactData_.payAmount +
                        (pactData_.payAmount * commissionPercentage_) /
                        100,
                "Amount less than payAmount"
            );
            payData.lastPayTimeStamp = uint40(block.timestamp);
            payData.lastPayAmount = uint128(msg.value);
            payData.pauseDuration = 0;
            payable(commissionSink_).transfer(
                (pactData_.payAmount * commissionPercentage_) / 100
            );
            payable(pactData_.employee).transfer(msg.value);
            result = true;
        } else {
            require(msg.value == 0);
            result = IERC20(pactData_.erc20TokenAddress).transferFrom(
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
        bytes32 pactid,
        uint tokenAmount,
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
            GigPactUpgradeable(address(this)).isEmployeeDelegate(
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
            if (
                (pactData.erc20TokenAddress == address(0) && msg.value > 0) ||
                (tokenAmount != 0 && pactData.erc20TokenAddress != address(0))
            ) {
                receiver = pactData.employer;
            }
        } else if (
            GigPactUpgradeable(address(this)).isEmployerDelegate(
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
            if (
                (pactData.erc20TokenAddress == address(0) && msg.value > 0) ||
                (tokenAmount != 0 && pactData.erc20TokenAddress != address(0))
            ) {
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
            emit LogPaymentMade(pactid, msg.value, msg.sender);
            if (
                pactState_ == PactState.DISPUTED &&
                receiver == pactData.employee &&
                (msg.value >= payData.proposedAmount ||
                    tokenAmount >= payData.proposedAmount)
            ) {
                pactState_ = PactState.FNF_SETTLED;
            }
            if (tokenAmount == 0) {
                require(payable(receiver).send(msg.value));
            } else {
                require(msg.value == 0);
                require(
                    IERC20(pactData.erc20TokenAddress).transferFrom(
                        msg.sender,
                        receiver,
                        tokenAmount
                    )
                );
            }
        }
    }
}
