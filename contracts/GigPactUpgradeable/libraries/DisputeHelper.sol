//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
import "../Structs.sol";
import "../GigPactUpgradeable.sol";

library DisputeHelper{

    event LogStateUpdate(
        bytes32 indexed pactid,
        PactState newState,
        address indexed updater
    );
    event LogPactAction(
        bytes32 indexed pactid
    );


    function dispute(
        bytes32 pactid,
        PactData storage pactData_,
        PayData storage payData_,
        uint suggestedAmountClaim
    ) external {
        require(GigPactUpgradeable(address(this)).isEmployeeDelegate(pactid, msg.sender), "employee delegate only");
        require(pactData_.pactState == PactState.FNF_EMPLOYER);
        pactData_.pactState = PactState.DISPUTED;
        payData_.proposedAmount = uint128(suggestedAmountClaim);
        emit LogStateUpdate(pactid, PactState.DISPUTED, msg.sender);
    }

    function proposeArbitrators(
        bytes32 pactid,
        PactData storage pactData_,
        address[] calldata proposedArbitrators_
    ) external {
        // PactData storage pactData_ = pactData_;
        require(
            GigPactUpgradeable(address(this)).isEmployeeDelegate(pactid, msg.sender)
            || GigPactUpgradeable(address(this)).isEmployerDelegate(pactid, msg.sender)
            );
        require(!(pactData_.arbitratorAccepted), "Already Accepted");
        require(proposedArbitrators_.length > 0);
        require(proposedArbitrators_.length <= 30);  /// @dev don't allow too many arbitrators for gas considerations 
        require(pactData_.pactState == PactState.DISPUTED, "Not Disputed");
        pactData_.arbitratorProposer = msg.sender;
        pactData_.arbitratorProposedFlag = true;
        delete pactData_.proposedArbitrators;
        for (uint i = 0; i < proposedArbitrators_.length; i++) {
            pactData_.proposedArbitrators.push(
                Arbitrator({addr: proposedArbitrators_[i], hasResolved: false})
            );
        }
        emit LogPactAction(pactid);
    }

    function acceptOrRejectArbitrators(
        bytes32 pactid,
        PactData storage pactData,
        // PayData memory payData_,
        bool acceptOrReject
    ) external {
        PactData memory pactData_ = pactData;
        require(
            pactData_.pactState == PactState.DISPUTED &&
                pactData_.arbitratorProposedFlag
        );

        if (GigPactUpgradeable(address(this)).isEmployeeDelegate(pactid, pactData_.arbitratorProposer)) {
            require(GigPactUpgradeable(address(this)).isEmployerDelegate(pactid,msg.sender));
        } else if(GigPactUpgradeable(address(this)).isEmployerDelegate(pactid, pactData_.arbitratorProposer)) {
            require(GigPactUpgradeable(address(this)).isEmployeeDelegate(pactid,msg.sender));
        } else revert("only parties");
        pactData.arbitratorAccepted = acceptOrReject;
        if (!acceptOrReject) {
            pactData.arbitratorProposedFlag = false;
            delete pactData.proposedArbitrators;
            emit LogPactAction(pactid);
        } else {
            pactData.pactState = PactState.ARBITRATED;
            emit LogStateUpdate(pactid, PactState.ARBITRATED, msg.sender);
        }
    }

    function arbitratorResolve(
        bytes32 pactid,
        PactData storage pactData_
        // PayData memory payData_,
        ) external {
        require(
            pactData_.pactState == PactState.ARBITRATED,
            "Not arbitrated"
        );
        require(pactData_.arbitratorAccepted, "Arbitrator not accepted");
        bool allResolved = true;
        Arbitrator[] memory proposedArbitrators_ = pactData_
            .proposedArbitrators;
        for (uint i = 0; i < proposedArbitrators_.length; i++) {
            if (msg.sender == proposedArbitrators_[i].addr) {
                pactData_.proposedArbitrators[i].hasResolved = true;
                proposedArbitrators_[i].hasResolved = true;
            }
            allResolved = allResolved && proposedArbitrators_[i].hasResolved;
        }
        if (allResolved) {
            pactData_.pactState = PactState.DISPUTE_RESOLVED;
            emit LogStateUpdate(pactid, PactState.DISPUTE_RESOLVED, msg.sender);
            // return PactState.DISPUTE_RESOLVED;
        }
        emit LogPactAction(pactid);
    }
}