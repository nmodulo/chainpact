//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../Structs.sol";

library PactSignature {
    function contractDataHash(
        bytes32 pactName,
        bytes32 pactid,
        address employee,
        address employer,
        uint payScheduleDays,
        uint payAmount,
        uint256 signingDate_
    ) public pure returns (bytes32) {
        // PactData memory pactData_ = pactData[pactid];
        return
            keccak256(
                abi.encodePacked(
                    "ChainPact - Simple Gig pact - I hereby agree with the following ",
                    "For this pact named ",
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
        return ECDSA.recover(ECDSA.toEthSignedMessageHash(dataHash), signature);
    }

    function checkSignPact(
        bytes32 pactid,
        PactData storage pactData,
        bytes calldata signature,
        uint256 signingDate_
    ) public returns (PactState) {
        PactData memory pactData_ = pactData;
        require(pactData_.pactState < PactState.ALL_SIGNED, "Already signed");
        bytes32 contractDataHash_ = contractDataHash(
            pactData_.pactName,
            pactid,
            pactData_.employee,
            pactData_.employer,
            pactData_.payScheduleDays,
            pactData_.payAmount,
            signingDate_
        );
        address signer_ = recoverContractSigner(signature, contractDataHash_);

        PactState newPactState = PactState.EMPLOYER_SIGNED;
        if (msg.sender == pactData_.employer) {
            if (pactData_.erc20TokenAddress == address(0)) {
                require(msg.value >= pactData_.payAmount, "Less Stake");
                pactData.stakeAmount = uint128(msg.value);
            } else {
                bool result = IERC20(pactData_.erc20TokenAddress).transferFrom(
                    msg.sender,
                    address(this),
                    pactData_.payAmount
                );
                require(result, "Token transfer failed");
                pactData.stakeAmount = pactData.payAmount;
            }
            require(signer_ == pactData_.employer, "Incorrect signature");
        } else if (msg.sender == pactData_.employee) {
            require(signer_ == pactData_.employee, "Incorrect signature");
            newPactState = PactState.EMPLOYEE_SIGNED;
            pactData.employeeSignDate = uint40(signingDate_);
        } else revert("Unauthorized");

        if (pactData_.pactState >= PactState.EMPLOYER_SIGNED) {
            newPactState = PactState.ALL_SIGNED;
        }
        pactData.pactState = newPactState;
        return newPactState;
        // emit LogStateUpdate(pactid, newPactState, msg.sender);
    }
}
