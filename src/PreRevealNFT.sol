// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseNFT, BaseNFTParams} from "./Base/BaseNFTNativePaymentToken.sol";

/**
 * @title PreRevealNFT
 * @notice ERC721 with pre-reveal logic: all tokens return a shared placeholder
 *         URI until the owner triggers the reveal.
 *
 * Pre-reveal flow:
 *   1. Deploy with a placeholder URI (e.g. IPFS CID pointing to a generic image).
 *   2. Users mint — every token returns the same placeholder metadata.
 *   3. Owner calls `reveal(realBaseURI)` to flip all tokens to their real metadata.
 *
 * Once revealed, the state is permanent — it cannot be reversed.
 */
contract PreRevealNFT is BaseNFT {
    error AlreadyRevealed();
    error NotRevealed();
    error EmptyRevealURI();

    string public s_placeholderURI;
    bool public s_revealed;

    event Revealed(string baseURI);
    event PlaceholderURIUpdated(string placeholderURI);

    constructor(
        BaseNFTParams.InitParams memory _params,
        string memory placeholderURI
    ) BaseNFT(_params) {
        s_placeholderURI = placeholderURI;
    }

    // ─── Reveal ──────────────────────────────────────────────────────────────

    /**
     * @notice Reveal the collection by setting the real base URI.
     * @dev One-shot: once revealed, cannot be undone.
     * @param realBaseURI The real base URI for revealed metadata
     */
    function reveal(string calldata realBaseURI) external onlyOwner {
        if (s_revealed) revert AlreadyRevealed();
        if (bytes(realBaseURI).length == 0) revert EmptyRevealURI();

        s_revealed = true;
        s_baseURI = realBaseURI;

        emit Revealed(realBaseURI);
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    /**
     * @notice Returns the token URI.
     *         Before reveal: all tokens return the placeholder URI.
     *         After reveal:  standard baseURI + tokenId behavior.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (!s_revealed) {
            return s_placeholderURI;
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @notice Update the placeholder URI (only before reveal).
     * @param placeholderURI New placeholder URI
     */
    function setPlaceholderURI(
        string calldata placeholderURI
    ) external onlyOwner {
        if (s_revealed) revert AlreadyRevealed();
        s_placeholderURI = placeholderURI;
        emit PlaceholderURIUpdated(placeholderURI);
    }

    /**
     * @dev Override setBaseURI to only allow changes after reveal.
     *      Before reveal, the base URI is meaningless — use setPlaceholderURI.
     */
    function setBaseURI(string calldata uri) external override onlyOwner {
        if (!s_revealed) revert NotRevealed();
        if (bytes(uri).length == 0) revert InvalidURI();
        s_baseURI = uri;
        emit BaseURIUpdated(uri);
    }
}
