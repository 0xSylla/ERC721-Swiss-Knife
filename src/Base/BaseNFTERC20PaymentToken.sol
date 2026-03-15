// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@limitbreak/creator-token-standards/src/erc721c/ERC721AC.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Interface/IMintStageRegistry.sol";

library BaseNFTERC20Params {
    struct InitParams {
        string collectionName;
        string collectionSymbol;
        address collectionOwner;
        uint256 collectionMaxSupply;
        string baseURI;
        address royaltyReceiver;
        uint96 royaltyFeeBps;
        address mintStageRegistry;
        address paymentToken;
    }
}

contract BaseNFTERC20 is OwnableBasic, ERC721AC, BasicRoyalties {
    using SafeERC20 for IERC20;

    error InvalidURI();
    error InvalidOperation(string reason);
    error ExceedsMaxSupply(uint256 requested, uint256 available);
    error InvalidPaymentToken();

    IMintStageRegistry public immutable i_registry;
    uint256 public immutable i_maxSupply;
    IERC20 public immutable i_paymentToken;

    string public s_baseURI;
    uint256 public s_totalAirdropped;

    event BaseURIUpdated(string baseURI);
    event NFTsMinted(
        address indexed recipient,
        uint256 amount,
        uint256 stageId
    );
    event NFTsAirdropped(
        address[] recipients,
        uint256 amountPerRecipient,
        uint256 totalAmount
    );

    constructor(
        BaseNFTERC20Params.InitParams memory _params
    )
        ERC721AC(_params.collectionName, _params.collectionSymbol)
        OwnableBasic(_params.collectionOwner)
        BasicRoyalties(_params.royaltyReceiver, _params.royaltyFeeBps)
    {
        if (_params.paymentToken == address(0)) revert InvalidPaymentToken();
        i_registry = IMintStageRegistry(_params.mintStageRegistry);
        i_maxSupply = _params.collectionMaxSupply;
        s_baseURI = _params.baseURI;
        i_paymentToken = IERC20(_params.paymentToken);
    }

    // ─── Mint ────────────────────────────────────────────────────────────────

    /**
     * @notice Mint tokens through an active stage, paying with the ERC20 token.
     * @dev Caller must have approved this contract for at least `totalCost` tokens.
     * @param stageId  The stage to mint through
     * @param amount   Number of tokens to mint
     */
    function batchMint(
        uint256 stageId,
        uint256 amount
    ) external virtual {
        if (_totalMinted() + amount > i_maxSupply) {
            revert ExceedsMaxSupply(amount, i_maxSupply - _totalMinted());
        }

        uint256 totalCost = i_registry.validateAndRecordMint(
            stageId,
            msg.sender,
            amount
        );

        if (totalCost > 0) {
            i_paymentToken.safeTransferFrom(msg.sender, address(this), totalCost);
        }

        _mint(msg.sender, amount);

        emit NFTsMinted(msg.sender, amount, stageId);
    }

    /**
     * @notice Owner-only batch airdrop. Respects stage-reserved supply.
     * @param to     Array of recipient addresses
     * @param amount Number of tokens each recipient receives
     */
    function batchAirdrop(
        address[] calldata to,
        uint256 amount
    ) external virtual onlyOwner {
        if (to.length == 0 || amount == 0)
            revert InvalidOperation("Empty list or zero amount");

        uint256 totalToMint = to.length * amount;

        if (_totalMinted() + totalToMint > i_maxSupply) {
            revert ExceedsMaxSupply(totalToMint, i_maxSupply - _totalMinted());
        }

        uint256 stageAllocated = i_registry.getTotalStageMaxSupply();
        uint256 reservedForAirdrops = i_maxSupply > stageAllocated
            ? i_maxSupply - stageAllocated
            : 0;

        if (s_totalAirdropped + totalToMint > reservedForAirdrops) {
            revert InvalidOperation("Airdrop exceeds unreserved supply");
        }

        s_totalAirdropped += totalToMint;

        for (uint256 i = 0; i < to.length; i++) {
            _safeMint(to[i], amount);
        }

        emit NFTsAirdropped(to, amount, totalToMint);
    }

    // ─── Burn ────────────────────────────────────────────────────────────────

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _burn(tokenId);
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    function _baseURI() internal view override returns (string memory) {
        return s_baseURI;
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        if (bytes(uri).length == 0) revert InvalidURI();
        s_baseURI = uri;
        emit BaseURIUpdated(uri);
    }

    // ─── Royalties ───────────────────────────────────────────────────────────

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    // ─── Withdraw ────────────────────────────────────────────────────────────

    function withdraw() external onlyOwner {
        uint256 balance = i_paymentToken.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        i_paymentToken.safeTransfer(owner(), balance);
    }

    // ─── View: Supply ────────────────────────────────────────────────────────

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
        availableForNewStages = allocated < i_maxSupply
            ? i_maxSupply - allocated
            : 0;

        uint256 airdropBudget = i_maxSupply > stagesAllocated
            ? i_maxSupply - stagesAllocated
            : 0;
        availableForAirdrops = airdropBudget > s_totalAirdropped
            ? airdropBudget - s_totalAirdropped
            : 0;
    }

    // ─── Interface Support ───────────────────────────────────────────────────

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721AC, ERC2981) returns (bool) {
        return
            ERC721AC.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }
}
