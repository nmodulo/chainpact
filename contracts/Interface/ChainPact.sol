//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ChainPact{
    event LogPactCreated(address indexed creator, bytes32 pactid);
    function isParty(bytes32 pactid, address party) external view returns (bool);
}