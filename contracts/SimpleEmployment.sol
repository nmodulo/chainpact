//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
pragma solidity > 0.8.0  <= 0.9.0;

import "./ECDSA.sol";
import "./Structs.sol";
import "./Enums.sol";

contract SimpleEmployment {

    //Core Data
    CoreData public pactData;
    uint256 employeeSignDate;

    //BAU
    PactState public pactState;
    uint public stakeAmount;
    Payment lastPaymentMade;
    Dispute disputeData;
    uint pauseDuration;
    uint pauseResumeTime;

    //Constraint flags
    mapping (address => bool) isEmployeeDelegate;
    mapping (address => bool) isEmployerDelegate;

    //modifiers
    modifier onlyEmployer{
        require(isEmployerDelegate[msg.sender], "employer delegate only");
        _;
    }

    modifier onlyEmployee{
        require(isEmployeeDelegate[msg.sender], "employee delegate only");
        _;
    }

    modifier onlyParties{
        require(isEmployeeDelegate[msg.sender] || isEmployerDelegate[msg.sender], "only parties");
        _;
    }

    modifier isActive{
        require(pactState == PactState.ACTIVE, "not active");
        _;
    }

    // Functions
    constructor (
        bytes32 pactName_,
        address employee_, 
        address employer_,
        uint128 payScheduleDays_,
        uint128 payAmount_) {
        require (payAmount_ > 0 && pactName_ != 0);
        pactData = CoreData({
            pactName : pactName_,
            employee : employee_,
            employer : employer_,
            payScheduleDays : payScheduleDays_,
            payAmount : payAmount_
        });
        isEmployeeDelegate[employee_] = true;
        isEmployerDelegate[employer_] = true;
    }

    //Function to send the employer digital signature and stake amount
    function employerSign(bytes calldata signature, uint256 signingDate_) external payable returns(bool){
        PactState pactState_ = pactState;
        CoreData memory pactData_= pactData;
        
        require(pactState_ < PactState.ALL_SIGNED, "Already signed");
        require(msg.value >= pactData_.payAmount, "Can't have zero stake");
        require(recoverContractSigner(signature, signingDate_) == pactData_.employer, "Employer Sign Invalid");

        stakeAmount = msg.value;
        if(pactState_ == PactState.EMPLOYEE_SIGNED) {
            pactState = PactState.ALL_SIGNED;
        } else {
            pactState = PactState.EMPLOYER_SIGNED;
        }
        return true;
    }

    // Function to retract the stake before the employee signs
    function retractOffer() external onlyEmployer returns (bool){
        require(pactState < PactState.ALL_SIGNED, "Contract already signed");
        pactState = PactState.RETRACTED;
        stakeAmount = 0;
        payable(pactData.employer).transfer(stakeAmount);
        return true;
    }
    
    // Function to send digital signature as the employee
    function employeeSign(bytes calldata signature, uint256 signingDate_) external returns (bool){
        PactState pactState_ = pactState;
        CoreData memory pactData_ = pactData;
        require(pactState_ < PactState.ALL_SIGNED, "Already signed");
        require(recoverContractSigner(signature, signingDate_) == pactData_.employee, "Employee Sign Invalid");
        employeeSignDate = signingDate_;

        if(pactState_ == PactState.EMPLOYER_SIGNED) {
            pactState = PactState.ALL_SIGNED;
        } else {
            pactState = PactState.EMPLOYEE_SIGNED;
        }
        return true;
    }

    function delegate(address[] calldata delegates, bool addOrRevoke) external{
        require(pactState >= PactState.ALL_SIGNED);
        if(msg.sender == pactData.employer){
            for(uint i=0; i<delegates.length; i++){
                isEmployerDelegate[delegates[i]] = addOrRevoke;
            }
        }
        if(msg.sender == pactData.employee){
            for(uint i=0; i<delegates.length; i++){
                isEmployeeDelegate[delegates[i]] = addOrRevoke;
            }
        }
    }

    function start() external onlyEmployer{
        require(pactState == PactState.ALL_SIGNED);
        pactState = PactState.ACTIVE;
        lastPaymentMade.timeStamp = uint128(block.timestamp);
    }

    function pause() external onlyParties isActive{
        pactState = PactState.PAUSED;
        pauseResumeTime = block.timestamp;
    }

    function resume() external onlyParties{
        require(pactState == PactState.PAUSED);
        pactState = PactState.ACTIVE;
        pauseDuration = block.timestamp - pauseResumeTime;
        pauseResumeTime = block.timestamp;
    }

    function approvePayment() external payable onlyEmployer isActive{
        require(msg.value >= pactData.payAmount, "Amount less than payAmount");
        lastPaymentMade = Payment({timeStamp: uint128(block.timestamp), amount: uint128(msg.value)});
        pauseDuration = 0;
        payable(pactData.employee).transfer(msg.value);
    }

    function resign() external onlyEmployee isActive{
        pactState = PactState.RESIGNED;
    }

    function approveResign() external onlyEmployer{
        require(pactState == PactState.RESIGNED, "Not Resigned");
        pactState = PactState.END_ACCEPTED;
    }

    function terminate() external onlyEmployer isActive{
        pactState = PactState.TERMINATED;
        uint stakeAmount_ = stakeAmount;

        // Payment due assumed
        uint lockedAmt = (pactData.payAmount * (block.timestamp - lastPaymentMade.timeStamp - pauseDuration))
        / (pactData.payScheduleDays *86400*1000);
        if (lockedAmt >= stakeAmount_) return;

        uint refundAmount_= stakeAmount_ - lockedAmt;
        stakeAmount = lockedAmt;

        if(address(this).balance < refundAmount_){
            return;
        }
        payable(msg.sender).transfer(refundAmount_);
    }

    /* Full and Final Settlement FnF can be initiated by both parties in case they owe something.*/
    function FnF() external payable{
        PactState pactState_ = pactState;
        require(pactState_ >= PactState.TERMINATED && pactState_ <= PactState.ENDED, "Check State");
        
        if(isEmployeeDelegate[msg.sender]){
            if(msg.value > 0) payable(pactData.employer).transfer(msg.value);
            if(pactState_ == PactState.TERMINATED){
                pactState = PactState.FNF_EMPLOYEE;
            }
            if(pactState_ == PactState.DISPUTED || pactState_ == PactState.ARBITRATED){
                pactState = PactState.DISPUTE_RESOLVED;
            }
            if(pactState_ == PactState.FNF_EMPLOYER){
                pactState = PactState.FNF_SETTLED;
            }

        }

        else if(isEmployerDelegate[msg.sender]){
            if(pactState_ == PactState.TERMINATED || pactState_ == PactState.END_ACCEPTED){
                pactState = PactState.FNF_EMPLOYER;
            }
            if(pactState == PactState.FNF_EMPLOYEE){
                pactState = PactState.FNF_SETTLED;
            }
            if(msg.value > 0){
                if(pactState == PactState.DISPUTED && msg.value >= disputeData.proposedAmount){
                    pactState = PactState.FNF_SETTLED;
                }
                payable(pactData.employee).transfer(msg.value);
            } 

        }

        else{
            revert("Unauthorized");
        }
    }

    function dispute(uint suggestedAmountClaim) external onlyEmployee{
        require(pactState == PactState.FNF_EMPLOYER);
        pactState = PactState.DISPUTED;
        disputeData.proposedAmount = uint128(suggestedAmountClaim);
    }

    function proposeArbitrators(address[] calldata proposedArbitrators_) external onlyParties{
        require(!(disputeData.arbitratorAccepted), "Already Accepted");
        pactState = PactState.ARBITRATED;
        disputeData.arbitratorProposer = msg.sender;
        delete disputeData.proposedArbitrators;
        for(uint i=0; i<proposedArbitrators_.length; i++){
            disputeData.proposedArbitrators.push(Arbitrator({addr: proposedArbitrators_[i], hasResolved: false}));
        }
    }

    function acceptOrRejectArbitrators(bool acceptOrReject) external onlyParties{
        require(pactState == PactState.ARBITRATED, "Not arbitrated");

        if(isEmployeeDelegate[disputeData.arbitratorProposer]){
            require(isEmployerDelegate[msg.sender]);
        } else {
            require(isEmployeeDelegate[msg.sender]);
        }
        disputeData.arbitratorAccepted = acceptOrReject;
        if(!acceptOrReject) disputeData.arbitratorProposed = false;
    }

    function arbitratorResolve() public{
        require(pactState == PactState.ARBITRATED, "Not arbitrated");
        require(disputeData.arbitratorAccepted, "Arbitrator not accepted");
        bool allResolved = true;
        Arbitrator[] memory proposedArbitrators_ = disputeData.proposedArbitrators;
        for(uint i=0; i < proposedArbitrators_.length; i++){
            if(msg.sender == proposedArbitrators_[i].addr){
                disputeData.proposedArbitrators[i].hasResolved = true;
                proposedArbitrators_[i].hasResolved = true;
            }
            allResolved = allResolved && proposedArbitrators_[i].hasResolved;
        } 
        if(allResolved){
            pactState = PactState.DISPUTE_RESOLVED;
        }
    }

    /** To get the remaining stake by the employer when the contract has been ended. */
    function reclaimStake(address payable payee) external onlyEmployer{
        require(pactState >= PactState.FNF_SETTLED);
        require(stakeAmount <= address(this).balance, "Low Balance");
        pactState = PactState.ENDED;
        payee.transfer(stakeAmount);
    }

    function autoWithdraw() external onlyEmployee{
        require(pactState >= PactState.ACTIVE);
        require(block.timestamp - lastPaymentMade.timeStamp > 2*pactData.payScheduleDays*86400000, "Wait");
        uint stakeAmount_ = stakeAmount;
        stakeAmount = 0;
        payable(msg.sender).transfer(stakeAmount_);
        lastPaymentMade = Payment({amount: uint128(stakeAmount_), timeStamp: uint128(block.timestamp)});
        pactState = PactState.PAUSED;
    }

    function contractDataHash(uint256 signingDate_) public view returns (bytes32){
        return keccak256(abi.encodePacked(
            "ChainPact - I hereby sign the following ",
            pactData.employee, 
            pactData.employer, 
            pactData.payScheduleDays,
            pactData.payAmount,
            signingDate_,
            address(this)));
    }

    function recoverContractSigner(bytes memory signature, uint256 signingDate_) public view returns (address){
        return ECDSA.recover(
            ECDSA.toEthSignedMessageHash(contractDataHash(signingDate_)),
            signature);
    }

    /** Allows for destryoing the contract in case something has gone wrong */
    function destroy() external onlyEmployer{
        require(pactState == PactState.ENDED || pactState == PactState.DEPLOYED);
        selfdestruct(payable(msg.sender));
    }
}