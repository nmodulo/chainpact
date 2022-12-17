//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

///@dev Struct for storing overall contract configuration to be initialized
struct Config {
    uint32 maxVotingPeriod; //Maximum allowed voting window - for safety
    uint32 minOpenParticipationVotingPeriod; //Min voting period that should be applicable for open participation pacts, so that users don't miss the window
    address groupsContract; //Contract address for creating and managing user groups for chainpact
    uint128 minOpenParticipationAmount; //Minimum contribution amount the open participation should be set to
}

///@dev Struct for storing options related to voting for pacts
struct VotingInfo {
    bool votingEnabled; //Whether voting is enabled for a pact
    bool openParticipation; //Whether the voting is open to all
    bool refundOnVotedYes; //Make the refundAvailable flag true if yes > no
    bool refundOnVotedNo; //Make the refundAvailable flag true if no >= yes
    bool votingConcluded; //Whether voting window was set, and now concluded
    uint40 duration; //Duration of voting window in Seconds
    uint40 votingStartTimestamp; //Timestamp at which voting window starts
    uint128 minContribution; //Minimum contribution that every allowed voter must have before they can vote
}

///@dev Struct for storing all pact related data
struct PactData {
    uint32 yesVotes; //Count of votes for the motion
    uint32 noVotes; //Count of votes against the motion
    uint128 totalValue; //Total value held against this pact
    bool refundAvailable;
    bool isEditable; //whether the pactText should be editable
    address creator; //Address of the author of original post
    bytes32 groupName; 
    string pactText; //Textual summary of proposal
    // bytes32 memberList;
    address[] voters;
    address[] yesBeneficiaries;
    address[] noBeneficiaries;
}

///@dev Struct for storing all user related data
struct PactUserInteraction {
    bool canVote;
    bool hasVoted;
    bool castedVote;
    uint128 contribution;
}

// UUPSUpgradeable
contract ProposalPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    event logContribution(bytes32 indexed uid, address payer, uint256 amount);
    event logPactCreated(address indexed creator, bytes32 uid);
    event logvotingConcluded(bytes32 uid);
    event logAmountOut(
        bytes32 indexed uid,
        address indexed payee,
        uint256 amount
    );
    //Data
    uint internal pactsCounter; //Stores the number of pacts in this (storage) contract
    Config internal config;
    mapping(bytes32 => PactData) public pacts; //Storing data of all the pacts
    mapping(bytes32 => VotingInfo) public votingInfo;
    mapping(bytes32 => mapping(address => PactUserInteraction))
        public userInteractionData;

    mapping(address => uint) public grants;

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function isVotingActive(
        VotingInfo memory votingInfo_
    ) internal view returns (int) {
        if (!votingInfo_.votingEnabled) {
            return -100;
        }
        if (block.timestamp < votingInfo_.votingStartTimestamp) {
            return -1;
        }
        if (
            block.timestamp >
            votingInfo_.votingStartTimestamp + votingInfo_.duration
        ) {
            return 1;
        }
        return 0;
    }

    function getParticipants(
        bytes32 pactid
    )
        external
        view
        returns (address[] memory, address[] memory, address[] memory)
    {
        return (
            pacts[pactid].voters,
            pacts[pactid].yesBeneficiaries,
            pacts[pactid].noBeneficiaries
        );
    }

    function initialize(Config calldata _config) public initializer {
        config = _config;
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }

    function createPact(
        VotingInfo memory votingInfo_,
        bool _isEditable,
        bytes32 groupName,
        string calldata _pactText,
        address[] calldata _voters,
        address[] calldata _yesBeneficiaries,
        address[] calldata _noBeneficiaries
    ) external payable {
        Config memory config_ = config;
        bytes32 uid = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                "chainpact_proposalpact",
                pactsCounter
            )
        );
        PactData storage pactData = pacts[uid];
        pactData.isEditable = _isEditable;
        pactData.pactText = _pactText;
        pactData.creator = msg.sender;
        pactData.groupName = groupName;
        ///@dev voting related checks
        if (votingInfo_.votingEnabled) {
            if (votingInfo_.votingStartTimestamp < block.timestamp) {
                votingInfo_.votingStartTimestamp = uint40(
                    block.timestamp + 30 * 60 //add half an hour grace period
                );
            }
            if (votingInfo_.openParticipation) {
                require(
                    votingInfo_.minContribution >=
                        config_.minOpenParticipationAmount
                );
                require(
                    votingInfo_.duration >=
                        config_.minOpenParticipationVotingPeriod
                );
            } else {
                require(
                    votingInfo_.duration >=
                        config_.minOpenParticipationVotingPeriod / 2
                );
                if (_voters.length != 0) _addVoters(uid, _voters);
            }
            require(votingInfo_.duration <= config_.maxVotingPeriod);

            votingInfo_.votingConcluded = false;
            if (!votingInfo_.refundOnVotedYes) {
                require(_yesBeneficiaries.length > 0);
                pactData.yesBeneficiaries = _yesBeneficiaries;
            }
            if (!votingInfo_.refundOnVotedNo) {
                require(_noBeneficiaries.length > 0);
                pactData.noBeneficiaries = _noBeneficiaries;
            }
        }

        votingInfo[uid] = votingInfo_;
        pactsCounter++;
        emit logPactCreated(msg.sender, uid);
        if (msg.value > 0) {
            pitchIn(uid);
        }
    }

    function _addVoters(bytes32 pactid, address[] calldata _voters) internal {
        for (uint i = 0; i < _voters.length; i++) {
            if (!userInteractionData[pactid][_voters[i]].canVote) {
                pacts[pactid].voters.push(_voters[i]);
                userInteractionData[pactid][_voters[i]].canVote = true;
            }
        }
    }

    ///@dev Function to add voters to a pact after its creation
    //     - Can be performed by OP
    //     - Can't be performed when voting window is active */
    function addVoters(bytes32 pactid, address[] calldata _voters) public {
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(isVotingActive(votingInfo_) == -1, "Voting started");
        require(msg.sender == pacts[pactid].creator, "Unauthorized");
        require(!votingInfo_.openParticipation);
        _addVoters(pactid, _voters);
    }

    // /** Function to allow external addresses or participants to add funds */
    function pitchIn(bytes32 pactid) public payable {
        require(msg.value > 0);
        require(!votingInfo[pactid].votingConcluded);
        pacts[pactid].totalValue += uint128(msg.value);
        userInteractionData[pactid][msg.sender].contribution += uint128(
            msg.value
        );
        emit logContribution(pactid, msg.sender, msg.value);
    }

    /** Function to allow users to withdraw their share of contribution from pact id */
    function withDrawContribution(bytes32 pactid, uint amount) external {
        //Checks
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(
            isVotingActive(votingInfo_) == -1 || pacts[pactid].refundAvailable,
            "Withdraw unavailable"
        );
        uint contri = userInteractionData[pactid][msg.sender].contribution;
        require(amount <= contri);

        //Effects
        userInteractionData[pactid][msg.sender].contribution = uint128(
            contri - amount
        );
        pacts[pactid].totalValue -= uint128(amount);
        emit logAmountOut(pactid, msg.sender, amount);

        //Interaction
        payable(msg.sender).transfer(amount);
    }

    function withdrawGrant(uint amount) external {
        require(grants[msg.sender] >= amount); //Checks
        grants[msg.sender] -= amount; //Effects
        payable(msg.sender).transfer(amount); //Interactions
    }

    /** OP can postpone voting window by 24 hours */
    function postponeVotingWindow(bytes32 pactid) external {
        require(pacts[pactid].creator == msg.sender);
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(isVotingActive(votingInfo_) == -1);
        votingInfo[pactid].votingStartTimestamp =
            votingInfo_.votingStartTimestamp +
            24 *
            60 *
            60;
    }

    function voteOnPact(bytes32 _pactid, bool _vote) external {
        PactUserInteraction memory userData_ = userInteractionData[_pactid][
            msg.sender
        ];
        VotingInfo memory votingInfo_ = votingInfo[_pactid];
        int votingStatus = isVotingActive(votingInfo_);
        if (votingStatus == -1) revert("Voting not started");
        require(votingStatus == 0, "Voting not active");
        // else if(votingStatus == 1) revert("Voting over");
        // else if(votingStatus == 100) revert("Voting disabled");
        // require(isVotingActive(votingInfo_) == 0, "Voting inactive");
        require(userData_.canVote || votingInfo_.openParticipation);
        require(!userData_.hasVoted);
        require(
            userData_.contribution >= votingInfo[_pactid].minContribution,
            "Contribution not enough"
        );
        userData_.hasVoted = true;
        userData_.castedVote = _vote;
        userInteractionData[_pactid][msg.sender] = userData_;

        if (_vote) pacts[_pactid].yesVotes += 1;
        else pacts[_pactid].noVotes += 1;
    }

    ///@dev Function to disburse amounts after voting. Anyone with voting rights can conclude results and execution
    function concludeVoting(bytes32 pactid) external {
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(isVotingActive(votingInfo_) == 1, "Voting not over");
        require(!votingInfo_.votingConcluded);
        if (!votingInfo_.openParticipation) {
            require(userInteractionData[pactid][msg.sender].canVote);
        }
        require(
            userInteractionData[pactid][msg.sender].contribution >=
                votingInfo_.minContribution
        );

        PactData memory pactData = pacts[pactid];
        if (pactData.totalValue == 0) return;

        address[] memory finalBeneficiaries;

        if (pactData.yesVotes > pactData.noVotes) {
            if (votingInfo_.refundOnVotedYes) {
                pacts[pactid].refundAvailable = true;
            } else {
                finalBeneficiaries = pactData.yesBeneficiaries;
            }
        } else if (votingInfo_.refundOnVotedNo) {
            pacts[pactid].refundAvailable = true;
        } else {
            finalBeneficiaries = pactData.noBeneficiaries;
        }

        if (finalBeneficiaries.length != 0) {
            uint amountToSend = pactData.totalValue / finalBeneficiaries.length;
            pacts[pactid].totalValue = 0;
            for (uint i = 0; i < finalBeneficiaries.length; i++) {
                grants[finalBeneficiaries[i]] += amountToSend;
                emit logAmountOut(pactid, finalBeneficiaries[i], amountToSend);
            }

            uint totalValueAfter = pactData.totalValue -
                finalBeneficiaries.length *
                amountToSend;
            if (totalValueAfter > 0) {
                grants[pactData.creator] += totalValueAfter;
            }
        }
        votingInfo[pactid].votingConcluded = true;
    }

    function setText(bytes32 pactid, string calldata pactText_) external {
        require(pacts[pactid].creator == msg.sender);
        require(pacts[pactid].isEditable);
        pacts[pactid].pactText = pactText_;
    }
}
