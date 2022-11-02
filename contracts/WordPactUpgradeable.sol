//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "hardhat/console.sol";
// import "./Structs.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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
    bool created; //Whether a pact for the pactId was created
    bool isEditable; //whether the pactText should be editable
    bool refundOnVotedNo; //On failed motion (Vote result No), should all contributions be refunded
    uint32 yesVotes; //Count of votes for the motion
    uint32 noVotes; //Count of votes against the motion
    uint64 timeLockEndTimestamp; //Timestamp in seconds after which the locked amount should be allowed to be withdrawn
    uint64 votingEndTimestamp; //Timestamp at which voting window ends
    address creator; //Address of the author of original post
    uint256 totalValue; //Total value held in this pact
    string pactText; //Textual summary of proposal
    Participant[] participants;
    bytes32 memberList;
}

// UUPSUpgradeable
contract WordPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    //Overrides for Upgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(uint _maxMaturityTime, uint _maxVotingPeriod) public {
        maxMaturityTime = _maxMaturityTime;
        maxVotingPeriod = _maxVotingPeriod;
    }

    //Data
    uint64 public pactsCounter; //Stores the number of pacts in this (storage) contract
    uint64 public listsCounter; //Store the number of membership lists in this (storage contract)
    uint public maxMaturityTime; //Maximum allowed time for maturity - for safety
    uint public maxVotingPeriod; //Maximum allowed voting window - for safety
    mapping(bytes32 => PactData) public pacts; //Storing data of all the pacts

    mapping(bytes32 => mapping(address => uint256)) public contributions; //Mapping of contribution to a given pact, by a given address (account)
    mapping(bytes32 => bool) public canWithdrawContribution; //Flag to for contributors to withdraw contribution on failed motion [Voted NO]
    mapping(bytes32 => mapping(address => bool)) public canVote; //Whether a given address is allowed to vote on the given pact
    mapping(bytes32 => mapping(address => bool)) public hasVoted; //Whether a given address has already voted on the given pact
    mapping(bytes32 => uint) public minVotingContribution; //Min amount of contribution each voter must have to be able to vote
    mapping(bytes32 => bool) public votingActive; //If voting is active on a given pact address
    event logContribution(bytes32 uid, address payer, uint256 amount);
    event logPactCreated(address creator, bytes32 uid);
    event logVotingStarted(bytes32 uid);
    event logVotingEnded(bytes32 uid);

    //membership list
    mapping(bytes32 => address[]) public membershipLists;
    mapping(bytes32 => mapping(address => bool)) public listAdmin;
    event logMembershipListCreated(address creator, bytes32 listName);

    //modifiers
    modifier isListAdmin(bytes32 listName) {
        require(listAdmin[listName][msg.sender], "Unauthorized");
        _;
    }

    modifier onlyPactCreator(bytes32 pactid) {
        require(pacts[pactid].creator == msg.sender);
        _;
    }

    //Generic
    receive() external payable {
        emit logContribution(0, msg.sender, msg.value);
    }

    //Logic
    function calcUid() public view returns (bytes32 uid) {
        return
            keccak256(
                abi.encodePacked(msg.sender, block.timestamp, pactsCounter)
            );
    }

    function createMembershipList(
        bytes32 listName_,
        address[] calldata members_
    ) external payable {
        require(membershipLists[listName_].length == 0 && members_.length > 0);
        if (uint(listName_) < 0xffffffffffffffffffffffff) {
            require(msg.value == uint(listName_) / 0xffffffffffffffffffffffff);
        }
        listAdmin[listName_][msg.sender] = true;
        for (uint i = 0; i < members_.length; i++) {
            if (members_[i] != address(0)) {
                membershipLists[listName_].push(members_[i]);
            }
        }
        emit logMembershipListCreated(msg.sender, listName_);
    }

    function addAdminForList(bytes32 listName_, address newAdmin_)
        external
        isListAdmin(listName_)
    {
        listAdmin[listName_][newAdmin_] = true;
    }

    /**Function to remove self or a member for a given list */
    function removeFromList(
        bytes32 listName_,
        uint indexToRemove,
        address memberToRemove_
    ) external {
        require(
            listAdmin[listName_][memberToRemove_] ||
                memberToRemove_ == msg.sender,
            "Unauthorized"
        );
        uint listLength = membershipLists[listName_].length;
        require(
            indexToRemove < listLength &&
                membershipLists[listName_][indexToRemove] == memberToRemove_
        );
        if (indexToRemove < listLength - 1 && listLength > 1) {
            //not the last element
            membershipLists[listName_][indexToRemove] = membershipLists[
                listName_
            ][listLength - 1];
        }
        membershipLists[listName_].pop();
    }

    function addMembersToList(bytes32 listName_, address[] calldata members_)
        external
        isListAdmin(listName_)
    {
        for (uint i = 0; i < members_.length; i++) {
            if (members_[i] != address(0)) {
                membershipLists[listName_].push(members_[i]);
            }
        }
    }

    function createPact(
        bool isEditable_,
        string calldata pactText_,
        uint256 timeLockEndTimestamp_,
        Participant[] calldata participants_,
        bytes32 memberList_,
        bool enableWithdrawingContribution
    ) external payable returns (bytes32 uid) {
        if (timeLockEndTimestamp_ != 0) {
            require(
                timeLockEndTimestamp_ < block.timestamp + maxMaturityTime,
                "Maturity Time too long"
            );
        }
        uid = calcUid(); //Calculate a unique identifier as the pact identifier
        pacts[uid].created = true;
        pacts[uid].isEditable = isEditable_;
        pacts[uid].pactText = pactText_;
        pacts[uid].totalValue = msg.value;
        if (timeLockEndTimestamp_ > 0) {
            pacts[uid].timeLockEndTimestamp = uint64(timeLockEndTimestamp_);
        }
        pacts[uid].creator = msg.sender;

        //Option to enable or disable withdrawal of contribution
        canWithdrawContribution[uid] = enableWithdrawingContribution;

        if (participants_.length > 0) addParticipants(uid, participants_);
        if (memberList_ != "") addParticipantsFromList(uid, memberList_);
        pactsCounter++;
        emit logPactCreated(msg.sender, uid);
        if (msg.value > 0) {
            contributions[uid][msg.sender] += msg.value;
            emit logContribution(uid, msg.sender, msg.value);
        }
        return uid;
    }

    // /** Function to enable withdrawing own contribution after the pact is deployed */
    function enableWithdrawContribution(bytes32 pactid)
        external
        onlyPactCreator(pactid)
    {
        if (!canWithdrawContribution[pactid]) {
            canWithdrawContribution[pactid] = true;
        }
    }

    // /** Function to add participants to a pact after its creation
    //     - Can be performed by OP
    //     - Can't be performed when voting window is active */
    function addParticipants(
        bytes32 pactid,
        Participant[] calldata participants_
    ) public onlyPactCreator(pactid) {
        require(!votingActive[pactid]);
        for (uint256 i = 0; i < participants_.length; i++) {
            pacts[pactid].participants.push(participants_[i]);
            canVote[pactid][participants_[i].addr] = participants_[i].canVote;
        }
    }

    /** Sets canVote to true for all participants from the given list for the given Pact ID  */
    function addParticipantsFromList(bytes32 pactid, bytes32 list)
        public
        onlyPactCreator(pactid)
    {
        for (uint j = 0; j < membershipLists[list].length; j++) {
            canVote[pactid][membershipLists[list][j]] = true;
        }
    }

    // /** Function to allow external addresses or participants to add funds */
    function pitchIn(bytes32 pactid) external payable {
        require(pacts[pactid].created);
        emit logContribution(pactid, msg.sender, msg.value);
        pacts[pactid].totalValue += msg.value;
        contributions[pactid][msg.sender] += msg.value;
    }

    /** Function to allow users to withdraw their share of contribution from pact id */
    function withDrawContribution(bytes32 pactid, uint amount) external {
        require(
            !votingActive[pactid] &&
                block.timestamp > pacts[pactid].timeLockEndTimestamp &&
                amount <= pacts[pactid].totalValue
        );

        if (canWithdrawContribution[pactid]) {
            uint contri = contributions[pactid][msg.sender];
            if (amount <= contri) {
                contributions[pactid][msg.sender] = contri - amount;
                pacts[pactid].totalValue -= amount;
                payable(msg.sender).transfer(amount);
            }
        }
    }

    /** OP can start voting window for a pact id */
    function startVotingWindow(
        bytes32 pactid,
        uint64 endTimeSeconds,
        bool ifRefundOnVotedNo
    ) external onlyPactCreator(pactid) {
        require(
            !votingActive[pactid] &&
                pacts[pactid].participants.length > 0 &&
                endTimeSeconds < maxVotingPeriod
        );
        pacts[pactid].votingEndTimestamp = uint64(
            block.timestamp + endTimeSeconds
        );
        pacts[pactid].refundOnVotedNo = ifRefundOnVotedNo;
        votingActive[pactid] = true;
    }

    function voteOnPact(bytes32 pactid, bool vote) external {
        require(
            // votingActive[pactid] &&
            canVote[pactid][msg.sender] &&
                !hasVoted[pactid][msg.sender] &&
                contributions[pactid][msg.sender] >=
                minVotingContribution[pactid],
            "Unauthorized"
        );
        require(block.timestamp < pacts[pactid].votingEndTimestamp);
        hasVoted[pactid][msg.sender] = true;

        if (vote) pacts[pactid].yesVotes += 1;
        else pacts[pactid].noVotes += 1;
    }

    function concludeVoting(bytes32 pactid) public {
        //Anyone with voting rights can conclude results and execution
        require(canVote[pactid][msg.sender], "Unauthorized");
        votingActive[pactid] = false;
        if (pacts[pactid].totalValue == 0) return;

        if (pacts[pactid].refundOnVotedNo) {
            canWithdrawContribution[pactid] = true;
            return;
        }

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
        uint divisions = 0;
        uint totalValueAfter = 0;
        address[] memory finalBeneficiaries;
        uint amountToSend = 0;

        // if (pacts[pactid].yesVotes > pacts[pactid].noVotes) {
        //     divisions = yesBeneficiariesCount;
        //     if (divisions != 0) {
        //         uint amountToSend = pacts[pactid].totalValue / divisions;
        //         for (uint i = 0; i < divisions; i++) {
        //             pacts[pactid].totalValue -= amountToSend;
        //             payable(yesBeneficiaries[i]).transfer(amountToSend);
        //         }
        //     }
        // } else {
        //     divisions = noBeneficiariesCount;
        //     if (divisions != 0) {
        //         uint amountToSend = pacts[pactid].totalValue / divisions;
        //         for (uint i = 0; i < divisions; i++) {
        //             pacts[pactid].totalValue -= amountToSend;
        //             payable(noBeneficiaries[i]).transfer(amountToSend);
        //         }
        //     }
        // }

        if (pacts[pactid].yesVotes > pacts[pactid].noVotes) {
            divisions = yesBeneficiariesCount;
            finalBeneficiaries = yesBeneficiaries;
        } else {
            divisions = noBeneficiariesCount;
            finalBeneficiaries = noBeneficiaries;
        }

        if (divisions != 0) {
            amountToSend = pacts[pactid].totalValue / divisions;
            for (uint i = 0; i < divisions; i++) {
                pacts[pactid].totalValue -= amountToSend;
                payable(finalBeneficiaries[i]).transfer(amountToSend);
                console.log(amountToSend);
                console.log("Sent to ");
                console.log(finalBeneficiaries[i])
;            }
            totalValueAfter = pacts[pactid].totalValue;
            pacts[pactid].totalValue = 0;

            //Send the remaining amount to the creator
            if (totalValueAfter > 0) {
                payable(pacts[pactid].creator).transfer(totalValueAfter);
            }
        }
    }

    // //Getters
    // function getPact(bytes32 pactid)
    //     external
    //     view
    //     returns (PactData memory pactData)
    // {
    //     return pacts[pactid];
    // }

    function getParticipants(bytes32 pactid)
        external
        view
        returns (Participant[] memory)
    {
        return pacts[pactid].participants;
    }

    function setText(bytes32 pactid, string memory pactText_)
        public
        onlyPactCreator(pactid)
    {
        require(pacts[pactid].isEditable);
        pacts[pactid].pactText = pactText_;
    }
}
