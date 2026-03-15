// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployPreRevealNFT} from "../../script/DeployPreRevealNFT.s.sol";
import {PreRevealNFT} from "../../src/PreRevealNFT.sol";
import {MintStageRegistry} from "../../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";

contract PreRevealNFTTest is Test, CodeConstants {
    PreRevealNFT nft;
    MintStageRegistry registry;

    address public OWNER;
    address public USER = makeAddr("user");
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 public stageId;

    function setUp() external {
        DeployPreRevealNFT deployer = new DeployPreRevealNFT();
        (nft, registry,) = deployer.deployPreRevealNFT("PreReveal", "PR", 100);

        OWNER = nft.owner();
        vm.deal(USER, STARTING_BALANCE);

        vm.startPrank(OWNER);
        stageId = registry.addStage(
            "Public Sale", 0.01 ether, 50, 10, false, block.timestamp, block.timestamp + 30 days, true, false
        );
        vm.stopPrank();
    }

    // ─── Pre-Reveal State ────────────────────────────────────────────────────

    function testInitialStateNotRevealed() public view {
        assertFalse(nft.s_revealed());
    }

    function testPlaceholderURISetOnDeploy() public view {
        assertEq(nft.s_placeholderURI(), DEFAULT_PLACEHOLDER_URI);
    }

    function testTokenURIReturnsPlaceholderBeforeReveal() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        assertEq(nft.tokenURI(0), DEFAULT_PLACEHOLDER_URI);
    }

    function testAllTokensReturnSamePlaceholder() public {
        vm.prank(USER);
        nft.batchMint{value: 0.03 ether}(stageId, 3);

        assertEq(nft.tokenURI(0), DEFAULT_PLACEHOLDER_URI);
        assertEq(nft.tokenURI(1), DEFAULT_PLACEHOLDER_URI);
        assertEq(nft.tokenURI(2), DEFAULT_PLACEHOLDER_URI);
    }

    // ─── Reveal ──────────────────────────────────────────────────────────────

    function testRevealSetsRealBaseURI() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        vm.prank(OWNER);
        nft.reveal("ipfs://revealed/");

        assertEq(nft.tokenURI(0), "ipfs://revealed/0");
    }

    function testRevealSetsRevealedFlag() public {
        vm.prank(OWNER);
        nft.reveal("ipfs://revealed/");

        assertTrue(nft.s_revealed());
    }

    function testRevertDoubleReveal() public {
        vm.startPrank(OWNER);
        nft.reveal("ipfs://revealed/");

        vm.expectRevert(PreRevealNFT.AlreadyRevealed.selector);
        nft.reveal("ipfs://revealed2/");
        vm.stopPrank();
    }

    function testRevertRevealEmptyURI() public {
        vm.prank(OWNER);
        vm.expectRevert(PreRevealNFT.EmptyRevealURI.selector);
        nft.reveal("");
    }

    function testRevertRevealByNonOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        nft.reveal("ipfs://revealed/");
    }

    // ─── Placeholder URI Management ──────────────────────────────────────────

    function testSetPlaceholderURIBeforeReveal() public {
        vm.prank(OWNER);
        nft.setPlaceholderURI("ipfs://newPlaceholder");

        assertEq(nft.s_placeholderURI(), "ipfs://newPlaceholder");
    }

    function testRevertSetPlaceholderURIAfterReveal() public {
        vm.startPrank(OWNER);
        nft.reveal("ipfs://revealed/");

        vm.expectRevert(PreRevealNFT.AlreadyRevealed.selector);
        nft.setPlaceholderURI("ipfs://newPlaceholder");
        vm.stopPrank();
    }

    // ─── BaseURI Management ──────────────────────────────────────────────────

    function testRevertSetBaseURIBeforeReveal() public {
        vm.prank(OWNER);
        vm.expectRevert(PreRevealNFT.NotRevealed.selector);
        nft.setBaseURI("ipfs://sneaky/");
    }

    function testSetBaseURIAfterReveal() public {
        vm.startPrank(OWNER);
        nft.reveal("ipfs://revealed/");
        nft.setBaseURI("ipfs://updated/");
        vm.stopPrank();

        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        assertEq(nft.tokenURI(0), "ipfs://updated/0");
    }
}
