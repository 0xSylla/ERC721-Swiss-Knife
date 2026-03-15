// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMintStageRegistry
 * @notice Interface for the MintStageRegistry contract.
 * @dev Single-collection registry — one registry is permanently bound to one
 *      NFT contract via `bindCollection`. All address collection parameters
 *      from the multi-collection version have been removed.
 */
interface IMintStageRegistry {

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct MintStage {
        string  name;
        uint256 price;
        uint256 maxSupply;
        uint256 maxPerWallet;
        uint256 minted;
        bool    isActive;
        bool    requiresAllowlist;
        bool    isGTD;       // true = GTD, no oversubscription; false = FCFS, 120% allowed
        uint256 startTime;   // 0 = no restriction
        uint256 endTime;     // 0 = no restriction
    }

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted once when the registry is permanently bound to a collection.
    event CollectionBound(address indexed collection);

    event StageCreated(address indexed collection, uint256 indexed stageId, string name);
    event StageUpdated(address indexed collection, uint256 indexed stageId);
    event StageStatusChanged(address indexed collection, uint256 indexed stageId, bool isActive);
    event AllowlistUpdated(address indexed collection, uint256 indexed stageId, uint256 totalCount);
    event MintRecorded(address indexed collection, uint256 indexed stageId, address indexed user, uint256 amount);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error Unauthorized();
    error CollectionAlreadyBound(address existing);
    error CollectionNotBound();
    error InvalidCollection();
    error StageDoesNotExist(uint256 stageId);
    error StageInactive(uint256 stageId);
    error StageNotStarted(uint256 stageId);
    error StageEnded(uint256 stageId);
    error ExceedsStageSupply(uint256 requested, uint256 available);
    error ExceedsMaxPerWallet(uint256 requested, uint256 allowed);
    error NotInAllowlist(address caller, uint256 stageId);
    error StageDoesNotRequireAllowlist(uint256 stageId);
    error GTDAllowlistExceedsSupply();
    error FCFSAllowlistExceedsMax();
    error InvalidStageConfig(string reason);

    /// @notice Reverts when adding or updating a stage would cause the sum of
    ///         all stage maxSupplies to exceed the bound collection's i_maxSupply.
    error StagesTotalExceedsCollectionSupply(uint256 proposed, uint256 max);

    // ─── Binding ──────────────────────────────────────────────────────────────

    /**
     * @notice Permanently bind this registry to a single collection address.
     * @dev Owner-only. Can only be called once — reverts with
     *      `CollectionAlreadyBound` on any subsequent call.
     */
    function bindCollection(address collection) external;

    /// @notice Returns the bound collection address (zero if not yet bound).
    function boundCollection() external view returns (address);

    // ─── Stage Management ─────────────────────────────────────────────────────

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
    ) external returns (uint256 stageId);

    function updateStage(
        uint256 stageId,
        string calldata name,
        uint256 price,
        uint256 maxSupply,
        uint256 maxPerWallet,
        bool requiresAllowlist,
        uint256 startTime,
        uint256 endTime
    ) external;

    function setStageStatus(uint256 stageId, bool isActive) external;

    // ─── Allowlist Management ─────────────────────────────────────────────────

    function batchAddToAllowlist(uint256 stageId, address[] calldata addresses) external;
    function batchRemoveFromAllowlist(uint256 stageId, address[] calldata addresses) external;

    // ─── Mint Enforcement ─────────────────────────────────────────────────────

    /**
     * @notice Validates all mint conditions and records the mint atomically.
     * @dev Only callable by the bound collection contract.
     *      Reverts with a specific error if any condition fails.
     * @return totalCost Total ETH required for this mint (price * amount).
     */
    function validateAndRecordMint(
        uint256 stageId,
        address user,
        uint256 amount
    ) external returns (uint256 totalCost);

    // ─── View Functions ───────────────────────────────────────────────────────

    function getStage(uint256 stageId) external view returns (MintStage memory);
    function getNextStageId() external view returns (uint256);
    function getTotalStageMaxSupply() external view returns (uint256);

    /**
     * @notice Returns how many tokens are still available to allocate to new stages.
     * @dev Reads i_maxSupply live from the bound collection. Returns 0 if fully allocated.
     *      Reverts with `CollectionNotBound` if called before `bindCollection`.
     */
    function getRemainingAllocatable() external view returns (uint256);

    function getUserMintAllowance(
        uint256 stageId,
        address user
    ) external view returns (
        uint256 maxAllowed,
        uint256 alreadyMinted,
        uint256 canStillMint,
        bool isAllowlisted
    );

    function canUserMint(
        uint256 stageId,
        address user,
        uint256 amount
    ) external view returns (bool eligible, string memory reason);

    function getActiveStages() external view returns (uint256[] memory activeStageIds);

    function getAllStages() external view returns (
        uint256[] memory stageIds,
        string[] memory names,
        uint256[] memory prices,
        uint256[] memory maxSupplies,
        uint256[] memory mintedAmounts,
        bool[] memory activeStatuses
    );

    function getTotalRevenue() external view returns (uint256);

    function getRevenueByStage(uint256 stageId) external view returns (
        uint256 revenueGenerated,
        uint256 potentialRevenue
    );

    function getUserMintHistory(address user) external view returns (
        uint256[] memory stageIds,
        uint256[] memory amountsMinted,
        uint256 totalMintedByUser
    );

    function isAllowlisted(uint256 stageId, address user) external view returns (bool);
    function getAllowlistCount(uint256 stageId) external view returns (uint256);
}
