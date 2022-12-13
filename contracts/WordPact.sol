pragma solidity 0.8.16;
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
    bool refundOnVotedNo;
    uint32 yesVotes;
    uint32 noVotes;
    uint64 maturityTimestamp;
    uint64 votingEndTimestamp;
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
    mapping(bytes32 => mapping(address => bool)) public canWithdraw;
    mapping(bytes32 => bool) public canWithdrawContribution;
    mapping(bytes32 => mapping(address => bool)) public canVote;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    mapping(bytes32 => uint) public minVotingContribution;
    mapping(bytes32 => bool) public votingActive;
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
        uint256 maturityTimestamp_,
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
        if (maturityTimestamp_ > 0) {
            if(maturityTimestamp_ < block.timestamp + 900 days) //Don't allow too big maturity times
                pacts[uid].maturityTimestamp  = uint64(
                maturityTimestamp_
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
            block.timestamp > pacts[pactid].maturityTimestamp,
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

    function withdrawContribution(bytes32 pactid) external {
        if(canWithdrawContribution[pactid]){
            uint contri = contributions[pactid][msg.sender];
            contributions[pactid][msg.sender] = 0;
            payable(msg.sender).transfer(contri);
        }
    }

    function startVotingWindow(bytes32 pactid, uint64 endTimeSeconds) external {
        require(!votingActive[pactid], "Already active");
        require(pacts[pactid].creator == msg.sender, "Unauthorized");
        require(pacts[pactid].participants.length > 0, "No Voters");
        require(endTimeSeconds < 180 days, "Voting period too long");
        pacts[pactid].votingEndTimestamp = uint64(
            block.timestamp + endTimeSeconds
        );
        votingActive[pactid] = true;
    }

    function voteOnPact(bytes32 pactid, bool vote) external {
        require(
            votingActive[pactid] 
            && canVote[pactid][msg.sender] 
            && contributions[pactid][msg.sender] >= minVotingContribution[pactid],
            "Not allowed"
        );
        require(block.timestamp < pacts[pactid].votingEndTimestamp , "Voting Ended");
        canVote[pactid][msg.sender] = false;
        hasVoted[pactid][msg.sender] = true;

        if (vote) pacts[pactid].yesVotes += 1;
        else pacts[pactid].noVotes += 1;
    }

    function setRefundOnVotedNo(bytes32 pactid, bool ifRefundOnVotedNo) external{
        require(msg.sender == pacts[pactid].creator, "Unauthorized");
        pacts[pactid].refundOnVotedNo = ifRefundOnVotedNo;
    }

    function endVoting(bytes32 pactid) public {
        require( hasVoted[pactid][msg.sender] || msg.sender == pacts[pactid].creator, "acc has not voted");
        votingActive[pactid] = false;
        if(pacts[pactid].totalValue == 0) return;
        uint yesVotes = pacts[pactid].yesVotes;
        uint noVotes = pacts[pactid].noVotes;

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
        } else if(pacts[pactid].refundOnVotedNo){
            console.log("Refundonvotedno");
            canWithdrawContribution[pactid] = true;
            return;
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
