// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//Captcha + Backend signature + msg.sender binding (prevents mempool copy)
//IP/Wallet rate limit

import "@limitbreak/creator-token-standards/src/erc721c/ERC721AC.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "../Interface/IMintStageRegistry.sol";

library BaseNFTParams {
    struct InitParams {
        string collectionName;
        string collectionSymbol;
        address collectionOwner;
        uint256 collectionMaxSupply;
        string baseURI;
        address royaltyReceiver; // Address to receive royalties
        uint96 royaltyFeeBps; // Royalty in basis points (e.g., 500 = 5%)
        address mintStageRegistry;
    }
}

contract BaseNFT is OwnableBasic, ERC721AC, BasicRoyalties {
    error InvalidURI();
    error InvalidOperation(string reason);
    error ExceedsMaxSupply(uint256 requested, uint256 available);
    error InsufficientEther(uint256 required, uint256 provided);

    IMintStageRegistry public immutable i_registry;
    uint256 public immutable i_maxSupply;

    string public s_baseURI;
    uint256 public s_totalAirdropped;

    event BaseURIUpdated(string baseURI);
    event NFTsMinted(address indexed recipient, uint256 amount, uint256 stageId);
    event NFTsAirdropped(address[] recipients, uint256 amountPerRecipient, uint256 totalAmount);

    constructor(BaseNFTParams.InitParams memory _params)
        ERC721AC(_params.collectionName, _params.collectionSymbol)
        OwnableBasic(_params.collectionOwner)
        BasicRoyalties(_params.royaltyReceiver, _params.royaltyFeeBps)
    {
        i_registry = IMintStageRegistry(_params.mintStageRegistry);
        i_maxSupply = _params.collectionMaxSupply;
        s_baseURI = _params.baseURI;
    }

    //Mint

    /**
     * @notice Mint tokens through an active stage.
     * @dev Payment validation happens here (this contract holds ETH).
     *      All stage logic (active check, time, supply, allowlist, quota)
     *      is delegated atomically to the registry.
     * @param stageId  The stage to mint through
     * @param amount   Number of tokens to mint
     */
    function batchMint(uint256 stageId, uint256 amount) external payable virtual {
        _executeMint(stageId, amount);
    }

    /**
     * @dev Internal mint logic: supply check, registry validation, payment, refund.
     *      Extracted so derived contracts can add pre-checks (e.g. signature
     *      verification) and then call this to execute the actual mint.
     */
    function _executeMint(uint256 stageId, uint256 amount) internal {
        // 1. Global supply check (registry tracks stage supply separately)
        if (_totalMinted() + amount > i_maxSupply) {
            revert ExceedsMaxSupply(amount, i_maxSupply - _totalMinted());
        }

        // 2. Delegate all stage checks + record to registry (reverts on any failure)
        uint256 totalCost = i_registry.validateAndRecordMint(stageId, msg.sender, amount);

        // 3. Payment check
        if (msg.value < totalCost) {
            revert InsufficientEther(totalCost, msg.value);
        }

        // 4. Mint
        _mint(msg.sender, amount);

        // 5. Refund excess
        unchecked {
            uint256 excess = msg.value - totalCost;
            if (excess > 0) {
                (bool ok,) = msg.sender.call{value: excess}("");
                require(ok, "Refund failed");
            }
        }

        emit NFTsMinted(msg.sender, amount, stageId);
    }

    /**
     * @notice Owner-only batch airdrop. Respects stage-reserved supply.
     * @param to     Array of recipient addresses
     * @param amount Number of tokens each recipient receives
     */
    function batchAirdrop(address[] calldata to, uint256 amount) external virtual onlyOwner {
        if (to.length == 0 || amount == 0) {
            revert InvalidOperation("Empty list or zero amount");
        }

        uint256 totalToMint = to.length * amount;

        // Global supply
        if (_totalMinted() + totalToMint > i_maxSupply) {
            revert ExceedsMaxSupply(totalToMint, i_maxSupply - _totalMinted());
        }

        // Cannot eat into stage-reserved supply
        uint256 stageAllocated = i_registry.getTotalStageMaxSupply();
        uint256 reservedForAirdrops = i_maxSupply > stageAllocated ? i_maxSupply - stageAllocated : 0;

        if (s_totalAirdropped + totalToMint > reservedForAirdrops) {
            revert InvalidOperation("Airdrop exceeds unreserved supply");
        }

        s_totalAirdropped += totalToMint;

        for (uint256 i = 0; i < to.length; i++) {
            _safeMint(to[i], amount);
        }

        emit NFTsAirdropped(to, amount, totalToMint);
    }

    // ─── Burn ─────────────────────────────────────────────────────────────────

    /**
     * @notice Burn a token. Allowed even if collection is soulbound.
     */
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _burn(tokenId);
    }

    //───Metadata─────────────────────────────────────────────────────────────────

    function _baseURI() internal view override returns (string memory) {
        return s_baseURI;
    }

    function setBaseURI(string calldata uri) external virtual onlyOwner {
        if (bytes(uri).length == 0) revert InvalidURI();
        s_baseURI = uri;
        emit BaseURIUpdated(uri);
    }

    // ─── Royalties ────────────────────────────────────────────────────────────

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function withdraw() external onlyOwner {
        require(address(this).balance > 0, "No balance to withdraw");
        (bool success,) = owner().call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    // ─── View: Supply ─────────────────────────────────────────────────────────

    function getSupplyInfo()
        external
        view
        returns (
            uint256 maxSupply,
            uint256 totalMintedSoFar,
            uint256 remainingSupply,
            uint256 stagesAllocated,
            uint256 airdropped,
            uint256 availableForNewStages,
            uint256 availableForAirdrops
        )
    {
        maxSupply = i_maxSupply;
        totalMintedSoFar = _totalMinted();
        remainingSupply = i_maxSupply - totalMintedSoFar;
        stagesAllocated = i_registry.getTotalStageMaxSupply();
        airdropped = s_totalAirdropped;

        uint256 allocated = stagesAllocated + s_totalAirdropped;
        availableForNewStages = allocated < i_maxSupply ? i_maxSupply - allocated : 0;

        uint256 airdropBudget = i_maxSupply > stagesAllocated ? i_maxSupply - stagesAllocated : 0;
        availableForAirdrops = airdropBudget > s_totalAirdropped ? airdropBudget - s_totalAirdropped : 0;
    }

    // ─── Interface Support ────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721AC, ERC2981) returns (bool) {
        return ERC721AC.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}
