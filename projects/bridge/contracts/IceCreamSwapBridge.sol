// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./utils/AccessControl.sol";
import "./utils/Pausable.sol";
import "./utils/SafeCast.sol";
import "./interfaces/IDepositExecute.sol";
import "./interfaces/IERCHandler.sol";
import "./interfaces/IGenericHandler.sol";

/**
    @title Facilitates deposits, creation and voting of deposit proposals, and deposit executions.
    @author ChainSafe Systems.
 */
contract IceCreamSwapBridge is Pausable, AccessControl {
    using SafeCast for *;

    // Limit relayers number because proposal can fit only so much votes
    uint256 public constant MAX_RELAYERS = 200;

    uint8 public immutable _domainID;
    uint8 public _relayerThreshold;
    uint40 public _expiry;

    enum ProposalStatus {
        Inactive,
        Active,
        Passed,
        Executed,
        Cancelled
    }

    struct Proposal {
        ProposalStatus _status;
        uint200 _yesVotes; // bitmap, 200 maximum votes
        uint8 _yesVotesTotal;
        uint40 _proposedBlock; // 1099511627775 maximum block
    }

    // destinationDomainID => number of deposits
    mapping(uint8 => uint64) public _depositCounts;
    // resourceID => handler address
    mapping(bytes32 => address) public _resourceIDToHandlerAddress;
    // forwarder address => is Valid
    mapping(address => bool) public isValidForwarder;
    // destinationDomainID + depositNonce => dataHash => Proposal
    mapping(uint72 => mapping(bytes32 => Proposal)) private _proposals;

    // default fee in native tokens to do a bridging
    uint256 public _bridgeFee;
    // destinationDomainID => fee multiplier. 1_000 = 1x, defaults to 1x
    mapping(uint8 => uint256) public chainFeeMultipliers;
    // resourceID => fee multiplier. 1_000 = 1x, defaults to 1x
    mapping(bytes32 => uint256) public resourceFeeMultipliers;

    event RelayerThresholdChanged(uint256 newThreshold);
    event Deposit(
        uint8 destinationDomainID,
        bytes32 resourceID,
        uint64 depositNonce,
        address indexed user,
        bytes data,
        bytes handlerResponse
    );
    event ProposalEvent(uint8 originDomainID, uint64 depositNonce, ProposalStatus status, bytes32 dataHash);
    event ProposalVote(uint8 originDomainID, uint64 depositNonce, ProposalStatus status, bytes32 dataHash);
    event FailedHandlerExecution(bytes lowLevelData);

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyRelayers() {
        _onlyRelayers();
        _;
    }

    modifier onlyAdminOrRelayer() {
        _onlyAdminOrRelayer();
        _;
    }

    modifier onlyAdminRelayerOrExecutor() {
        _onlyAdminRelayerOrExecutor();
        _;
    }

    function _onlyAdmin() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "!admin");
    }

    function _onlyRelayers() private view {
        require(hasRole(RELAYER_ROLE, _msgSender()), "!relayer");
    }

    function _onlyAdminOrRelayer() private view {
        address sender = _msgSender();
        require(hasRole(DEFAULT_ADMIN_ROLE, sender) || hasRole(RELAYER_ROLE, sender), "!admin|relayer");
    }

    function _onlyAdminRelayerOrExecutor() private view {
        address sender = _msgSender();
        require(
            hasRole(DEFAULT_ADMIN_ROLE, sender) || hasRole(RELAYER_ROLE, sender) || hasRole(EXECUTOR_ROLE, sender),
            "!admin|relayer|executor"
        );
    }

    function _relayerBit(address relayer) private view returns (uint256) {
        uint256 relayerIdx = AccessControl.getRoleMemberIndex(RELAYER_ROLE, relayer);
        require(relayerIdx <= MAX_RELAYERS, ">MAX_RELAYERS");
        return uint256(1) << (relayerIdx - 1);
    }

    function _hasVoted(Proposal memory proposal, address relayer) private view returns (bool) {
        return (_relayerBit(relayer) & uint256(proposal._yesVotes)) > 0;
    }

    function _msgSender() internal view override returns (address) {
        address signer = msg.sender;
        if (msg.data.length >= 20 && isValidForwarder[signer]) {
            assembly {
                signer := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        }
        return signer;
    }

    /**
        @notice Initializes Bridge, creates and grants {_msgSender()} the admin role,
        creates and grants {initialRelayers} the relayer role.
        @param domainID ID of chain the Bridge contract exists on.
        @param initialRelayers Addresses that should be initially granted the relayer role.
        @param initialRelayerThreshold Number of votes needed for a deposit proposal to be considered passed.
     */
    constructor(
        uint8 domainID,
        address[] memory initialRelayers,
        uint256 initialRelayerThreshold,
        uint256 expiry,
        uint256 bridgeFee
    ) {
        require(domainID != 0 && initialRelayerThreshold != 0);
        _domainID = domainID;
        _relayerThreshold = initialRelayerThreshold.toUint8();
        _expiry = expiry.toUint40();
        _bridgeFee = bridgeFee;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        for (uint256 i; i < initialRelayers.length; i++) {
            grantRole(RELAYER_ROLE, initialRelayers[i]);
        }
    }

    receive() external payable {}

    /**
        @notice Returns true if {relayer} has voted on {destNonce} {dataHash} proposal.
        @notice Naming left unchanged for backward compatibility.
        @param destNonce destinationDomainID + depositNonce of the proposal.
        @param dataHash Hash of data to be provided when deposit proposal is executed.
        @param relayer Address to check.
     */
    function _hasVotedOnProposal(uint72 destNonce, bytes32 dataHash, address relayer) external view returns (bool) {
        return _hasVoted(_proposals[destNonce][dataHash], relayer);
    }

    /**
        @notice Returns true if {relayer} has the relayer role.
        @param relayer Address to check.
     */
    function isRelayer(address relayer) external view returns (bool) {
        return hasRole(RELAYER_ROLE, relayer);
    }

    /**
        @notice Removes admin role from {_msgSender()} and grants it to {newAdmin}.
        @notice Only callable by an address that currently has the admin role.
        @param newAdmin Address that admin role will be granted to.
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        address sender = _msgSender();
        require(sender != newAdmin);
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        renounceRole(DEFAULT_ADMIN_ROLE, sender);
    }

    /**
        @notice Pauses deposits, proposal creation and voting, and deposit executions.
        @notice Only callable by an address that currently has the admin role.
     */
    function adminPauseTransfers() external onlyAdmin {
        _pause(_msgSender());
    }

    /**
        @notice Unpauses deposits, proposal creation and voting, and deposit executions.
        @notice Only callable by an address that currently has the admin role.
     */
    function adminUnpauseTransfers() external onlyAdmin {
        _unpause(_msgSender());
    }

    /**
        @notice Modifies the number of votes required for a proposal to be considered passed.
        @notice Only callable by an address that currently has the admin role.
        @param newThreshold Value {_relayerThreshold} will be changed to.
        @notice Emits {RelayerThresholdChanged} event.
     */
    function adminChangeRelayerThreshold(uint256 newThreshold) external onlyAdmin {
        require(newThreshold != 0);
        _relayerThreshold = newThreshold.toUint8();
        emit RelayerThresholdChanged(newThreshold);
    }

    /**
        @notice Sets a new resource for handler contracts that use the IERCHandler interface,
        and maps the {handlerAddress} to {resourceID} in {_resourceIDToHandlerAddress}.
        @notice Only callable by an address that currently has the admin role.
        @param handlerAddress Address of handler resource will be set for.
        @param resourceID ResourceID to be used when making deposits.
        @param tokenAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
    function adminSetResource(address handlerAddress, bytes32 resourceID, address tokenAddress) external onlyAdmin {
        require(handlerAddress != address(0) && resourceID != bytes32(0) && tokenAddress != address(0));
        _resourceIDToHandlerAddress[resourceID] = handlerAddress;
        IERCHandler(handlerAddress).setResource(resourceID, tokenAddress);
    }

    /**
        @notice Sets a new resource for handler contracts that use the IGenericHandler interface,
        and maps the {handlerAddress} to {resourceID} in {_resourceIDToHandlerAddress}.
        @notice Only callable by an address that currently has the admin role.
        @param handlerAddress Address of handler resource will be set for.
        @param resourceID ResourceID to be used when making deposits.
        @param contractAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
    function adminSetGenericResource(
        address handlerAddress,
        bytes32 resourceID,
        address contractAddress,
        bytes4 depositFunctionSig,
        uint256 depositFunctionDepositerOffset,
        bytes4 executeFunctionSig
    ) external onlyAdmin {
        require(handlerAddress != address(0) && resourceID != bytes32(0) && contractAddress != address(0));
        _resourceIDToHandlerAddress[resourceID] = handlerAddress;
        IGenericHandler(handlerAddress).setResource(
            resourceID,
            contractAddress,
            depositFunctionSig,
            depositFunctionDepositerOffset,
            executeFunctionSig
        );
    }

    /**
        @notice Removes a resource for Bridge and handler contract
        @notice Only callable by an address that currently has the admin role.
        @param resourceID ResourceID to be used when making deposits.
     */
    function adminRemoveResource(bytes32 resourceID) external onlyAdmin {
        address handlerAddress = _resourceIDToHandlerAddress[resourceID];
        require(handlerAddress != address(0), "invalid resourceID");
        _resourceIDToHandlerAddress[resourceID] = address(0);
        IERCHandler(handlerAddress).removeResource(resourceID);
    }

    /**
        @notice Sets the nonce for the specific domainID.
        @notice Only callable by an address that currently has the admin role.
        @param domainID Domain ID for increasing nonce.
        @param nonce The nonce value to be set.
     */
    function adminSetDepositNonce(uint8 domainID, uint64 nonce) external onlyAdmin {
        require(nonce > _depositCounts[domainID], "no decrements");
        _depositCounts[domainID] = nonce;
    }

    /**
        @notice Set a forwarder to be used.
        @notice Only callable by an address that currently has the admin role.
        @param forwarder Forwarder address to be added.
        @param valid Decision for the specific forwarder.
     */
    function adminSetForwarder(address forwarder, bool valid) external onlyAdmin {
        isValidForwarder[forwarder] = valid;
    }

    /**
        @notice Returns a proposal.
        @param originDomainID Chain ID deposit originated from.
        @param depositNonce ID of proposal generated by proposal's origin Bridge contract.
        @param dataHash Hash of data to be provided when deposit proposal is executed.
        @return Proposal which consists of:
        - _dataHash Hash of data to be provided when deposit proposal is executed.
        - _yesVotes Number of votes in favor of proposal.
        - _noVotes Number of votes against proposal.
        - _status Current status of proposal.
     */
    function getProposal(
        uint8 originDomainID,
        uint64 depositNonce,
        bytes32 dataHash
    ) external view returns (Proposal memory) {
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(originDomainID);
        return _proposals[nonceAndID][dataHash];
    }

    /**
        @notice Returns total relayers number.
     */
    function _totalRelayers() public view returns (uint256) {
        return AccessControl.getRoleMemberCount(RELAYER_ROLE);
    }

    /**
        @notice Initiates a transfer using a specified handler contract.
        @notice Only callable when Bridge is not paused.
        @param destinationDomainID ID of chain deposit will be bridged to.
        @param resourceID ResourceID used to find address of handler to be used for deposit.
        @param data Additional data to be passed to specified handler.
        @notice Emits {Deposit} event with all necessary parameters and a handler response.
        - ERC20Handler: responds with an empty data or new amount after fees.
        - ERC721Handler: responds with the deposited token metadata acquired by calling a tokenURI method in the token contract.
        - GenericHandler: responds with the raw bytes returned from the call to the target contract.
     */
    function deposit(
        uint8 destinationDomainID,
        bytes32 resourceID,
        bytes calldata data
    ) external payable whenNotPaused {
        address handler = _resourceIDToHandlerAddress[resourceID];
        require(handler != address(0), "invalid resourceID");

        uint256 bridgeFee = calculateBridgeFee(destinationDomainID, resourceID, data);
        require(msg.value >= bridgeFee, "Insufficient native fee");

        uint64 depositNonce = ++_depositCounts[destinationDomainID];
        address sender = _msgSender();

        IDepositExecute depositHandler = IDepositExecute(handler);
        bytes memory handlerResponse = depositHandler.deposit{value: msg.value - bridgeFee}(
            resourceID,
            sender,
            destinationDomainID,
            data
        );

        emit Deposit(destinationDomainID, resourceID, depositNonce, sender, data, handlerResponse);
    }

    /**
        @notice When called, {_msgSender()} will be marked as voting in favor of proposal.
        @notice Only callable by relayers when Bridge is not paused.
        @param domainID ID of chain deposit originated from.
        @param depositNonce ID of deposited generated by origin Bridge contract.
        @param data Data originally provided when deposit was made.
        @notice Proposal must not have already been passed or executed.
        @notice {_msgSender()} must not have already voted on proposal.
        @notice Emits {ProposalEvent} event with status indicating the proposal status.
        @notice Emits {ProposalVote} event.
     */
    function voteProposal(
        uint8 domainID,
        uint64 depositNonce,
        bytes32 resourceID,
        bytes calldata data
    ) external onlyRelayers whenNotPaused {
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(domainID);
        bytes32 dataHash = keccak256(abi.encodePacked(resourceID, data));
        Proposal memory proposal = _proposals[nonceAndID][dataHash];

        require(_resourceIDToHandlerAddress[resourceID] != address(0), "no handler for resourceID");

        if (proposal._status == ProposalStatus.Passed) {
            executeProposal(domainID, depositNonce, data, resourceID, true);
            return;
        }

        address sender = _msgSender();

        require(uint256(proposal._status) <= 1, "proposal completed");
        require(!_hasVoted(proposal, sender), "already voted");

        if (proposal._status == ProposalStatus.Inactive) {
            proposal = Proposal({
                _status: ProposalStatus.Active,
                _yesVotes: 0,
                _yesVotesTotal: 0,
                _proposedBlock: uint40(block.number) // Overflow is desired.
            });

            emit ProposalEvent(domainID, depositNonce, ProposalStatus.Active, dataHash);
        } else if (uint40(block.number - proposal._proposedBlock) > _expiry) {
            // if the number of blocks that has passed since this proposal was
            // submitted exceeds the expiry threshold set, cancel the proposal
            proposal._status = ProposalStatus.Cancelled;

            emit ProposalEvent(domainID, depositNonce, ProposalStatus.Cancelled, dataHash);
        }

        if (proposal._status != ProposalStatus.Cancelled) {
            proposal._yesVotes = (proposal._yesVotes | _relayerBit(sender)).toUint200();
            proposal._yesVotesTotal++;

            emit ProposalVote(domainID, depositNonce, proposal._status, dataHash);

            // Finalize if _relayerThreshold has been reached
            if (proposal._yesVotesTotal >= _relayerThreshold) {
                proposal._status = ProposalStatus.Passed;
                emit ProposalEvent(domainID, depositNonce, ProposalStatus.Passed, dataHash);
            }
        }
        _proposals[nonceAndID][dataHash] = proposal;

        if (proposal._status == ProposalStatus.Passed) {
            executeProposal(domainID, depositNonce, data, resourceID, false);
        }
    }

    /**
        @notice Cancels a deposit proposal that has not been executed yet.
        @notice Only callable by relayers when Bridge is not paused.
        @param domainID ID of chain deposit originated from.
        @param depositNonce ID of deposited generated by origin Bridge contract.
        @param dataHash Hash of data originally provided when deposit was made.
        @notice Proposal must be past expiry threshold.
        @notice Emits {ProposalEvent} event with status {Cancelled}.
     */
    function cancelProposal(uint8 domainID, uint64 depositNonce, bytes32 dataHash) external onlyAdminOrRelayer {
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(domainID);
        Proposal memory proposal = _proposals[nonceAndID][dataHash];
        ProposalStatus currentStatus = proposal._status;

        require(
            currentStatus == ProposalStatus.Active || currentStatus == ProposalStatus.Passed,
            "cannot be cancelled"
        );
        require(uint40(block.number - proposal._proposedBlock) > _expiry, "not expired");

        proposal._status = ProposalStatus.Cancelled;
        _proposals[nonceAndID][dataHash] = proposal;

        emit ProposalEvent(domainID, depositNonce, ProposalStatus.Cancelled, dataHash);
    }

    /**
        @notice Executes a deposit proposal that is considered passed using a specified handler contract.
        @notice Only callable by relayers when Bridge is not paused.
        @param domainID ID of chain deposit originated from.
        @param resourceID ResourceID to be used when making deposits.
        @param depositNonce ID of deposited generated by origin Bridge contract.
        @param data Data originally provided when deposit was made.
        @param revertOnFail Decision if the transaction should be reverted in case of handler's executeProposal is reverted or not.
        @notice Proposal must have Passed status.
        @notice Hash of {data} must equal proposal's {dataHash}.
        @notice Emits {ProposalEvent} event with status {Executed}.
        @notice Emits {FailedExecution} event with the failed reason.
     */
    function executeProposal(
        uint8 domainID,
        uint64 depositNonce,
        bytes calldata data,
        bytes32 resourceID,
        bool revertOnFail
    ) public onlyAdminRelayerOrExecutor whenNotPaused {
        address handler = _resourceIDToHandlerAddress[resourceID];
        require(handler != address(0), "invalid resourceID");
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(domainID);
        bytes32 dataHash = keccak256(abi.encodePacked(resourceID, data));
        Proposal storage proposal = _proposals[nonceAndID][dataHash];

        require(proposal._status == ProposalStatus.Passed, "!passed");

        proposal._status = ProposalStatus.Executed;
        IDepositExecute depositHandler = IDepositExecute(handler);

        if (revertOnFail) {
            depositHandler.executeProposal(resourceID, data);
        } else {
            try depositHandler.executeProposal(resourceID, data) {} catch (bytes memory lowLevelData) {
                proposal._status = ProposalStatus.Passed;
                emit FailedHandlerExecution(lowLevelData);
                return;
            }
        }

        emit ProposalEvent(domainID, depositNonce, ProposalStatus.Executed, dataHash);
    }

    /**
        @notice Calculates the Handler fees for a deposit with the same arguments.
        @param destinationDomainID ID of chain deposit will be bridged to.
        @param resourceID ResourceID used to find address of handler to be used for deposit.
        @param data Additional data to be passed to specified handler.
     */
    function calculateHandlerFee(
        uint8 destinationDomainID,
        bytes32 resourceID,
        bytes calldata data
    ) external view returns (address feeToken, uint256 fee) {
        address handler = _resourceIDToHandlerAddress[resourceID];
        require(handler != address(0), "invalid resourceID");

        address sender = _msgSender();

        IERCHandler depositHandler = IERCHandler(handler);
        (feeToken, fee) = depositHandler.calculateFee(resourceID, sender, destinationDomainID, data);
    }

    /**
        @notice Calculates the Bridge fees for a deposit with the same arguments.
        @param destinationDomainID ID of chain deposit will be bridged to.
        @param resourceID ResourceID used to find address of handler to be used for deposit.
        @notice parameter data not used, but Additional data to be passed to specified handler.
     */
    function calculateBridgeFee(
        uint8 destinationDomainID,
        bytes32 resourceID,
        bytes calldata // data
    ) public view returns (uint256 fee) {
        fee = _bridgeFee;
        if (chainFeeMultipliers[destinationDomainID] != 0) {
            fee = (fee * chainFeeMultipliers[destinationDomainID]) / 1_000;
        }
        if (resourceFeeMultipliers[resourceID] != 0) {
            fee = (fee * resourceFeeMultipliers[resourceID]) / 1_000;
        }
    }

    /**
        @notice Sets the fixed Bridge fee
        @param bridgeFee fee amount in wei of native token
     */
    function setBridgeFee(uint256 bridgeFee) external onlyAdmin {
        _bridgeFee = bridgeFee;
    }

    /**
        @notice add a fee multiplier for a chain.
        @param domainId domain ID of the chain to set the multiplier for
        @param feeMultiplier multiplier for this chain, 1_000 = 1x and 0 defaults to 1x
     */
    function setFeeMultiplierChain(uint8 domainId, uint256 feeMultiplier) external onlyAdmin {
        chainFeeMultipliers[domainId] = feeMultiplier;
    }

    /**
        @notice add a fee multiplier for a resource.
        @param resourceId resource ID of the token or other resource to set the multiplier for
        @param feeMultiplier multiplier for this resource, 1_000 = 1x and 0 defaults to 1x
     */
    function setFeeMultiplierResource(bytes32 resourceId, uint256 feeMultiplier) external onlyAdmin {
        resourceFeeMultipliers[resourceId] = feeMultiplier;
    }

    /**
        @notice Sets the proposal expiry. After a given time proposals with not enough votes or reverted executions
        won't be able to be executed anymore.
        @param expiry time in seconds till a proposal expires after it was first submitted.
     */
    function setExpiry(uint40 expiry) external onlyAdmin {
        _expiry = expiry;
    }

    /**
        @notice allows the admin to withdraw accumulated fees and tokens sent to this contract.
        @param tokenAddress address of the token to withdraw
        @param recipient recipient which should receive the withdrawn token
        @param amount how many tokens should be withdrawn
     */
    function withdraw(address tokenAddress, address recipient, uint256 amount) external onlyAdmin {
        if (tokenAddress == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(tokenAddress).transfer(recipient, amount);
        }
    }
}
