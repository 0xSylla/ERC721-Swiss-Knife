// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Interface/IMintStageRegistry.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MintStageRegistry
 * @notice Standalone contract that owns all mint stage definitions, allowlists,
 *         quota tracking, and validation logic.
 *
 * @dev Architecture:
 *   - This contract is STATEFUL for stage/allowlist data only.
 *   - It does NOT hold ETH or tokens.
 *   - Bound to exactly ONE collection address, set once, immutable thereafter.
 *
 * Trust model:
 *   - Registry owner  : can call `bindCollection` only. No stage control.
 *   - Collection owner: can manage stages, allowlists, and stage status.
 *                       Verified by calling `owner()` on the bound collection.
 *   - Bound collection: can call `validateAndRecordMint` (the NFT contract itself).
 *   - Anyone          : can read all view functions.
 *
 * Supply invariant:
 *   - `_totalStageMaxSupply` must never exceed the bound collection's `i_maxSupply`.
 *   - Enforced on every `addStage` and `updateStage` by reading `i_maxSupply`
 *     directly from the bound collection contract via `ICollection`.
 *
 * Reentrancy:
 *   - `onlyCollectionOwner` makes an external call to `boundCollection.owner()`.
 *   - `_enforceSupplyCap` makes an external call to `boundCollection.i_maxSupply()`.
 *   - All state-mutating functions are guarded with `nonReentrant`.
 */
contract MintStageRegistry is IMintStageRegistry, Ownable2Step, ReentrancyGuard {

    // ─── Storage ─────────────────────────────────────────────────────────────

    /// @notice The one and only collection this registry serves.
    ///         Set once via `bindCollection`, never changeable.
    address public boundCollection;

    /// @dev stageId counter
    uint256 private _nextStageId;

    /// @dev stageId => MintStage
    mapping(uint256 => MintStage) private _stages;

    /// @dev Running sum of all stage maxSupplies. Must always be <= collection's i_maxSupply.
    uint256 private _totalStageMaxSupply;

    /// @dev stageId => user => minted amount
    mapping(uint256 => mapping(address => uint256)) private _stageMints;

    /// @dev stageId => user => allowlisted
    mapping(uint256 => mapping(address => bool)) private _allowlist;

    /// @dev stageId => total allowlisted count
    mapping(uint256 => uint256) private _allowlistCount;

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address owner) Ownable(owner) {}

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier whenBound() {
        if (boundCollection == address(0)) revert CollectionNotBound();
        _;
    }

    modifier onlyBoundCollection() {
        if (boundCollection == address(0)) revert CollectionNotBound();
        if (msg.sender != boundCollection) revert Unauthorized();
        _;
    }

    /**
     * @dev Reads `owner()` from the bound collection at call time.
     *      All functions using this modifier must also use `nonReentrant`.
     */
    modifier onlyCollectionOwner() {
        if (boundCollection == address(0)) revert CollectionNotBound();
        if (msg.sender != ICollection(boundCollection).owner()) revert Unauthorized();
        _;
    }

    // ─── Collection Binding ───────────────────────────────────────────────────

    function bindCollection(address collection) external onlyOwner {
        if (boundCollection != address(0)) revert CollectionAlreadyBound(boundCollection);
        if (collection == address(0))      revert InvalidCollection();

        boundCollection = collection;
        emit CollectionBound(collection);
    }

    // ─── Stage Management ─────────────────────────────────────────────────────

    /// @inheritdoc IMintStageRegistry
    function addStage(
        string calldata name,
        uint256 price,
        uint256 maxSupply,
        uint256 maxPerWallet,
        bool requiresAllowlist,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isGTD
    ) external onlyCollectionOwner nonReentrant returns (uint256 stageId) {
        _validateStageConfig(maxSupply, maxPerWallet, startTime, endTime);

        // Guard: new total must not exceed collection's hard cap
        _enforceSupplyCap(_totalStageMaxSupply + maxSupply);

        stageId = _nextStageId;

        _stages[stageId] = MintStage({
            name: name,
            price: price,
            maxSupply: maxSupply,
            maxPerWallet: maxPerWallet,
            minted: 0,
            isActive: isActive,
            requiresAllowlist: requiresAllowlist,
            isGTD: isGTD,
            startTime: startTime,
            endTime: endTime
        });

        _totalStageMaxSupply += maxSupply;
        _nextStageId++;

        emit StageCreated(boundCollection, stageId, name);
    }

    /// @inheritdoc IMintStageRegistry
    function updateStage(
        uint256 stageId,
        string calldata name,
        uint256 price,
        uint256 maxSupply,
        uint256 maxPerWallet,
        bool requiresAllowlist,
        uint256 startTime,
        uint256 endTime
    ) external onlyCollectionOwner nonReentrant {
        _requireStageExists(stageId);
        _validateStageConfig(maxSupply, maxPerWallet, startTime, endTime);

        MintStage storage stage = _stages[stageId];

        if (maxSupply < stage.minted) {
            revert InvalidStageConfig("New max supply less than already minted");
        }

        // Guard: compute what the new total would be after swapping old for new
        uint256 newTotal = _totalStageMaxSupply - stage.maxSupply + maxSupply;
        _enforceSupplyCap(newTotal);

        _totalStageMaxSupply = newTotal;

        stage.name              = name;
        stage.price             = price;
        stage.maxSupply         = maxSupply;
        stage.maxPerWallet      = maxPerWallet;
        stage.requiresAllowlist = requiresAllowlist;
        stage.startTime         = startTime;
        stage.endTime           = endTime;

        emit StageUpdated(boundCollection, stageId);
    }

    /// @inheritdoc IMintStageRegistry
    function setStageStatus(uint256 stageId, bool isActive) external onlyCollectionOwner nonReentrant {
        _requireStageExists(stageId);
        _stages[stageId].isActive = isActive;
        emit StageStatusChanged(boundCollection, stageId, isActive);
    }

    // ─── Allowlist Management ─────────────────────────────────────────────────

    /// @inheritdoc IMintStageRegistry
    function batchAddToAllowlist(
        uint256 stageId,
        address[] calldata addresses
    ) external onlyCollectionOwner nonReentrant {
        _requireStageExists(stageId);

        MintStage storage stage = _stages[stageId];
        if (!stage.requiresAllowlist) revert StageDoesNotRequireAllowlist(stageId);

        uint256 newCount = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!_allowlist[stageId][addresses[i]]) newCount++;
        }

        uint256 newTotal = _allowlistCount[stageId] + newCount;

        if (stage.isGTD) {
            if (newTotal > stage.maxSupply) revert GTDAllowlistExceedsSupply();
        } else {
            uint256 maxAllowed = (stage.maxSupply * 120) / 100;
            if (newTotal > maxAllowed) revert FCFSAllowlistExceedsMax();
        }

        for (uint256 i = 0; i < addresses.length; i++) {
            if (!_allowlist[stageId][addresses[i]]) {
                _allowlist[stageId][addresses[i]] = true;
                _allowlistCount[stageId]++;
            }
        }

        emit AllowlistUpdated(boundCollection, stageId, _allowlistCount[stageId]);
    }

    /// @inheritdoc IMintStageRegistry
    function batchRemoveFromAllowlist(
        uint256 stageId,
        address[] calldata addresses
    ) external onlyCollectionOwner nonReentrant {
        _requireStageExists(stageId);

        MintStage storage stage = _stages[stageId];
        if (!stage.requiresAllowlist) revert StageDoesNotRequireAllowlist(stageId);

        for (uint256 i = 0; i < addresses.length; i++) {
            if (_allowlist[stageId][addresses[i]]) {
                _allowlist[stageId][addresses[i]] = false;
                _allowlistCount[stageId]--;
            }
        }

        emit AllowlistUpdated(boundCollection, stageId, _allowlistCount[stageId]);
    }

    // ─── Mint Validation & Recording ──────────────────────────────────────────

    /// @inheritdoc IMintStageRegistry
    function validateAndRecordMint(
        uint256 stageId,
        address user,
        uint256 amount
    ) external onlyBoundCollection nonReentrant returns (uint256 totalCost) {
        _requireStageExists(stageId);

        MintStage storage stage = _stages[stageId];

        if (!stage.isActive) revert StageInactive(stageId);

        if (stage.startTime > 0 && block.timestamp < stage.startTime) revert StageNotStarted(stageId);
        if (stage.endTime   > 0 && block.timestamp > stage.endTime)   revert StageEnded(stageId);

        uint256 remaining = stage.maxSupply - stage.minted;
        if (amount > remaining) revert ExceedsStageSupply(amount, remaining);

        if (stage.requiresAllowlist && !_allowlist[stageId][user]) {
            revert NotInAllowlist(user, stageId);
        }

        uint256 userMinted = _stageMints[stageId][user];
        if (userMinted + amount > stage.maxPerWallet) {
            revert ExceedsMaxPerWallet(userMinted + amount, stage.maxPerWallet);
        }

        stage.minted               += amount;
        _stageMints[stageId][user] += amount;
        totalCost                   = stage.price * amount;

        emit MintRecorded(boundCollection, stageId, user, amount);
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    function getStage(uint256 stageId) external view returns (MintStage memory) {
        _requireStageExists(stageId);
        return _stages[stageId];
    }

    function getNextStageId() external view returns (uint256) {
        return _nextStageId;
    }

    function getTotalStageMaxSupply() external view returns (uint256) {
        return _totalStageMaxSupply;
    }

    /**
     * @notice Returns how many tokens are still available to be allocated to new stages.
     * @dev Reads i_maxSupply live from the collection. Returns 0 if fully allocated.
     */
    function getRemainingAllocatable() external view whenBound returns (uint256) {
        uint256 collectionMax = ICollection(boundCollection).i_maxSupply();
        return collectionMax > _totalStageMaxSupply
            ? collectionMax - _totalStageMaxSupply
            : 0;
    }

    function getUserMintAllowance(
        uint256 stageId,
        address user
    ) external view returns (
        uint256 maxAllowed,
        uint256 alreadyMinted,
        uint256 canStillMint,
        bool isAllowlisted_
    ) {
        _requireStageExists(stageId);
        MintStage storage stage = _stages[stageId];

        maxAllowed     = stage.maxPerWallet;
        alreadyMinted  = _stageMints[stageId][user];
        canStillMint   = maxAllowed > alreadyMinted ? maxAllowed - alreadyMinted : 0;
        isAllowlisted_ = stage.requiresAllowlist ? _allowlist[stageId][user] : true;
    }

    function canUserMint(
        uint256 stageId,
        address user,
        uint256 amount
    ) external view returns (bool eligible, string memory reason) {
        if (stageId >= _nextStageId) return (false, "Stage does not exist");

        MintStage storage stage = _stages[stageId];

        if (!stage.isActive)                                           return (false, "Stage is not active");
        if (stage.startTime > 0 && block.timestamp < stage.startTime) return (false, "Stage has not started");
        if (stage.endTime   > 0 && block.timestamp > stage.endTime)   return (false, "Stage has ended");
        if (stage.minted + amount > stage.maxSupply)                   return (false, "Exceeds stage supply");
        if (stage.requiresAllowlist && !_allowlist[stageId][user])    return (false, "Not in allowlist");
        if (_stageMints[stageId][user] + amount > stage.maxPerWallet) return (false, "Exceeds max per wallet");

        return (true, "Eligible to mint");
    }

    function getActiveStages() external view returns (uint256[] memory activeStageIds) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _nextStageId; i++) {
            if (_stages[i].isActive) activeCount++;
        }
        activeStageIds = new uint256[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < _nextStageId; i++) {
            if (_stages[i].isActive) activeStageIds[idx++] = i;
        }
    }

    function getAllStages() external view returns (
        uint256[] memory stageIds,
        string[] memory names,
        uint256[] memory prices,
        uint256[] memory maxSupplies,
        uint256[] memory mintedAmounts,
        bool[] memory activeStatuses
    ) {
        uint256 count  = _nextStageId;
        stageIds       = new uint256[](count);
        names          = new string[](count);
        prices         = new uint256[](count);
        maxSupplies    = new uint256[](count);
        mintedAmounts  = new uint256[](count);
        activeStatuses = new bool[](count);

        for (uint256 i = 0; i < count; i++) {
            MintStage storage s = _stages[i];
            stageIds[i]       = i;
            names[i]          = s.name;
            prices[i]         = s.price;
            maxSupplies[i]    = s.maxSupply;
            mintedAmounts[i]  = s.minted;
            activeStatuses[i] = s.isActive;
        }
    }

    function getTotalRevenue() external view returns (uint256 totalRevenue) {
        for (uint256 i = 0; i < _nextStageId; i++) {
            totalRevenue += _stages[i].minted * _stages[i].price;
        }
    }

    function getRevenueByStage(uint256 stageId) external view returns (
        uint256 revenueGenerated,
        uint256 potentialRevenue
    ) {
        _requireStageExists(stageId);
        MintStage storage s = _stages[stageId];
        revenueGenerated = s.minted * s.price;
        potentialRevenue = s.maxSupply * s.price;
    }

    function getUserMintHistory(address user) external view returns (
        uint256[] memory stageIds,
        uint256[] memory amountsMinted,
        uint256 totalMintedByUser
    ) {
        stageIds      = new uint256[](_nextStageId);
        amountsMinted = new uint256[](_nextStageId);

        for (uint256 i = 0; i < _nextStageId; i++) {
            stageIds[i]       = i;
            amountsMinted[i]  = _stageMints[i][user];
            totalMintedByUser += amountsMinted[i];
        }
    }

    function isAllowlisted(uint256 stageId, address user) external view returns (bool) {
        return _allowlist[stageId][user];
    }

    function getAllowlistCount(uint256 stageId) external view returns (uint256) {
        return _allowlistCount[stageId];
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    function _requireStageExists(uint256 stageId) internal view {
        if (stageId >= _nextStageId) revert StageDoesNotExist(stageId);
    }

    function _validateStageConfig(
        uint256 maxSupply,
        uint256 maxPerWallet,
        uint256 startTime,
        uint256 endTime
    ) internal pure {
        if (maxSupply == 0)    revert InvalidStageConfig("Max supply cannot be zero");
        if (maxPerWallet == 0) revert InvalidStageConfig("Max per wallet cannot be zero");
        if (endTime != 0 && startTime != 0 && endTime <= startTime) {
            revert InvalidStageConfig("End time must be after start time");
        }
    }

    /**
     * @notice Reads `i_maxSupply` from the bound collection and reverts if
     *         `proposedTotal` would exceed it.
     * @dev Called inside `addStage` and `updateStage` after nonReentrant lock
     *      is already acquired, so the external call here is safe.
     * @param proposedTotal The new value of `_totalStageMaxSupply` after the change.
     */
    function _enforceSupplyCap(uint256 proposedTotal) internal view {
        uint256 collectionMax = ICollection(boundCollection).i_maxSupply();
        if (proposedTotal > collectionMax) {
            revert StagesTotalExceedsCollectionSupply(proposedTotal, collectionMax);
        }
    }
}

// ─── Minimal interfaces to read from the bound collection ─────────────────────

interface ICollection {
    function owner() external view returns (address);
    function i_maxSupply() external view returns (uint256);
}
