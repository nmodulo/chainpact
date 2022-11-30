//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

///@dev Three types of vote options
enum VoteType {
    NONE,
    YES,
    NO
}

///@dev Three types of options related to when to start voting
enum VoteTimeOption {
    IMMEDIATE,
    GIVEN_TIME,
    MANUAL
}

///@dev Struct for storing overall contract configuration to be initialized
struct Config {
    uint32 maxMaturityTime; //Maximum allowed time for maturity - for safety
    uint32 maxVotingPeriod; //Maximum allowed voting window - for safety
    uint32 minOpenParticipationVotingPeriod;
    address groupsContract;
    uint128 minOpenParticipationAmount; //Minimum contribution amount the open participation should be set to
}

///@dev Struct for storing options related to voting for pacts
struct VotingInfo {
    bool votingEnabled;
    bool openParticipation;
    bool refundOnVotedYes;
    bool refundOnVotedNo;
    VoteTimeOption voteTimeOption;
    uint40 duration;
    uint40 votingStartTimestamp; //Timestamp at which voting window ends
    uint128 minContribution;
}

///@dev Struct for storing all pact related data
struct PactData {
    uint32 yesVotes; //Count of votes for the motion
    uint32 noVotes; //Count of votes against the motion
    uint64 timeLockEndTimestamp; //Timestamp in seconds after which the locked amount should be allowed to be withdrawn
    uint128 totalValue; //Total value held in this pact
    bool created; //Whether a pact for the pactId was created
    bool votingActive;
    bool votingEnded;
    bool refundAvailable;
    bool isEditable; //whether the pactText should be editable
    address creator; //Address of the author of original post
    string pactText; //Textual summary of proposal
    bytes32 memberList;
    address[] voters;
    address[] yesBeneficiaries;
    address[] noBeneficiaries;
}

struct PactUserInteraction {
    bool canVote;
    bool hasVoted;
    VoteType castedVote;
    uint128 contribution;
}

// UUPSUpgradeable
contract WordPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    event logContribution(bytes32 indexed uid, address payer, uint256 amount);
    event logPactCreated(address indexed creator, bytes32 uid);
    event logVotingStarted(bytes32 uid);
    event logVotingEnded(bytes32 uid);
    event logMembershipListCreated(address indexed creator, string listName);
    event logAmountOut(
        bytes32 indexed uid,
        address indexed payee,
        uint256 amount
    );
    //Data
    uint public pactsCounter; //Stores the number of pacts in this (storage) contract
    Config public config;
    mapping(bytes32 => PactData) public pacts; //Storing data of all the pacts
    mapping(bytes32 => VotingInfo) public votingInfo;
    mapping(bytes32 => mapping(address => PactUserInteraction))
        public userInteractionData;

    mapping(bytes32 => bool) public votingActive; //If voting is active on a given pact address
    mapping(address => uint) public grants;

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    modifier onlyPactCreator(bytes32 pactid) {
        require(pacts[pactid].creator == msg.sender);
        _;
    }

    function initialize(Config calldata _config) public initializer {
        config = _config;
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }

    //Logic
    function calcUid() public view returns (bytes32 uid) {
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    msg.sender,
                    "chainpact_proposalpact",
                    pactsCounter
                )
            );
    }

    function createPact(
        uint256 _timeLockEndTimestamp,
        VotingInfo memory votingInfo_,
        bool _isEditable,
        string calldata _pactText,
        string calldata _memberList,
        address[] calldata _voters,
        address[] calldata _yesBeneciaries,
        address[] calldata _noBeneficiaries
    ) external payable returns (bytes32 uid) {
        Config memory config_ = config;
        PactData memory pactData_;

        if (_timeLockEndTimestamp != 0) {
            require(
                _timeLockEndTimestamp <
                    block.timestamp + config_.maxMaturityTime,
                "locktime too long"
            );
            pactData_.timeLockEndTimestamp = uint64(_timeLockEndTimestamp);
        }

        ///@dev voting related checks
        if (votingInfo_.votingEnabled) {
            require(votingInfo_.refundOnVotedYes || _yesBeneciaries.length > 0);
            require(votingInfo_.refundOnVotedNo || _noBeneficiaries.length > 0);
            if (votingInfo_.openParticipation) {
                require(
                    votingInfo_.minContribution >=
                        config_.minOpenParticipationAmount
                );
            }
            require(votingInfo_.duration <= config_.maxVotingPeriod);

            if (votingInfo_.voteTimeOption == VoteTimeOption.MANUAL) {
                require(!votingInfo_.openParticipation);
            } else if (
                votingInfo_.voteTimeOption == VoteTimeOption.GIVEN_TIME
            ) {
                require(votingInfo_.votingStartTimestamp > block.timestamp);
            } else {
                votingInfo_.votingStartTimestamp = uint40(block.timestamp);
            }
        }

        uid = calcUid(); //Calculate a unique identifier as the pact identifier
        pactData_.created = true;
        pactData_.isEditable = _isEditable;
        pactData_.pactText = _pactText;
        pactData_.creator = msg.sender;

        votingInfo[uid] = votingInfo_;

        if (_voters.length != 0) addVoters(uid, _voters);
        // if (bytes(_memberList).length > 0) {
        //     addParticipantsFromList(uid, memberList_);
        // }
        pactsCounter++;
        emit logPactCreated(msg.sender, uid);
        if (msg.value > 0) {
            pitchIn(uid);
        }
        return uid;
    }

    // /** Function to add participants to a pact after its creation
    //     - Can be performed by OP
    //     - Can't be performed when voting window is active */
    function addVoters(
        bytes32 pactid,
        address[] calldata _voters
    ) public onlyPactCreator(pactid) {
        require(!pacts[pactid].votingActive);
        require(!votingInfo[pactid].)
        for (uint i = 0; i < _voters.length; i++) {
            pacts[pactid].voters.push(_voters[i]);
            userInteractionData[pactid][_voters[i]].canVote = true;
        }
    }

    /** Sets canVote to true for all participants from the given list for the given Pact ID  */
    // function addParticipantsFromList(bytes32 pactid, string calldata listName)
    //     public
    //     onlyPactCreator(pactid)
    // {
    //     for (uint j = 0; j < membershipLists[listName].length; j++) {
    //         canVote[pactid][membershipLists[listName][j]] = true;
    //     }
    // }

    // /** Function to allow external addresses or participants to add funds */
    function pitchIn(bytes32 pactid) public payable {
        require(pacts[pactid].created && msg.value > 0);
        pacts[pactid].totalValue += uint128(msg.value);
        userInteractionData[pactid][msg.sender].contribution += uint128(
            msg.value
        );
        emit logContribution(pactid, msg.sender, msg.value);
    }

    /** Function to allow users to withdraw their share of contribution from pact id */
    function withDrawContribution(bytes32 pactid, uint amount) external {
        require(
            !votingActive[pactid] &&
                block.timestamp > pacts[pactid].timeLockEndTimestamp &&
                amount <= pacts[pactid].totalValue
        );

        uint contri = userInteractionData[pactid][msg.sender].contribution;
        if (amount <= contri) {
            userInteractionData[pactid][msg.sender].contribution = uint128(
                contri - amount
            );
            pacts[pactid].totalValue -= uint128(amount);
            payable(msg.sender).transfer(amount);
            emit logAmountOut(pactid, msg.sender, amount);
        }
    }

    function withdrawGrant(uint amount) external {
        if (grants[msg.sender] >= amount) {
            grants[msg.sender] -= amount;
            payable(msg.sender).transfer(amount);
        }
    }

    /** OP can start voting window for a pact id */
    function startVotingWindow(
        bytes32 pactid,
        uint64 endTimeSeconds,
        bool ifRefundOnVotedNo
    ) external onlyPactCreator(pactid) {
        Config memory config_ = config;
        require(
            !votingActive[pactid] &&
                pacts[pactid].voters.length > 0 &&
                endTimeSeconds < config_.maxVotingPeriod
        );
        votingInfo[pactid].duration = uint32(endTimeSeconds);
        if (ifRefundOnVotedNo) votingInfo[pactid].refundOnVotedNo = true;
        pacts[pactid].votingActive = true;
    }

    // function voteOnPact(bytes32 _pactid, VoteType _vote) external {
    //     PactUserInteraction memory userData_ = userInteractionData[_pactid][msg.sender];
    //     VotingInfo memory votingInfo_ = votingInfo[_pactid];

    //     require(
    //         // votingActive[pactid] &&
    //         userData_.canVote &&
    //             !userData_.hasVoted &&
    //             userData_.contribution >=
    //             votingInfo[_pactid].minContribution,
    //         "Unauthorized"
    //     );
    //     require(block.timestamp < votingInfo_.votingEndTimestamp);
    //     userData_.hasVoted = true;
    //     userData_.castedVote = _vote;

    //     if (_vote == VoteType.YES) pacts[_pactid].yesVotes += 1;
    //     else if(_vote == VoteType.NO) pacts[_pactid].noVotes += 1;
    // }

    // function concludeVoting(bytes32 pactid) public {
    //     //Anyone with voting rights can conclude results and execution
    //     require(userInteractionData[pactid][msg.sender].canVote, "Unauthorized");
    //     require(block.timestamp > votingInfo[pactid].votingEndTimestamp);
    //     pacts[pactid].votingActive = false;
    //     pacts[pactid].votingEnded = true;
    //     if (pacts[pactid].totalValue == 0) return;
    //     VotingInfo memory votingInfo_ = votingInfo[pactid];

    //     address[] storage finalBeneficiaries;

    //     if (pacts[pactid].yesVotes > pacts[pactid].noVotes) {
    //         if(votingInfo_.refundOnVotedYes){
    //             pacts[pactid].refundAvailable = true;
    //             return;
    //         }
    //         finalBeneficiaries = pacts[pactid].yesBeneficiaries;
    //     } else if(votingInfo[pactid].refundOnVotedNo) {
    //         pacts[pactid].refundAvailable = true;
    //         return;
    //     } else {
    //         if(votingInfo_.refundOnVotedNo){
    //             pacts[pactid].refundAvailable = true;
    //             return;
    //         }
    //         finalBeneficiaries = pacts[pactid].noBeneficiaries;
    //     }

    //     uint finalBeneficiariesLength = finalBeneficiaries.length;

    //     if (finalBeneficiariesLength != 0) {
    //         uint totalValue_ = pacts[pactid].totalValue;
    //         uint amountToSend = totalValue_/finalBeneficiariesLength;
    //         pacts[pactid].totalValue = 0;
    //         amountToSend = pacts[pactid].totalValue / finalBeneficiariesLength;
    //         for (uint i = 0; i < finalBeneficiariesLength; i++) {
    //             grants[finalBeneficiaries[i]] = amountToSend;
    //             emit logAmountOut(pactid, finalBeneficiaries[i], amountToSend);
    //         }

    //         totalValue_ = totalValue_ - finalBeneficiariesLength * amountToSend;
    //         if(totalValue_ > 0){
    //             grants[pacts[pactid].creator] = totalValue_;
    //         }
    //     }
    // }

    // function getParticipants(bytes32 _pactid, VoteType _voteType)
    //     external
    //     view
    //     returns (address[]  memory addr_, VoteType[] memory voteType_){
    //     uint votersLength_ = pacts[_pactid].voters.length;
    //     uint yesBeneciariesLength_ = pacts[_pactid].yesBeneciaries.length;
    //     uint noBeneficiariesLength_ = pacts[_pactid].noBeneficiaries.length;
    //     for(uint i=0; i<votersLength_; i++){
    //         addr_.push(pacts[_pactid].voters[i]);
    //         voteType_.push(VoteType.NONE);
    //     }
    // }

    function setText(
        bytes32 pactid,
        string memory pactText_
    ) public onlyPactCreator(pactid) {
        require(pacts[pactid].isEditable);
        pacts[pactid].pactText = pactText_;
    }
}
