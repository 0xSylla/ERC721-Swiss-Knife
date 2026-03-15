// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseNFT, BaseNFTParams} from "./Base/BaseNFTNativePaymentToken.sol";
import {BaseNFTERC20, BaseNFTERC20Params} from "./Base/BaseNFTERC20PaymentToken.sol";

/**
 * @title SoulboundNFT
 * @notice Non-transferable ERC721 (native ETH payment).
 *         Tokens cannot be transferred between wallets once minted.
 *         Burns are still permitted so holders can destroy their own tokens.
 */
contract SoulboundNFT is BaseNFT {
    error TokenIsSoulbound();

    constructor(BaseNFTParams.InitParams memory _params) BaseNFT(_params) {}

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        // Allow mints (from == 0) and burns (to == 0), block transfers
        if (from != address(0) && to != address(0)) {
            revert TokenIsSoulbound();
        }
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }
}

/**
 * @title SoulboundNFTERC20
 * @notice Non-transferable ERC721 (ERC20 payment).
 *         Tokens cannot be transferred between wallets once minted.
 *         Burns are still permitted so holders can destroy their own tokens.
 */
contract SoulboundNFTERC20 is BaseNFTERC20 {
    error TokenIsSoulbound();

    constructor(BaseNFTERC20Params.InitParams memory _params) BaseNFTERC20(_params) {}

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            revert TokenIsSoulbound();
        }
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }
}
