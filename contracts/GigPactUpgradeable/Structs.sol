//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

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
    address erc20TokenAddress;
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