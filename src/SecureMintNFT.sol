// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseNFT, BaseNFTParams} from "./Base/BaseNFTNativePaymentToken.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title SecureMintNFT
 * @notice Anti-bot ERC721 with backend signature verification (native ETH payment).
 *
 * Mint flow:
 *   1. User requests a mint from the frontend (passes captcha, rate-limit, etc.).
 *   2. Backend validates the request and signs a typed EIP-712 message containing:
 *      - minter   : msg.sender (binds sig to caller — prevents mempool copying)
 *      - stageId  : the mint stage
 *      - amount   : token count
 *      - nonce    : per-user nonce (prevents replay)
 *      - deadline : unix timestamp after which the sig expires
 *   3. User submits the tx with the signature. Contract verifies it on-chain.
 *
 * The owner can rotate the signer address at any time without redeploying.
 */
contract SecureMintNFT is BaseNFT, EIP712 {
    using ECDSA for bytes32;

    error InvalidSignature();
    error SignatureExpired();
    error InvalidSigner();

    bytes32 private constant MINT_TYPEHASH = keccak256(
        "Mint(address minter,uint256 stageId,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    address public s_signer;
    mapping(address => uint256) public s_nonces;

    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    constructor(
        BaseNFTParams.InitParams memory _params,
        address signer
    )
        BaseNFT(_params)
        EIP712(_params.collectionName, "1")
    {
        if (signer == address(0)) revert InvalidSigner();
        s_signer = signer;
    }

    // ─── Secure Mint ─────────────────────────────────────────────────────────

    /**
     * @notice Mint with a backend-issued signature.
     * @param stageId   The stage to mint through
     * @param amount    Number of tokens to mint
     * @param deadline  Signature expiry (unix timestamp)
     * @param signature Backend ECDSA signature over the EIP-712 typed data
     */
    function secureBatchMint(
        uint256 stageId,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external payable {
        if (block.timestamp > deadline) revert SignatureExpired();

        uint256 currentNonce = s_nonces[msg.sender];

        bytes32 structHash = keccak256(
            abi.encode(MINT_TYPEHASH, msg.sender, stageId, amount, currentNonce, deadline)
        );
        address recovered = _hashTypedDataV4(structHash).recover(signature);
        if (recovered != s_signer) revert InvalidSignature();

        s_nonces[msg.sender] = currentNonce + 1;

        _executeMint(stageId, amount);
    }

    /**
     * @dev Override to block direct unsigned mints.
     *      All mints must go through secureBatchMint.
     */
    function batchMint(uint256, uint256) external payable override {
        revert InvalidOperation("Use secureBatchMint");
    }

    // ─── Signer Management ──────────────────────────────────────────────────

    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidSigner();
        emit SignerUpdated(s_signer, newSigner);
        s_signer = newSigner;
    }

    // ─── View ────────────────────────────────────────────────────────────────

    function getNonce(address user) external view returns (uint256) {
        return s_nonces[user];
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
