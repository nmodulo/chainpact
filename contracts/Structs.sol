//SPDX-License-Identifier: MIT
pragma solidity > 0.8.0  <= 0.9.0;

struct CoreData{
    bytes32 pactName;
    address employee;
    address employer;
    uint128 payScheduleDays;
    uint128 payAmount;
}

struct Arbitrator{
    address addr;
    bool    hasResolved;
}

struct Payment{
    uint128 amount;
    uint128 timeStamp;
}

struct Dispute{
    uint128 proposedAmount;
    address arbitratorProposer;
    bool arbitratorProposed;
    bool arbitratorAccepted;
    Arbitrator[] proposedArbitrators;
}