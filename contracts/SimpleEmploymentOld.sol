//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
pragma solidity > 0.8.0  <= 0.9.0;

import "./ECDSA.sol";

contract SimpleEmploymentOld {

    struct Arbitrator{
        address addr;
        bool    hasResolved;
    }
    //Core Data
    bytes32 public pactName;
    address public employee;
    address public employer;
    uint256 public paySchedule;
    uint256 public employeeSignDate;
    uint256 public payAmount;
    uint lastPaymentMade;

    mapping (address => uint256) public stakeAmount;

    //Constraint flags
    mapping (address => bool) isApprover;
    mapping (address => bool) signedFlag;
    bool public active;
    bool public started;
    bool public stopped;
    bool public disputed;
    Arbitrator[] public arbitrators;

    mapping(address => bool) public isArbitrator;


    //modifiers
    modifier onlyApprovers{
        require(isApprover[msg.sender], "Approver only");
        _;
    }

    modifier isActive{
        require(active, "Not Active");
        _;
    }

    modifier isStarted{
        require(started, "Not started");
        _;
    }

    //Events

    // Functions
    constructor (
        bytes32 pactName_,
        address employee_, 
        address employer_,
        uint256 paySchedule_,
        uint256 payAmount_) {
            pactName = pactName_;
            employee = employee_;
            employer = employer_;
            paySchedule = paySchedule_;
            payAmount = payAmount_;
            isApprover[employer] = true;
            lastPaymentMade = block.timestamp;
    }


    //Parameter Setters

    //Add arbitrators
    function addArbitrators(address[] memory arbitratorAddresses) public{
        require(!active && !started, "Already started and active");
        for(uint8 i = 0; i < arbitrators.length; i++){
            Arbitrator memory arbitrator;
            arbitrator.addr = arbitratorAddresses[i];
            arbitrators.push(arbitrator);
            isArbitrator[arbitratorAddresses[i]] = true;
        }
    }

    function contractDataHash(uint256 signingDate_) public view returns (bytes32){
        return keccak256(abi.encodePacked(
            employee, 
            employer, 
            paySchedule,
            payAmount,
            signingDate_,
            address(this)));
    }

//working
    function recoverContractSigner(bytes memory signature, uint256 signingDate_) public view returns (address){
        return ECDSA.recover(
            ECDSA.toEthSignedMessageHash(contractDataHash(signingDate_)), 
            signature);
    }

//working
    function employerSign(bytes memory signature, uint256 signingDate_) public payable returns(bool){
        require(msg.value > 0, "Can't have zero stake");
        require(recoverContractSigner(signature, signingDate_) == employer, "Employer Sign Invalid");
        stakeAmount[address(this)] = msg.value;
        return true;
    }

    // Function to retract the stake before the employee signs
    function retractOffer() external returns (bool){
        require(signedFlag[employee] != true, "Contract already signed");
        require(stakeAmount[address(this)] > 0 && active, "Nothing to Do here");
        active = false;
        stakeAmount[address(this)] = 0;
        payable(employer).transfer(stakeAmount[address(this)]);
        return true;
    }

//working
    function employeeSign(bytes memory signature, uint256 signingDate_) external returns (bool){
        require(recoverContractSigner(signature, signingDate_) == employee, "Employee Sign Invalid");
        signedFlag[employee] = true;
        employeeSignDate = signingDate_;
        active = true;
        return true;
    }

    function addApprovers(address[] memory newApprovers) external onlyApprovers{
        require(newApprovers.length <= 5, "No more than 5 approvers");
        for(uint8 i = 0; i < newApprovers.length; i++){
            isApprover[newApprovers[i]] = true;
        }
    }

    function start() external isActive onlyApprovers{
        started = true;
    }

    function approvePayment() external payable isActive isStarted onlyApprovers{
        require(msg.value >= payAmount, "Amount less than contract");
        require(block.timestamp + 5 days >= (lastPaymentMade + paySchedule * 1 days), "Too soon per pay schedule");         //Allowing payment up to 5 days earlier
        lastPaymentMade = block.timestamp;
        payable(employee).transfer(msg.value);
    }

    function resign() external isActive isStarted{
        require(msg.sender == employee, "Only Employee");
        active = false;
        //Reset the signature flags
        signedFlag[employee] = false;
        signedFlag[employer] = false;
    }

    function approveResign() external isStarted{
        require(!active, "Active Contract");
        stopped = true;
    }

    function terminate() external onlyApprovers isActive{
        stopped = true;
    }

    /*
    Full and Final Settlement FnF can be initiated by both parties in case they owe something.
    */
    function FnF() external payable{
        require(!active || stopped, "Contract still in operation");
        if(isApprover[msg.sender] && msg.value > 0){
            payable(employee).transfer(msg.value);
            signedFlag[employer] = true;
        }
        else if(msg.sender == employee){
            signedFlag[employee] = true;
            if(msg.value > 0){
                payable(employer).transfer(msg.value);
            }
            active = false;
        }
        else{
            revert("INVALID");
        }
    }

//working
/** Sets the contract in the "Disputed" Mode. 
Advisable to send in your own address in case no external arbitration needed */
    function raiseDispute(address[] memory arbitrators_) public{
        require(msg.sender == employee || isApprover[msg.sender], "Employee or Approvers only");
        disputed = true;
        for(uint8 i = 0; i < arbitrators_.length; i++){
            Arbitrator memory newArbitrator;
            newArbitrator.addr = arbitrators_[i];
            arbitrators.push(newArbitrator);
            isArbitrator[arbitrators_[i]] = true;
        }
    }

    function resolveDispute() public{
        require(disputed, "No disputes to resolve");
        require(isArbitrator[msg.sender], "Arbitrators only");
        
        bool allArbitratorsResolved = true;
        for(uint8 i = 0; i < arbitrators.length; i++){
            Arbitrator storage arbitrator_ = arbitrators[i];
            if(arbitrator_.addr == msg.sender){
                arbitrator_.hasResolved = true;                    
                if(!allArbitratorsResolved) return;
            }
            allArbitratorsResolved = arbitrator_.hasResolved && allArbitratorsResolved;
        }
        if(allArbitratorsResolved) disputed = false;
    }

/**
Method to be used to get the remaining stake by the employer when the contract has been ended. */
    function reclaimStake(address payable payee) external onlyApprovers{
        require(!disputed, "Disputed");
        require(!active && stopped || !started, "Contract not dissolved");
        require(stakeAmount[address(this)] <= address(this).balance, "Low Balance");
        payee.transfer(stakeAmount[address(this)]);
    }

/** Allows for destryoing the contract in case something has gone wrong */
    function destroy() external onlyApprovers{
        require(msg.sender == employer, "Creator only");
        require(!active && stopped || !started && !disputed, "Can't Destroy");
        selfdestruct(payable(employer));
    }
}