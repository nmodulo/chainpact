//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/PactSignature.sol";
import "./libraries/DisputeHelper.sol";
import "./libraries/PaymentHelper.sol";
import "./Structs.sol";
import "../Interface/ChainPact.sol";

/**
 * @title ChainPact main logic contract
 * @author Somnath B
 * @notice The main logic contract of Gig pact
 * @dev Still in pre-alpha stage, report issues to chainpact@nmodulo.com
 * @dev To be used with OpenZeppelin upgrades plugin
 */
contract GigPactUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ChainPact
{
    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Disables initialization on the logic contract after deployment, since the proxy contract will not call this constructor
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    ///@dev Initialize function be used from the delegator/proxy contract only
    function initialize(
        uint commissionPercentage_,
        address commissionSink_
    ) public initializer {
        commissionPercentage = commissionPercentage_;
        commissionSink = commissionSink_;
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
    }

    /**
     * @notice Event triggered upon payment from employer to employee
     * @param pactid The UID for the pact
     * @param value Value of the payment made
     * @param payer The wallet making the payment, usually Employer
     */
    event LogPaymentMade(
        bytes32 indexed pactid,
        uint value,
        address indexed payer
    );

    /**
     * @notice Event emitted whenever a change to pactState is made by any party or delegated account
     * @param pactid The UID of the pact
     * @param newState The resulting new state
     * @param updater The account that triggered this change
     */
    event LogStateUpdate(
        bytes32 indexed pactid,
        PactState newState,
        address indexed updater
    );

    event LogPactAction(bytes32 indexed pactid);

    //     event LogPactAction2(
    //     bytes32 indexed pactid,
    //     string action,
    //     bytes32[] data
    // );

    /// @dev for a pausing mechanism
    bool private _paused;

    /// @dev keeps the count of the pacts, not to be called from outside
    uint private pactsCounter;
    /// @notice The core pact data mapped to pactId
    mapping(bytes32 => PactData) public pactData;
    /// @notice The pact pay related data mapped to pactId
    mapping(bytes32 => PayData) public payData;
    /// @notice Mapping to identify for a given pactId, whether an account is an employee delegatee
    mapping(bytes32 => mapping(address => bool)) public isEmployeeDelegate;
    /// @notice Mapping to identify for a given pactId, whether an account is an employer delegatee
    mapping(bytes32 => mapping(address => bool)) public isEmployerDelegate;
    /// @notice Hash of any external document to be added along with pactData
    mapping(bytes32 => bytes32) public externalDocumentHash;
    /// @dev Commission rate per cent
    uint private commissionPercentage;
    /// @dev Address (EOA) of where the commissions are sent to
    address private commissionSink;

    /**
     * @notice Get the list of arbitrators currently proposed (if any)
     * @param pactid The UID of the pact
     */
    function getArbitratrators(
        bytes32 pactid
    ) external view returns (Arbitrator[] memory) {
        return pactData[pactid].proposedArbitrators;
    }

    modifier onlyEmployer(bytes32 pactid) {
        require(
            isEmployerDelegate[pactid][msg.sender],
            "employer delegate only"
        );
        _;
    }

    modifier onlyEmployee(bytes32 pactid) {
        require(
            isEmployeeDelegate[pactid][msg.sender],
            "employee delegate only"
        );
        _;
    }

    modifier isActive(bytes32 pactid) {
        require(pactData[pactid].pactState == PactState.ACTIVE, "not active");
        _;
    }

    modifier isEOA() {
        require(msg.sender == tx.origin);
        _;
    }

    modifier whenNotPaused() {
        require(!_paused);
        _;
    }

    /// @dev To be used to pause/unpause in panic
    function pauseUnpausePanic(bool toPause) external onlyOwner {
        _paused = toPause;
    }

    /**
     * @notice Function to tell if an account is party to the pact in any way
     * @param pactid The Pact UID
     * @param party The address to check
     */
    function isParty(bytes32 pactid, address party) public view returns (bool) {
        return
            isEmployeeDelegate[pactid][party] ||
            isEmployerDelegate[pactid][party];
    }

    /**
     * @notice Function to create a new Gig pact.
     * @dev Creates a UID based on the sender's address, pactCounter and block information, deemed unique, however,     predictable.
     * @dev Should be created by an externally owned address, as some functionality may break if an external contract tries to create and manage pacts.
     * @param pactName_ Name for this pact
     * @param employee_ The receiver of payment
     * @param employer_ The payer
     * @param payScheduleDays_ The number of days in which the payAmount should be paid
     * @param payAmount_ The amount to be paid - decimals to be inferrred from erc20TokenAddress
     * @param erc20TokenAddress_ The token address, if any, or address(0) to use native value
     * @param externalDocumentHash_ The hash of text of any External Document to be attached to the pact
     */

    function createPact(
        bytes32 pactName_,
        address employee_,
        address employer_,
        uint32 payScheduleDays_,
        uint128 payAmount_,
        address erc20TokenAddress_,
        bytes32 externalDocumentHash_
    ) external isEOA {
        require(payAmount_ > 0 && pactName_ != 0);
        bytes32 uid = keccak256(
            abi.encodePacked(
                msg.sender,
                "chainpact_gigpact",
                pactsCounter,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );
        require(pactData[uid].pactState == PactState.NULL);
        pactData[uid].pactState = PactState.DEPLOYED;
        pactData[uid].pactName = pactName_;
        pactData[uid].employee = employee_;
        pactData[uid].payScheduleDays = payScheduleDays_;
        pactData[uid].employer = employer_;
        if (erc20TokenAddress_ != address(0))
            pactData[uid].erc20TokenAddress = erc20TokenAddress_;
        pactData[uid].payAmount = payAmount_;
        if (externalDocumentHash_ != 0)
            externalDocumentHash[uid] = externalDocumentHash_;
        isEmployeeDelegate[uid][employee_] = true;
        isEmployerDelegate[uid][employer_] = true;
        pactsCounter++;
        emit LogPactCreated(msg.sender, uid);
    }

    /**
     * @notice Function to record the signature of the parties for future use
     * @param pactid The UID for the pact
     * @param signature The signature coming from the user's wallet, that is a sign on the hash of the pact data
     * @param signingDate_ The date the msg.sender deems the signature was created using
     */
    function signPact(
        bytes32 pactid,
        bytes calldata signature,
        uint256 signingDate_
    ) external payable whenNotPaused {
        PactSignature.checkSignPact(
            pactid,
            pactData[pactid],
            signature,
            externalDocumentHash[pactid],
            signingDate_,
            commissionPercentage,
            commissionSink
        );
    }

    /**
     * @notice Function to add other EOAs
     * @param pactid UID of the pact
     * @param delegates List of addresses to give powers of delegation to, for this pact related actions (not to be confused with delegate in other ERC's)
     * @param addOrRevoke Either revoke or grant, based on whether this flag is true or false
     */
    function delegatePact(
        bytes32 pactid,
        address[] calldata delegates,
        bool addOrRevoke
    ) external whenNotPaused {
        require(pactData[pactid].pactState >= PactState.ALL_SIGNED);
        if (msg.sender == pactData[pactid].employer) {

            for (uint i = 0; i < delegates.length; i++) {
                isEmployerDelegate[pactid][delegates[i]] = addOrRevoke;
            }
        } else if (msg.sender == pactData[pactid].employee) {

            for (uint i = 0; i < delegates.length; i++) {
                isEmployeeDelegate[pactid][delegates[i]] = addOrRevoke;
            }
        } else {
            revert();
        }
        emit LogPactAction(
            pactid);
    }

    /**
     * @notice Function to start or pause a pact, making it active or Paused
     * @dev can be used for "start pact" or "pause pact" or "resume pact"
     * @param pactid Pact UID
     * @param toStart true for starting, false for pausing
     */
    function startPausePact(
        bytes32 pactid,
        bool toStart
    ) external onlyEmployer(pactid) {
        PayData memory payData_ = payData[pactid];
        PactState updatedState_ = pactData[pactid].pactState;
        if (toStart) {
            if (updatedState_ == PactState.ALL_SIGNED) {
                updatedState_ = PactState.ACTIVE;
                /// @dev Storing the timestamp as now to consider pro-rata payment from this point on
                payData_.lastPayTimeStamp = uint40(block.timestamp);
                payData_.lastPayAmount = 0;
            } else if (updatedState_ == PactState.PAUSED) {
                /// @dev the pause duration gets added up since last pauseResumeTime, considering there could be multiple pauses before a payment is made
                payData_.pauseDuration +=
                    uint40(block.timestamp) -
                    payData_.pauseResumeTime;
                payData_.pauseResumeTime = uint40(block.timestamp);
            } else revert();
            updatedState_ = PactState.ACTIVE;
        } else if (pactData[pactid].pactState == PactState.ACTIVE) {
            updatedState_ = PactState.PAUSED;
            payData_.pauseResumeTime = uint40(block.timestamp);
        } else revert(); /// @dev don't allow if the pactState is something else
        payData[pactid] = payData_;
        pactData[pactid].pactState = updatedState_;
        emit LogStateUpdate(pactid, updatedState_, msg.sender);
    }

    /**
     * @notice Function to add a record of an external payment
     * @dev Doesn't do much, except for adding a record
     * @param pactid Pact UID
     * @param payTime The timestamp of claimed payment
     * @param confirm Whether to confirm (true) or reject (false)
     */
    // function uselessAddExternalPayClaim(
    //     bytes32 pactid,
    //     uint payTime,
    //     bool confirm
    // ) external isActive(pactid) {
    //     PaymentHelper.addExternalPayClaim(pactid, payTime, confirm, payData[pactid]);
    // }

    /**
     * @notice Function to send payment from employer to employee
     * @dev The payAmount can be both in ERC20 terms or native value tokens
     * @dev The payment is sent directly with this, not a pull payment
     * @param pactid Pact UID
     */
    function approvePayment(
        bytes32 pactid
    ) external payable onlyEmployer(pactid) isActive(pactid) whenNotPaused {
        (address employee, uint payAmount, address erc20TokenAddress) = (
            pactData[pactid].employee,
            pactData[pactid].payAmount,
            pactData[pactid].erc20TokenAddress
        );

        bool result;
        if (erc20TokenAddress == address(0)) {
            require(
                msg.value >=
                    payAmount + (payAmount * commissionPercentage) / 200, /// @dev Charge half the commission from the employer
                "Amount less than payAmount"
            );
            require(
                payable(commissionSink).send(
                    (payAmount * commissionPercentage) / 100
                )
            );
            result = payable(employee).send(
                msg.value - (payAmount * commissionPercentage) / 100 /// @dev Effectively cutting another half of commission percent
            );
        } else {
            // IERC20 tokenContract = IERC20(pactData_.erc20TokenAddress);
            require(
                IERC20(erc20TokenAddress).transferFrom(
                    msg.sender,
                    commissionSink,
                    (payAmount * commissionPercentage) / 100
                )
            );
            result = IERC20(erc20TokenAddress).transferFrom(
                msg.sender,
                employee,
                payAmount - (payAmount * commissionPercentage) / 200
            );
        }
        if (result) {
            payData[pactid].lastPayTimeStamp = uint40(block.timestamp); /// @dev reset the lastPayTimeStamp to consider for pro-rata payments from NOW
            payData[pactid].lastPayAmount = uint128(
                erc20TokenAddress == address(0) ? msg.value : payAmount /// @dev no option for a "tip" with ERC-20 payments, payAmount is sent & recorded
            );
            payData[pactid].pauseDuration = 0; /// @dev reset the pause duration for future considerations
            emit LogPaymentMade(pactid, msg.value, msg.sender);
        } else {
            revert();
        }
    }

    /**
     * @notice Function to reclaim stake to be used by the employer
     * @param pactid Pact UID
     * @param payee The account to transfer the money to
     */
    function reclaimStake(
        bytes32 pactid,
        address payable payee
    ) external onlyEmployer(pactid) isEOA whenNotPaused {
        // PactData memory pactData_ = pactData[pactid];
        require(payee != address(0));
        (PactState pactState_, uint stakeAmount_) = (
            pactData[pactid].pactState,
            pactData[pactid].stakeAmount
        );
        require(stakeAmount_ > 0);
        if (pactState_ >= PactState.FNF_SETTLED) {
            pactState_ = PactState.ENDED;
        } else if (pactState_ == PactState.EMPLOYER_SIGNED) {
            pactState_ = PactState.RETRACTED;
        } else revert();
        bool result;

        pactData[pactid].stakeAmount = 0;
        pactData[pactid].pactState = pactState_;
        emit LogStateUpdate(pactid, pactState_, msg.sender);

        if (pactData[pactid].erc20TokenAddress == address(0)) {
            result = payee.send(stakeAmount_);
        } else {
            result = IERC20(pactData[pactid].erc20TokenAddress).transfer(
                payee,
                stakeAmount_
            );
        }
        if (!result) revert();
    }

    /**
     * @notice Function to initiate termination by either parties and their delegates
     *          Marks the pact as RESIGNED if initiated by employee or delegates,
     *          as TERMINATED if initiated by employer or delegates
     * @param pactid Pact UID
     */
    function terminate(bytes32 pactid) external isEOA isActive(pactid) {
        // PayData memory payData_ = payData[pactid];
        (uint lastPayTimeStamp, uint pauseDuration) = (
            payData[pactid].lastPayTimeStamp,
            payData[pactid].pauseDuration
        );
        (
            PactState pactState_,
            uint payScheduleDays,
            address employer,
            uint payAmount,
            uint stakeAmount_
        ) = (
                pactData[pactid].pactState,
                pactData[pactid].payScheduleDays,
                pactData[pactid].employer,
                pactData[pactid].payAmount,
                pactData[pactid].stakeAmount
            );

        uint refundAmount_ = 0;
        if (isEmployeeDelegate[pactid][msg.sender]) {
            pactState_ = PactState.RESIGNED;
        } else if (isEmployerDelegate[pactid][msg.sender]) {
            ///@dev Payment due assumed
            uint paymentDue = (payAmount *
                (block.timestamp - lastPayTimeStamp - pauseDuration)) /
                (payScheduleDays * 86400);
            if (paymentDue >= stakeAmount_) paymentDue = stakeAmount_;

            refundAmount_ = stakeAmount_ - paymentDue;
            pactData[pactid].stakeAmount = uint128(paymentDue);
            pactState_ = PactState.TERMINATED;
        } else revert("Unauthorized");
        pactData[pactid].pactState = pactState_;
        emit LogStateUpdate(pactid, pactState_, msg.sender);

        address erc20TokenAddress = pactData[pactid].erc20TokenAddress;
        if (erc20TokenAddress == address(0)) {
            payable(employer).transfer(refundAmount_);
        } else {
            require(
                IERC20(erc20TokenAddress).transfer(employer, refundAmount_)
            );
        }
    }

    /**
     * @notice Function to send full and final settlement by either parties
     * @param pactid Pact UID
     * @param tokenAmount Amount of tokens, if the payment mode is ERC-20 token/stablecoin
     */
    function fNf(
        bytes32 pactid,
        uint tokenAmount
    ) external payable whenNotPaused {
        PaymentHelper.fNf(
            pactid,
            tokenAmount,
            pactData[pactid],
            payData[pactid]
        );
    }

    function claimAutoPayAfterDormancy(bytes32 pactid) external {
        PaymentHelper.claimAutoPayAfterDormancy(
            pactid,
            pactData[pactid],
            payData[pactid],
            commissionPercentage,
            commissionSink
        );
    }

    /**
     * @notice Function to raise a dispute by the employee or a delegate. Puts the state of the
     *  pact into DISPUTED, and assigns a proposed "dispute amount". The hope is that
     *  the employer will send in this dispute amount and resolve it readily.
     * @dev the pactData and payData are passed as storage
     * @param pactid Pact UID
     * @param suggestedAmountClaim The amount claimed by the
     */
    function dispute(bytes32 pactid, uint suggestedAmountClaim) external {
        DisputeHelper.dispute(
            pactid,
            pactData[pactid],
            payData[pactid],
            suggestedAmountClaim
        );
    }

    /**
     * @notice Function to let third party list of accounts act as dispute arbitrators.
     *         Can only be called when the pactState is DISPUTED
     * @param pactid Pact UID
     * @param proposedArbitrators_ The list of accounts to act as arbitrators who can mark the pact resolved
     */
    function proposeArbitrators(
        bytes32 pactid,
        address[] calldata proposedArbitrators_
    ) external {
        DisputeHelper.proposeArbitrators(
            pactid,
            pactData[pactid],
            proposedArbitrators_
        );
    }

    /**
     * @notice Function to accept or reject set of arbitrators proposed by the other party
     * @param pactid Pact UID
     * @param acceptOrReject Whether to accept (true) or reject (false) the list of accounts as arbitrators, proposed by the other party
     */
    function acceptOrRejectArbitrators(
        bytes32 pactid,
        bool acceptOrReject
    ) external {
        DisputeHelper.acceptOrRejectArbitrators(
            pactid,
            pactData[pactid],
            acceptOrReject
        );
    }

    /**
     * @notice To be used by all arbitrators to mark the pact as resolved
     * @param pactid Pact UID
     */
    function arbitratorResolve(bytes32 pactid) external {
        DisputeHelper.arbitratorResolve(pactid, pactData[pactid]);
    }
}
