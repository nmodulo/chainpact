//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
import "../Structs.sol";
import "../GigPactUpgradeable.sol";


library DisputeHelper{
    function add() external pure returns (uint){
        return 2;
    }
    event LogStateUpdate(
        bytes32 indexed pactid,
        PactState newState,
        address indexed updater
    );

    function dispute(
        address gigPactAddress,
        bytes32 pactid,
        PactData storage pactData_,
        PayData storage payData_,
        uint suggestedAmountClaim
    ) external {
        require(GigPactUpgradeable(gigPactAddress).isEmployeeDelegate(pactid, msg.sender), "Unauthorized");
        require(pactData_.pactState == PactState.FNF_EMPLOYER);
        pactData_.pactState = PactState.DISPUTED;
        payData_.proposedAmount = uint128(suggestedAmountClaim);
        emit LogStateUpdate(pactid, PactState.DISPUTED, msg.sender);
    }

    function proposeArbitrators(
        address gigPactAddress,
        bytes32 pactid,
        PactData storage pactData_,
        address[] calldata proposedArbitrators_
    ) external {
        // PactData storage pactData_ = pactData_;
        require(
            GigPactUpgradeable(gigPactAddress).isEmployeeDelegate(pactid, msg.sender)
            || GigPactUpgradeable(gigPactAddress).isEmployerDelegate(pactid, msg.sender)
            );
        require(!(pactData_.arbitratorAccepted), "Already Accepted");
        require(proposedArbitrators_.length > 0);
        require(pactData_.pactState == PactState.DISPUTED, "Not Disputed");
        pactData_.arbitratorProposer = msg.sender;
        pactData_.arbitratorProposed = true;
        delete pactData_.proposedArbitrators;
        for (uint i = 0; i < proposedArbitrators_.length; i++) {
            pactData_.proposedArbitrators.push(
                Arbitrator({addr: proposedArbitrators_[i], hasResolved: false})
            );
        }
    }

    function acceptOrRejectArbitrators(
        address gigPactAddress,
        bytes32 pactid,
        PactData storage pactData,
        // PayData memory payData_,
        bool acceptOrReject
    ) external returns (PactState){
        PactData memory pactData_ = pactData;
        require(
            pactData_.pactState == PactState.DISPUTED &&
                pactData_.arbitratorProposed
        );

        if (GigPactUpgradeable(gigPactAddress).isEmployeeDelegate(pactid, pactData_.arbitratorProposer)) {
            require(GigPactUpgradeable(gigPactAddress).isEmployerDelegate(pactid,msg.sender));
        } else if(GigPactUpgradeable(gigPactAddress).isEmployerDelegate(pactid, pactData_.arbitratorProposer)) {
            require(GigPactUpgradeable(gigPactAddress).isEmployeeDelegate(pactid,msg.sender));
        } else revert("only parties");
        pactData.arbitratorAccepted = acceptOrReject;
        if (!acceptOrReject) {
            pactData.arbitratorProposed = false;
            delete pactData.proposedArbitrators;
            return pactData_.pactState;
        } else {
            pactData.pactState = PactState.ARBITRATED;
            emit LogStateUpdate(pactid, PactState.ARBITRATED, msg.sender);
            return PactState.ARBITRATED;
        }
    }

    function arbitratorResolve(
        bytes32 pactid,
        PactData storage pactData_
        // PayData memory payData_,
        ) external returns (PactState){
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
            // return PactState.DISPUTE_RESOLVED;
            emit LogStateUpdate(pactid, PactState.DISPUTE_RESOLVED, msg.sender);
        } else {
            emit LogStateUpdate(pactid, PactState.DISPUTE_RESOLVED, msg.sender);
            return PactState.ARBITRATED;
        }
    }
}