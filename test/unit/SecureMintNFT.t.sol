// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeploySecureMintNFT} from "../../script/DeploySecureMintNFT.s.sol";
import {SecureMintNFT} from "../../src/SecureMintNFT.sol";
import {MintStageRegistry} from "../../src/Registry/MintStageRegistry.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";

contract SecureMintNFTTest is Test, CodeConstants {
    SecureMintNFT nft;
    MintStageRegistry registry;

    address public OWNER;
    address public USER = makeAddr("user");
    uint256 public SIGNER_KEY;
    address public SIGNER;
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 public stageId;

    // Must match the MINT_TYPEHASH in SecureMintNFT
    bytes32 private constant MINT_TYPEHASH =
        keccak256("Mint(address minter,uint256 stageId,uint256 amount,uint256 nonce,uint256 deadline)");

    function setUp() external {
        // Use a deterministic key for the signer
        SIGNER_KEY = 0xA11CE;
        SIGNER = vm.addr(SIGNER_KEY);

        // Deploy directly (no broadcast needed in tests)
        MintStageRegistry _registry = new MintStageRegistry(address(this));

        SecureMintNFT _nft = new SecureMintNFT(
            BaseNFTParams.InitParams({
                collectionName: "SecureNFT",
                collectionSymbol: "SNFT",
                collectionOwner: address(this),
                collectionMaxSupply: 100,
                baseURI: DEFAULT_BASE_URI,
                royaltyReceiver: address(this),
                royaltyFeeBps: DEFAULT_ROYALTY_BPS,
                mintStageRegistry: address(_registry)
            }),
            SIGNER
        );
        _registry.bindCollection(address(_nft));

        nft = _nft;
        registry = _registry;
        OWNER = address(this);

        vm.deal(USER, STARTING_BALANCE);

        // Create a public stage
        stageId = registry.addStage(
            "Public Sale", 0.01 ether, 50, 10, false, block.timestamp, block.timestamp + 30 days, true, false
        );
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _signMint(address minter, uint256 _stageId, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(MINT_TYPEHASH, minter, _stageId, amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", nft.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    // ─── Secure Mint ─────────────────────────────────────────────────────────

    function testSecureMintWithValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signMint(USER, stageId, 1, 0, deadline);

        vm.prank(USER);
        nft.secureBatchMint{value: 0.01 ether}(stageId, 1, deadline, sig);

        assertEq(nft.balanceOf(USER), 1);
    }

    function testNonceIncrements() public {
        uint256 deadline = block.timestamp + 1 hours;

        assertEq(nft.getNonce(USER), 0);

        bytes memory sig = _signMint(USER, stageId, 1, 0, deadline);
        vm.prank(USER);
        nft.secureBatchMint{value: 0.01 ether}(stageId, 1, deadline, sig);

        assertEq(nft.getNonce(USER), 1);
    }

    function testRevertReplaySignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signMint(USER, stageId, 1, 0, deadline);

        vm.prank(USER);
        nft.secureBatchMint{value: 0.01 ether}(stageId, 1, deadline, sig);

        // Replay same sig (nonce is now 1, sig was for nonce 0)
        vm.prank(USER);
        vm.expectRevert(SecureMintNFT.InvalidSignature.selector);
        nft.secureBatchMint{value: 0.01 ether}(stageId, 1, deadline, sig);
    }

    function testRevertExpiredSignature() public {
        uint256 deadline = block.timestamp - 1; // already expired
        bytes memory sig = _signMint(USER, stageId, 1, 0, deadline);

        vm.prank(USER);
        vm.expectRevert(SecureMintNFT.SignatureExpired.selector);
        nft.secureBatchMint{value: 0.01 ether}(stageId, 1, deadline, sig);
    }

    function testRevertDirectBatchMint() public {
        vm.prank(USER);
        vm.expectRevert();
        nft.batchMint{value: 0.01 ether}(stageId, 1);
    }

    function testRevertWrongSigner() public {
        uint256 fakeKey = 0xBAD;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(abi.encode(MINT_TYPEHASH, USER, stageId, 1, 0, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", nft.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fakeKey, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(USER);
        vm.expectRevert(SecureMintNFT.InvalidSignature.selector);
        nft.secureBatchMint{value: 0.01 ether}(stageId, 1, deadline, badSig);
    }

    // ─── Signer Management ───────────────────────────────────────────────────

    function testSetSigner() public {
        address newSigner = makeAddr("newSigner");

        nft.setSigner(newSigner);
        assertEq(nft.s_signer(), newSigner);
    }

    function testRevertSetSignerToZero() public {
        vm.expectRevert(SecureMintNFT.InvalidSigner.selector);
        nft.setSigner(address(0));
    }
}

// Need this import for the InitParams struct
import {BaseNFTParams} from "../../src/Base/BaseNFTNativePaymentToken.sol";
