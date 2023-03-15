//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

///@dev Struct for storing overall contract configuration to be initialized
struct Config {
    uint32 maxVotingPeriod; //Maximum allowed voting window - for safety
    uint32 minOpenParticipationVotingPeriod; //Min voting period that should be applicable for open participation pacts, so that users don't miss the window
    uint32 commissionPerThousand;   // Commission rate in per thousand
    address commissionSink;         // EOA address to send commissions to
    address groupsContract; //Contract address for creating and managing user groups for chainpact
    uint128 minOpenParticipationAmount; // Minimum contribution amount the open participation should be set to
}

///@dev Struct for storing options related to voting for pacts
struct VotingInfo {
    bool votingEnabled; /// Whether voting is enabled for a pact
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
    bool refundAvailable;   // Whether refund of all pact's value is available for the rewspective contributors
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

/// @title Main upgradeable logic contract for Proposal Pact
/// @author Somnath B
/// @notice Contains all the functions related to creation of a pact, collecting and retrieving funds and voting
contract ProposalPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    event LogContribution(bytes32 indexed uid, address payer, uint256 amount);
    event LogPactCreated(address indexed creator, bytes32 uid);
    event LogvotingConcluded(bytes32 uid);
    event LogAmountOut(
        bytes32 indexed uid,
        address indexed payee,
        uint256 amount
    );
    event LogPactAction(bytes32 indexed uid);
    event LogWithdrawGrant(address indexed beneficiary, uint amount);


    uint internal pactsCounter; //Stores the number of pacts in this (storage) contract
    Config internal config;
    mapping(bytes32 => PactData) public pacts; //Storing data of all the pacts
    mapping(bytes32 => VotingInfo) public votingInfo;
    mapping(bytes32 => mapping(address => PactUserInteraction))
        public userInteractionData;

    mapping(address => uint) public grants;

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Config calldata config_) public initializer {
        config = config_;
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }

    /**
     * @notice Returns an integer based on whether voting isn't enabled (-100), voting is enabled and is yet to start (-1), is currently active as per the voting start time (0), was active and is now over (1)
     * @param votingInfo_ Votinginfo struct containing core info related to voting
     */
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

    /**
     * @notice Get the arrays of different pact parcitipants
     * @param pactid UID of the pact
     * @return Array of all allowed voters for a fixed participants, blank for open
     * @return YesBeneficiaries: array of all the beneficiaries set if YES vote wins
     * @return NoBeneficiaries: array all the beneficiaries set if NO vote wins
     */
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

    /**
     * @notice Function to create a proposal pact. All of the details are sent at once and only pactText can be edited later, if _isEditable param is set to true in this call.
     * @param votingInfo_ Full votingInfo for the pact id
     * @param _isEditable Whether to leave pactText editable
     * @param groupName Any name of a group created
     * @param _pactText A string to be used as the core pact text separated by </> for header and description
     * @param _voters The list of voters for a fixed voters pact, empty otherwise
     * @param _yesBeneficiaries  List of beneficiaries if YES vote wins
     * @param _noBeneficiaries List of beneficiaries if NO vote wins
     */
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
                msg.sender,
                "chainpact_proposalpact",
                pactsCounter,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );

        PactData storage pactData = pacts[uid];
        require(pactData.creator == address(0), "Already exists");
        require(bytes(_pactText).length !=0);
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
                        config_.minOpenParticipationVotingPeriod / 2    //half the duration of open participation min, because it's a more controlled set of users (supposedly)
                );
                if (_voters.length != 0 && _voters.length <= 30) _addVoters(uid, _voters);
            }
            require(votingInfo_.duration <= config_.maxVotingPeriod);

            votingInfo_.votingConcluded = false;
            if (!votingInfo_.refundOnVotedYes) {
                require(_yesBeneficiaries.length > 0);
                require(_yesBeneficiaries.length <= 30, "too many");
                pactData.yesBeneficiaries = _yesBeneficiaries;
            }
            if (!votingInfo_.refundOnVotedNo) {
                require(_noBeneficiaries.length > 0);
                require(_noBeneficiaries.length <= 30, "too many");
                pactData.noBeneficiaries = _noBeneficiaries;
            }
            votingInfo[uid] = votingInfo_;
        } else {
            votingInfo[uid].votingConcluded = true;
        }

        pactsCounter++;
        emit LogPactCreated(msg.sender, uid);
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

 
    /**
     * @notice Function to add voters to a pact after its creation
     * - Can be performed by OP
     * - Can't be performed when voting window is active
     * @param pactid Pact UID
     * @param _voters  set of adresses to add as voters
     */
    function addVoters(bytes32 pactid, address[] calldata _voters) public {
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(isVotingActive(votingInfo_) == -1, "Voting started");
        require(msg.sender == pacts[pactid].creator, "Unauthorized");
        require(!votingInfo_.openParticipation);
        require(_voters.length <= 100);
        _addVoters(pactid, _voters);
        emit LogPactAction(pactid);
    }

    // /** Function to allow external addresses or participants to add funds */
    function pitchIn(bytes32 pactid) public payable {
        require(msg.value > 0);
        require(!votingInfo[pactid].votingConcluded);
        pacts[pactid].totalValue += uint128(msg.value);
        userInteractionData[pactid][msg.sender].contribution += uint128(
            msg.value
        );
        emit LogContribution(pactid, msg.sender, msg.value);
    }

    /**
     * Function to allow users to withdraw their share of contribution from pact id
     * @param pactid UID of the pact
     * @param amount Ammount to withdraw for now
     */
    function withDrawContribution(bytes32 pactid, uint amount) external {
        //Checks
        VotingInfo memory votingInfo_ = votingInfo[pactid];

        //Require that either voting hasn't started, or refund is available for all contributors after the vote
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
        emit LogAmountOut(pactid, msg.sender, amount);

        //Interaction
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Function to withdraw beneficiary amount
     * @param amount Amount that users wishes to withdraw
     */
    function withdrawGrant(uint amount) external {
        require(grants[msg.sender] >= amount); //Checks
        grants[msg.sender] -= amount; //Effects
        uint commission = (amount*config.commissionPerThousand)/1000;
        emit LogWithdrawGrant(msg.sender, amount);
        if(commission != 0) payable(config.commissionSink).transfer(commission);
        payable(msg.sender).transfer(amount - commission); //Interactions
    }

    /**
     * @notice Creator can postpone voting window by 24 hours, before voting starts
     * @param pactid UID of the pact
     */
    function postponeVotingWindow(bytes32 pactid) external {
        require(pacts[pactid].creator == msg.sender);
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(isVotingActive(votingInfo_) == -1);
        votingInfo[pactid].votingStartTimestamp =
            votingInfo_.votingStartTimestamp +
            24 *
            60 *
            60;
        emit LogPactAction(pactid);
    }

    /**
     * @notice Function to let users vote on the proposal
     * @param pactid Pact ID
     * @param _vote The vote - true for YES and false for NO
     */
    function voteOnPact(bytes32 pactid, bool _vote) external {
        PactUserInteraction memory userData_ = userInteractionData[pactid][
            msg.sender
        ];
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        int votingStatus = isVotingActive(votingInfo_);
        if (votingStatus == -1) revert("Voting not started");
        require(votingStatus == 0, "Voting not active");
        require(userData_.canVote || votingInfo_.openParticipation);
        require(!userData_.hasVoted);
        require(
            userData_.contribution >= votingInfo[pactid].minContribution,
            "Contribution not enough"
        );
        userData_.hasVoted = true;
        userData_.castedVote = _vote;
        userInteractionData[pactid][msg.sender] = userData_;

        if (_vote) pacts[pactid].yesVotes += 1;
        else pacts[pactid].noVotes += 1;
        emit LogPactAction(pactid);
    }

    /**
     * @notice Function to disburse amounts after voting. Anyone with voting rights can conclude results and execution
     * @dev Sets the votingConcluded flag, and adds eligible pay amount to the grants map
     * @param pactid UID of the pact
     */
    function concludeVoting(bytes32 pactid) external {
        VotingInfo memory votingInfo_ = votingInfo[pactid];
        require(isVotingActive(votingInfo_) == 1, "Voting not over");
        require(!votingInfo_.votingConcluded);

        //Only one of the voters can call to conclude voting
        if (!votingInfo_.openParticipation) {
            require(userInteractionData[pactid][msg.sender].canVote);
        }

        //This check is especially useful for OpenParticipation, but is applicable for closed participation as well
        require(
            userInteractionData[pactid][msg.sender].contribution >=
                votingInfo_.minContribution
        );  

        //Set the concluded flag
        votingInfo[pactid].votingConcluded = true;

        PactData memory pactData = pacts[pactid];

        if (pactData.totalValue == 0) return;   // Nothing else to do

        address[] memory finalBeneficiaries = new address[](0);    // Stores the list of addresses to be sent the final amount to

        if (pactData.yesVotes > pactData.noVotes) {
            if (votingInfo_.refundOnVotedYes) {
                pacts[pactid].refundAvailable = true;
            } else {
                finalBeneficiaries = pactData.yesBeneficiaries; //Copy yes beneficiaries from storage to memory
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
                emit LogAmountOut(pactid, finalBeneficiaries[i], amountToSend);
            }

            //The following code will return any small leftover amount after sending it to beneficiaries
            // But given the size of the integer, the leftover amount will be way smaller than the gas cost
            // of the operation. It will be dealt with later. For now, the balance of the contract itself will
            // be a bit higher than expected.
            // uint totalValueAfter = pactData.totalValue -
            //     finalBeneficiaries.length *
            //     amountToSend;
            // if (totalValueAfter > 0) {
            //     grants[pactData.creator] += totalValueAfter;
            // }
        }
        emit LogPactAction(pactid);
    }

    /**
     * Function to change/set the text of a given pact id
     * @param pactid Pact UID
     * @param pactText_ The new text to be set
     */
    function setText(bytes32 pactid, string calldata pactText_) external {
        require(pacts[pactid].creator == msg.sender);
        require(pacts[pactid].isEditable);
        pacts[pactid].pactText = pactText_;
        emit LogPactAction(pactid);
    }
}
