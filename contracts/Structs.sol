//SPDX-License-Identifier: MIT
pragma solidity >0.8.4 <= 0.8.17;

struct CoreData {
    bytes32 pactName;
    address employee;
    address employer;
    uint128 payScheduleDays;
    uint128 payAmount;
}

struct Arbitrator {
    address addr;
    bool    hasResolved;
}

struct Payment {
    uint128 amount;
    uint120 timeStamp;
}

struct Dispute {
    uint128 proposedAmount;
    address arbitratorProposer;
    bool    arbitratorProposed;
    bool    arbitratorAccepted;
    Arbitrator[] proposedArbitrators;
}





