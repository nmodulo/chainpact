//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;


contract SimpleEmployment {

    //data
    address public employee;
    address public employer;
    uint256 public paySchedule;

    uint256 public payAmount;
    uint256 public stakeAmount;
    mapping (address => bool) isApprover;
    mapping (address => bool) hasSigned;
    bool public active;
    bool public started;
    bool public stopped;
    bool public disputed;
    uint lastPayDay;
    address[] public arbitrators;
    mapping(address => bool) hasResolved;


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
        address employee_, 
        address employer_,
        uint256 paySchedule_,
        uint256 payAmount_) {
            employee = employee_;
            employer = employer_;
            paySchedule = paySchedule_;
            payAmount = payAmount_;
            isApprover[employer] = true;
            lastPayDay = block.timestamp;
    }

    function contractDataHash() public view returns (bytes32){
        return keccak256(abi.encodePacked(employee, employer, paySchedule, payAmount));
    }

    function employerSign(uint8 _v, bytes32 _r, bytes32 _s) external payable returns(bool){
        require(msg.value > 0, "Can't have zero stake");
        require(getMessageSigner(contractDataHash(), _v, _r, _s) == employer, "Employer Sign Invalid");
        stakeAmount = msg.value;
        return true;
    }

    // Function to retract the stake before the employee signs
    function retractOffer() external returns (bool){
        require(hasSigned[employee] != true, "Contract already signed");
        require(stakeAmount > 0 && active, "Nothing to Do here");
        active = false;
        stakeAmount = 0;
        payable(employer).transfer(stakeAmount);
        return true;
    }

    function employeeSign(uint8 _v, bytes32 _r, bytes32 _s) external returns (bool){
        require(getMessageSigner(contractDataHash(), _v, _r, _s) == employee, "Employee Sign Invalid");
        hasSigned[employee] = true;
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
        require(block.timestamp >= lastPayDay + paySchedule - 5 days, "Too soon per pay schedule");         //Allowing payment up to 5 days earlier
        lastPayDay = block.timestamp;
        payable(employee).transfer(msg.value);
    }

    function resign() external isActive isStarted{
        require(msg.sender == employee, "Only Employee");
        active = false;
    }

    function approveResign() external isStarted{
        require(!active, "Active Contract");
        stopped = true;
    }

    function FnF() external payable{
        require(started && stopped && !active, "Check Resignation status");
        payable(employee).transfer(msg.value);
    }

    function raiseDispute(address[] memory arbitrators_) public{
        require(msg.sender == employee || isApprover[msg.sender], "Employee or Approvers only");
        disputed = true;
        for(uint8 i = 0; i < arbitrators_.length; i++){
            arbitrators.push(arbitrators_[i]);
        }
    }

    function resolveDispute() public{
        require(disputed, "No disputes to resolve");
        hasResolved[msg.sender] = true;
        if(hasResolved[employee] && isApprover[msg.sender]){
            bool allArbitratorsResolved = true;
            for(uint8 i = 0; i < arbitrators.length; i++){
                allArbitratorsResolved = hasResolved[arbitrators[i]] && allArbitratorsResolved;
            }
            require(allArbitratorsResolved, "All arbitrators haven't resolved");
        }
        disputed = false;
    }

    function reclaimStake(address payable payee) external onlyApprovers{
        require(!disputed, "Disputed");
        require(!active && stopped || !started, "Improper State");
        require(stakeAmount <= address(this).balance, "Low Balance");
        payee.transfer(stakeAmount);
    }

    function destroy() external onlyApprovers{
        require(msg.sender == employer, "Creator only");
        require(!active && stopped || !started && !disputed, "Can't Destroy");
        selfdestruct(payable(employer));
    }

    function getMessageSigner(bytes32 _hashedMessage, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address){
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _hashedMessage));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer;
    }
}