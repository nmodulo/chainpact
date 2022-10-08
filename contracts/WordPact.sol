pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

// import "hardhat/console.sol";
import "./Structs.sol";

// import "@openzeppelin/contracts/access/Ownable.sol";
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

enum BeneficiaryType{
    NONE,
    YES,
    NO
}

struct Participant{
    address addr;
    bool canVote;
    BeneficiaryType beneficiaryType;
}

struct PactData {
    bool isEditable;
    uint64 maturityTimeStamp;
    string pactText;
    uint totalValue;
    bool votingEnabled;
    Participant[] participants;
}

contract WordPact {
    //Data
    mapping(bytes32 => PactData) public pacts;
    uint64 public pactsCounter;

    mapping(bytes32 => mapping(address => uint256)) public contributions;
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
        uint256 maturityTimeStamp_,
        bool votingEnabled_,
        address[] calldata particpantAddresses_,
        bool[] calldata participantsCanVoteArray_,
        BeneficiaryType[] calldata beneficiaryTypes_
    ) external payable returns (bytes32 uid) {
        uint participantCount = particpantAddresses_.length;
        require(
          participantsCanVoteArray_.length == participantCount &&
          beneficiaryTypes_.length == participantCount
        );

        uid = calcUid();
        pacts[uid].isEditable = isEditable_;
        pacts[uid].pactText = pactText_;
        pacts[uid].totalValue = msg.value;
        pacts[uid].maturityTimeStamp = uint64(maturityTimeStamp_);
        pacts[uid].votingEnabled = votingEnabled_;
        
        for(uint i=0; i< participantCount; i++){
          pacts[uid].participants.push(
            Participant(
            particpantAddresses_[i],
            participantsCanVoteArray_[i],
            beneficiaryTypes_[i]
          ));
        }

        pactsCounter++;
        emit logPactCreated(msg.sender, uid);
        return uid;
    }

    receive() external payable {
        emit logContribution(0, msg.sender, msg.value);
    }

    function pitchIn(bytes32 pactid) external payable {
        contributions[pactid][msg.sender] += msg.value;
        emit logContribution(pactid, msg.sender, msg.value);
    }

    //Getters
    function getPact(bytes32 pactid)
        external
        view
        returns (PactData memory pactData)
    {
        return pacts[pactid];
    }

    //Setters

    function badSetEditable(bytes32 pactid, bool isEditable_) public {
        pacts[pactid].isEditable = isEditable_;
    }

    function setText(bytes32 pactid, string memory pactText_) public {
        require(pacts[pactid].isEditable);
        pacts[pactid].pactText = pactText_;
    }
}
