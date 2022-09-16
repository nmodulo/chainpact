//SPDX-License-Identifier: MIT

// import "hardhat/console.sol";
pragma solidity > 0.8.4  <= 0.8.17;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./Structs.sol";
import "./Enums.sol";

contract SimpleEmployment {

    event LogPaymentMade(uint value, address payer);
    event LogPaymentWithdrawn(uint value, address payee);
    event LogStateUpdate(PactState newState, address updater);

    //Core Data
    CoreData public pactData;
    uint256 public employeeSignDate;

    //BAU
    PactState public pactState;
    uint public stakeAmount;
    uint public availableToWithdraw;
    Payment public lastPaymentMade;
    Dispute public disputeData;
    uint public pauseDuration;
    uint public pauseResumeTime;

    //Constraint flags
    mapping (address => bool) public isEmployeeDelegate;
    mapping (address => bool) public isEmployerDelegate;

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

    modifier isEOA{
        require(msg.sender == tx.origin);
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
        lastPaymentMade = Payment({amount: uint128(0), timeStamp: uint120(block.timestamp)});
        emit LogStateUpdate(PactState.ACTIVE, msg.sender);
    }

    function pause() external onlyParties isActive{
        pactState = PactState.PAUSED;
        pauseResumeTime = block.timestamp;
        emit LogStateUpdate(PactState.PAUSED, msg.sender);
    }

    function resume() external onlyParties{
        require(pactState == PactState.PAUSED);
        pactState = PactState.ACTIVE;
        pauseDuration += block.timestamp - pauseResumeTime;
        pauseResumeTime = block.timestamp;
        emit LogStateUpdate(PactState.ACTIVE, msg.sender);
    }

    function approvePayment() external payable onlyEmployer isActive{
        require(msg.value >= pactData.payAmount, "Amount less than payAmount");
        lastPaymentMade = Payment({timeStamp: uint120(block.timestamp), amount: uint128(msg.value)});
        availableToWithdraw += msg.value;
        pauseDuration = 0;
        emit LogPaymentMade(msg.value, msg.sender);
    }

    function withdrawPayment(uint value) external onlyEmployee isActive{
        require(availableToWithdraw >= value && availableToWithdraw > 0, "Payment not available");
        uint withdrawAmt = value;
        if(withdrawAmt == 0){
            withdrawAmt = availableToWithdraw;
        }
        availableToWithdraw -= withdrawAmt;
        emit LogPaymentWithdrawn(withdrawAmt, msg.sender);
        payable(pactData.employee).transfer(withdrawAmt);
    }

    function resign() external onlyEmployee isActive{
        pactState = PactState.RESIGNED;
        emit LogStateUpdate(PactState.RESIGNED, msg.sender);
    }

    function approveResign() external onlyEmployer{
        require(pactState == PactState.RESIGNED, "Not Resigned");
        pactState = PactState.END_ACCEPTED;
        emit LogStateUpdate(PactState.END_ACCEPTED, msg.sender);
    }

    function terminate() external onlyEmployer isEOA isActive{
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
        emit LogStateUpdate(PactState.TERMINATED, msg.sender);
        payable(msg.sender).transfer(refundAmount_);
    }

    /* Full and Final Settlement FnF can be initiated by both parties in case they owe something.*/
    function fNf() external payable{
        PactState oldPactState_ = pactState;
        PactState pactState_ = oldPactState_;
        address receiver = address(0);

        require(pactState_ >= PactState.TERMINATED && pactState_ <= PactState.ENDED, "Check State");
        
        if(isEmployeeDelegate[msg.sender]){
            if(pactState_ == PactState.TERMINATED || pactState_ == PactState.END_ACCEPTED){
                pactState_ = PactState.FNF_EMPLOYEE;
            }
            else if(pactState_ == PactState.DISPUTED || pactState_ == PactState.ARBITRATED){
                pactState_ = PactState.DISPUTE_RESOLVED;
            }
            else if(pactState_ == PactState.FNF_EMPLOYER){
                pactState_ = PactState.FNF_SETTLED;
            }
            if(msg.value > 0){
                receiver = pactData.employer;
            }
        }

        else if(isEmployerDelegate[msg.sender]){
            if(pactState_ == PactState.TERMINATED || pactState_ == PactState.END_ACCEPTED){
                pactState_ = PactState.FNF_EMPLOYER;
            }
            else if(pactState == PactState.FNF_EMPLOYEE){
                pactState_ = PactState.FNF_SETTLED;
            }
            if(msg.value > 0){
                if(pactState == PactState.DISPUTED && msg.value >= disputeData.proposedAmount){
                    pactState_ = PactState.FNF_SETTLED;
                }
                receiver = pactData.employee;
            } 
        }

        else{
            revert("Unauthorized");
        }
        if(oldPactState_ != pactState_){
            pactState = pactState_;
            emit LogStateUpdate(pactState_, msg.sender);
        }
        if(receiver != address(0)){
            emit LogPaymentMade(msg.value, msg.sender);
            payable(receiver).transfer(msg.value);
        }
    }

    function dispute(uint suggestedAmountClaim) external onlyEmployee{
        require(pactState == PactState.FNF_EMPLOYER);
        pactState = PactState.DISPUTED;
        disputeData.proposedAmount = uint128(suggestedAmountClaim);
        emit LogStateUpdate(PactState.DISPUTED, msg.sender);
    }

    function proposeArbitrators(address[] calldata proposedArbitrators_) external onlyParties{
        require(!(disputeData.arbitratorAccepted), "Already Accepted");
        require(proposedArbitrators_.length > 0);
        require(pactState == PactState.DISPUTED, "Not Disputed");
        disputeData.arbitratorProposer = msg.sender;
        disputeData.arbitratorProposed = true;
        delete disputeData.proposedArbitrators;
        for(uint i=0; i<proposedArbitrators_.length; i++){
            disputeData.proposedArbitrators.push(Arbitrator({addr: proposedArbitrators_[i], hasResolved: false}));
        }
    }

    function acceptOrRejectArbitrators(bool acceptOrReject) external onlyParties{
        require(pactState == PactState.DISPUTED && disputeData.arbitratorProposed);

        if(isEmployeeDelegate[disputeData.arbitratorProposer]){
            require(isEmployerDelegate[msg.sender]);
        } else {
            require(isEmployeeDelegate[msg.sender]);
        }
        disputeData.arbitratorAccepted = acceptOrReject;
        if(!acceptOrReject){
            disputeData.arbitratorProposed = false;
            delete disputeData.proposedArbitrators;
        } 
        else {
            pactState = PactState.ARBITRATED;
            emit LogStateUpdate(PactState.ARBITRATED, msg.sender);
        }
    }

    function getArbitratorsList() external view returns(Arbitrator[] memory arbitrators){
        return disputeData.proposedArbitrators;
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
            emit LogStateUpdate(PactState.DISPUTE_RESOLVED, msg.sender);
        }
    }

    /** To get the remaining stake by the employer when the contract has been ended. */
    function reclaimStake(address payable payee) external onlyEmployer isEOA{
        require(pactState >= PactState.FNF_SETTLED);
        uint stakeAmount_ = stakeAmount;
        require(stakeAmount_ <= address(this).balance, "Low Balance");
        require(payee != address(0));
        pactState = PactState.ENDED;
        emit LogPaymentMade(stakeAmount_, address(this));
        emit LogStateUpdate(PactState.ENDED, msg.sender);
        stakeAmount = 0;
        payee.transfer(stakeAmount_);
    }

    function autoWithdraw() external onlyEmployee{
        require(pactState >= PactState.ACTIVE);
        require(block.timestamp - lastPaymentMade.timeStamp > 2*pactData.payScheduleDays*86400000, "Wait");
        uint stakeAmount_ = stakeAmount;
        stakeAmount = 0;
        lastPaymentMade = Payment({amount: uint128(stakeAmount_), timeStamp: uint120(block.timestamp)});
        pactState = PactState.PAUSED;
        emit LogStateUpdate(PactState.PAUSED, msg.sender);
        emit LogPaymentMade(stakeAmount_, address(this));
        payable(pactData.employee).transfer(stakeAmount_);
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
    function destroy() external{
        require(msg.sender == pactData.employer);
        require(pactState == PactState.ENDED || pactState == PactState.DEPLOYED);
        selfdestruct(payable(msg.sender));
    }
}