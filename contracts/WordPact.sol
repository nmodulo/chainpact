pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

// import "hardhat/console.sol";
import "./Structs.sol";

// import "@openzeppelin/contracts/access/Ownable.sol";
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

enum BeneficiaryType {
    NONE,
    YES,
    NO
}

struct Participant {
    address addr;
    bool canVote;
    BeneficiaryType beneficiaryType;
}

struct PactData {
    bool isEditable;
    bool votingEnabled;    
    uint64 maturityTimeStamp;
    address creator;
    uint256 totalValue;
    Participant[] participants;
    string pactText;
}

contract WordPact {
    //Data
    mapping(bytes32 => PactData) public pacts;
    uint64 public pactsCounter;

    mapping(bytes32 => mapping(address => uint256)) public contributions;
    mapping(bytes32 => mapping(address => bool)) canWithdraw;
    event logContribution(bytes32 uid, address payer, uint256 amount);
    event logPactCreated(address creator, bytes32 uid);

    //Logic

    function calcUid() public view returns (bytes32 uid) {
        return (
            keccak256(
                abi.encodePacked(msg.sender, block.timestamp, pactsCounter)
            )
        );
    }

    function createPact(
        bool isEditable_,
        string calldata pactText_,
        uint256 secondsToMaturity_,
        bool votingEnabled_,
        address[] calldata particpantAddresses_,
        bool[] calldata participantsCanVoteArray_,
        BeneficiaryType[] calldata beneficiaryTypes_
    ) external payable returns (bytes32 uid) {
        uint256 participantCount = particpantAddresses_.length;
        require(
            participantsCanVoteArray_.length == participantCount &&
                beneficiaryTypes_.length == participantCount
        );

        uid = calcUid();
        pacts[uid].isEditable = isEditable_;


        pacts[uid].pactText = pactText_;
        pacts[uid].votingEnabled = votingEnabled_;
        pacts[uid].totalValue = msg.value;
        if (secondsToMaturity_ > 0) {
            pacts[uid].maturityTimeStamp = uint64(
                secondsToMaturity_ + block.timestamp
            );
        }
        pacts[uid].creator = msg.sender;
        canWithdraw[uid][msg.sender] = true;

        for (uint256 i = 0; i < participantCount; i++) {
            pacts[uid].participants.push(
                Participant(
                    particpantAddresses_[i],
                    participantsCanVoteArray_[i],
                    beneficiaryTypes_[i]
                )
            );
        }

        pactsCounter++;
        emit logPactCreated(msg.sender, uid);
        if (msg.value > 0) {
            contributions[uid][msg.sender] += msg.value;
            emit logContribution(uid, msg.sender, msg.value);
        }
        return uid;
    }

    receive() external payable {
        emit logContribution(0, msg.sender, msg.value);
    }

    function pitchIn(bytes32 pactid) external payable {
        contributions[pactid][msg.sender] += msg.value;
        emit logContribution(pactid, msg.sender, msg.value);
    }

    function withdraw(bytes32 pactid, uint amount) external {
        require(block.timestamp > pacts[pactid].maturityTimeStamp, "Time locked");
        require(canWithdraw[pactid][msg.sender]);
        uint amountToSend = pacts[pactid].totalValue;
        if(amount > 0 && amount <= amountToSend){
            amountToSend = amount;
        }
        pacts[pactid].totalValue -= amountToSend;
        payable(msg.sender).transfer(amountToSend);
    } 
    //Getters
    function getPact(bytes32 pactid)
        external
        view
        returns (PactData memory pactData)
    {
        return pacts[pactid];
    }

    function setText(bytes32 pactid, string memory pactText_) public {
        require(pacts[pactid].isEditable);
        pacts[pactid].pactText = pactText_;
    }
}
