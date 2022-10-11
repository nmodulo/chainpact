pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
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
    uint32 yesVotes;
    uint32 noVotes;
    uint64 maturityTimeStamp;
    uint64 votingEndTimeStamp;
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
    mapping(bytes32 => mapping(address => bool)) canVote;
    mapping(bytes32 => mapping(address => bool)) hasVoted;
    mapping(bytes32 => uint) minVotingContribution;
    mapping(bytes32 => bool) votingActive;
    event logContribution(bytes32 uid, address payer, uint256 amount);
    event logPactCreated(address creator, bytes32 uid);
    event logVotingStarted(bytes32 uid);
    event logVotingEnded(bytes32 uid);

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
        bool[] calldata participantCanWithdrawArray_,
        Participant[] calldata participants_
    )
        external
        payable
        returns (
            // BeneficiaryType[] calldata beneficiaryTypes_
            bytes32 uid
        )
    {
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

        addParticipants(uid, participants_, participantCanWithdrawArray_);

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

    function addParticipants(
        bytes32 pactid,
        Participant[] calldata participants_,
        bool[] calldata participantCanWithdrawArray_
    ) public {
        require(participants_.length == participantCanWithdrawArray_.length);
        require(msg.sender == pacts[pactid].creator && !votingActive[pactid]);
        for (uint256 i = 0; i < participants_.length; i++) {
            pacts[pactid].participants.push(participants_[i]);
            canWithdraw[pactid][
                participants_[i].addr
            ] = participantCanWithdrawArray_[i];
            canVote[pactid][participants_[i].addr] = participants_[i].canVote;
        }
    }

    function pitchIn(bytes32 pactid) external payable {
        emit logContribution(pactid, msg.sender, msg.value);
        pacts[pactid].totalValue += msg.value;
        contributions[pactid][msg.sender] += msg.value;
    }

    function withdraw(bytes32 pactid, uint256 amount) external {
        require(
            block.timestamp > pacts[pactid].maturityTimeStamp,
            "Time locked"
        );
        require(canWithdraw[pactid][msg.sender], "Unauthorized");
        uint256 amountToSend = pacts[pactid].totalValue;
        if (amount > 0 && amount <= amountToSend) {
            amountToSend = amount;
        }
        pacts[pactid].totalValue -= amountToSend;
        payable(msg.sender).transfer(amountToSend);
    }

    function startVotingWindow(bytes32 pactid, uint64 endTimeSeconds) external {
        require(!votingActive[pactid], "Already active");
        require(pacts[pactid].creator == msg.sender, "Unauthorized");
        require(pacts[pactid].participants.length > 0, "No Voters");
        require(endTimeSeconds < 180 days, "Voting period too long");
        pacts[pactid].votingEndTimeStamp = uint64(
            block.timestamp + endTimeSeconds
        );
        votingActive[pactid] = true;
    }

    function voteOnPact(bytes32 pactid, bool vote) external {
        // console.log("Voting active canVote contribution");
        // console.log(votingActive[pactid]);
        // console.log(canVote[pactid][msg.sender]);
        // console.log(contributions[pactid][msg.sender]);
        require(
            votingActive[pactid] 
            && canVote[pactid][msg.sender] 
            && contributions[pactid][msg.sender] >= minVotingContribution[pactid],
            "Not allowed"
        );
        require(block.timestamp < pacts[pactid].votingEndTimeStamp , "Voting Ended");
        canVote[pactid][msg.sender] = false;
        hasVoted[pactid][msg.sender] = true;

        if (vote) pacts[pactid].yesVotes += 1;
        else pacts[pactid].noVotes += 1;
    }

    function endVoting(bytes32 pactid) public {
        require( hasVoted[pactid][msg.sender] || msg.sender == pacts[pactid].creator, "acc has not voted");
        votingActive[pactid] = false;
        if(pacts[pactid].totalValue == 0) return;
        uint yesVotes = pacts[pactid].yesVotes;
        uint noVotes = pacts[pactid].noVotes;

        // Participant[] memory participants_ = pacts[pactid].participants;


        uint numParticipants = pacts[pactid].participants.length;
        address[] memory yesBeneficiaries = new address[](numParticipants);
        address[] memory noBeneficiaries = new address[](numParticipants);
        uint yesBeneficiariesCount = 0;
        uint noBeneficiariesCount = 0;

        for (uint i = 0; i < numParticipants; i++) {
            Participant memory participant = pacts[pactid].participants[i];
            BeneficiaryType benType = participant.beneficiaryType;

            if (benType == BeneficiaryType.YES) {
                yesBeneficiaries[yesBeneficiariesCount++] = participant.addr;
            } else if (benType == BeneficiaryType.NO) {
                noBeneficiaries[noBeneficiariesCount++] = participant.addr;
            }
        }

        if (yesVotes > noVotes) {
            uint divisions = yesBeneficiariesCount;
            if (divisions != 0) {
                uint amountToSend = pacts[pactid].totalValue / divisions;
                for (uint i = 0; i < divisions; i++) {
                    pacts[pactid].totalValue -= amountToSend;
                    payable(yesBeneficiaries[i]).transfer(amountToSend);
                }
            }
        } else {
            uint divisions = noBeneficiariesCount;
            if (divisions != 0) {
                uint amountToSend = pacts[pactid].totalValue / divisions;
                for (uint i = 0; i < divisions; i++) {
                    pacts[pactid].totalValue -= amountToSend;
                    payable(noBeneficiaries[i]).transfer(amountToSend);
                }
            }
        }
        uint totalValueAfter = pacts[pactid].totalValue;
        //Send the remaining amount to the creator
        if (totalValueAfter > 0) {
            pacts[pactid].totalValue = 0;
            payable(pacts[pactid].creator).transfer(pacts[pactid].totalValue);
        }
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
