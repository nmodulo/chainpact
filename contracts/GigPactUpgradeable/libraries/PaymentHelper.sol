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

//NOT USED
    // function addExternalPayClaim(
    //     bytes32 pactid,
    //     uint payTime,
    //     bool confirm,
    //     PayData storage payData
    // ) external {
    //     uint lastExtPayTime = payData.lastExternalPayTimeStamp;
    //     bool existingClaim = payData.claimExternalPay;
    //     if (
    //         GigPactUpgradeable(address(this)).isEmployerDelegate(
    //             pactid,
    //             msg.sender
    //         )
    //     ) {
    //         if (existingClaim || lastExtPayTime == 0) {
    //             payData.lastExternalPayTimeStamp = uint40(payTime);
    //             if (existingClaim) payData.claimExternalPay = false;
    //         }
    //     } else if (
    //         GigPactUpgradeable(address(this)).isEmployeeDelegate(
    //             pactid,
    //             msg.sender
    //         )
    //     ) {
    //         if (!existingClaim && payTime != 0 && payTime == lastExtPayTime) {
    //             if (confirm) payData.claimExternalPay = true;
    //             else delete payData.lastExternalPayTimeStamp;
    //         }
    //     }
    // }

    // function approvePayment(
    //     PactData storage pactData,
    //     PayData storage payData,
    //     uint commissionPercentage_,
    //     address commissionSink_
    // ) external returns (bool) {
    //     PactData memory pactData_ = pactData;
    //     require(pactData_.pactState == PactState.ACTIVE);
    //     bool result;
    //     if (pactData_.erc20TokenAddress == address(0)) {
    //         require(
    //             msg.value >=
    //                 pactData_.payAmount +
    //                     (pactData_.payAmount * commissionPercentage_) /
    //                     100,
    //             "Amount less than payAmount"
    //         );
    //         payData.lastPayTimeStamp = uint40(block.timestamp);
    //         payData.lastPayAmount = uint128(msg.value);
    //         payData.pauseDuration = 0;
    //         payable(commissionSink_).transfer(
    //             (pactData_.payAmount * commissionPercentage_) / 100
    //         );
    //         payable(pactData_.employee).transfer(msg.value);
    //         result = true;
    //     } else {
    //         require(msg.value == 0);    //Should not send any value for token transfers
    //         result = IERC20(pactData_.erc20TokenAddress).transferFrom(
    //             msg.sender,
    //             pactData_.employee,
    //             pactData_.payAmount
    //         );
    //         if (result) {
    //             payData.lastPayTimeStamp = uint40(block.timestamp);
    //             payData.lastPayAmount = uint128(pactData_.payAmount);
    //             payData.pauseDuration = 0;
    //         } else revert();
    //     }
    //     return result;
    // }

    /**
     * Function to claim the stake amount remaining after employer dormancy for more than twice the paySchedule
     * @param pactid Pact UID
     * @param pactData PactData storage ref  
     * @param payData PayData storage ref
     * @param commissionPercent Commission per cent 
     * @param commissionSink Address to send commission to
     */
    function claimAutoPayAfterDormancy(
        bytes32 pactid,
        PactData storage pactData,
        PayData storage payData,
        uint commissionPercent,
        address commissionSink
    ) external{
        require(pactData.pactState != PactState.ENDED);
        require(GigPactUpgradeable(address(this)).isEmployeeDelegate(
                pactid,
                msg.sender
            ));
        require(block.timestamp > 2 * pactData.payScheduleDays * 1 days + payData.lastPayTimeStamp);
        uint remainingStake = pactData.stakeAmount;
        pactData.stakeAmount = 0;
        pactData.pactState = PactState.ENDED;   //Set the pact as ENDED as there is no more stake
        emit LogStateUpdate(pactid, PactState.ENDED, msg.sender);
        emit LogPaymentMade(pactid, remainingStake, address(this));
        payable(commissionSink).transfer((remainingStake * commissionPercent) / 100);
        payable(pactData.employee).transfer((remainingStake * (100 - commissionPercent))/100);
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
        address receiver = address(0);  // To be used to send funds to, depending on who is sending

        //Checks
        require(
            pactState_ >= PactState.TERMINATED && pactState_ <= PactState.ENDED,
            "Wrong State"
        );

        if (//Checks
            GigPactUpgradeable(address(this)).isEmployeeDelegate(
                pactid,
                msg.sender
            )
        ) { //If the employee or delegate is sending the payment
            if (
                pactState_ == PactState.TERMINATED ||
                pactState_ == PactState.RESIGNED
            ) {
                pactState_ = PactState.FNF_EMPLOYEE;    // Employee has signed off full and final first
            } else if (
                pactState_ == PactState.DISPUTED ||
                pactState_ == PactState.ARBITRATED
            ) {
                pactState_ = PactState.DISPUTE_RESOLVED;    // Employee has no further reasons to dispute
            } else if (pactState_ == PactState.FNF_EMPLOYER) {  
                pactState_ = PactState.FNF_SETTLED;         // Employee is happy with Employer's FnF
            }
            if (
                (pactData.erc20TokenAddress == address(0) && msg.value > 0) ||
                (tokenAmount != 0 && pactData.erc20TokenAddress != address(0))
            ) {
                receiver = pactData.employer;       // The value or token amount to be sent to the employer address only
            }
        } else if ( //Checks
            GigPactUpgradeable(address(this)).isEmployerDelegate(
                pactid,
                msg.sender
            )
        ) { // If the sender is Employer or a delegatee
            if (
                pactState_ == PactState.TERMINATED ||
                pactState_ == PactState.RESIGNED
            ) {
                pactState_ = PactState.FNF_EMPLOYER;    // Employer has sent the FnF first    
            } else if (pactState_ == PactState.FNF_EMPLOYEE) {
                pactState_ = PactState.FNF_SETTLED;     // Employer is happy with Employee's FnF too
            }
            if (
                (pactData.erc20TokenAddress == address(0) && msg.value > 0) ||
                (tokenAmount != 0 && pactData.erc20TokenAddress != address(0))
            ) {
                receiver = pactData.employee;           // The value or token amount to be sent to the employee address
            }
        } else {
            revert("Unauthorized");                        //Checks
        }
        if (oldPactState_ != pactState_) {
            pactData.pactState = pactState_;                //Effects
            emit LogStateUpdate(pactid, pactState_, msg.sender);
        }
        if (receiver != address(0)) {       // There is no receiver set in case of zero payment FnF
            if (
                pactState_ == PactState.DISPUTED &&
                receiver == pactData.employee &&
                (msg.value >= payData.proposedAmount ||
                    tokenAmount >= payData.proposedAmount)
            ) {
                pactState_ = PactState.FNF_SETTLED;
            }
            if (tokenAmount == 0) {
                emit LogPaymentMade(pactid, msg.value, msg.sender);
                require(payable(receiver).send(msg.value));             //Interaction
            } else {
                emit LogPaymentMade(pactid, tokenAmount, msg.sender);
                require(msg.value == 0);
                require(
                    IERC20(pactData.erc20TokenAddress).transferFrom(    //Interaction
                        msg.sender,
                        receiver,
                        tokenAmount
                    )
                );
            }
        }
    }
}
