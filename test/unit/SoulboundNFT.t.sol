// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeploySoulboundNFT} from "../../script/DeploySoulboundNFT.s.sol";
import {SoulboundNFT} from "../../src/SoulboundNFT.sol";
import {MintStageRegistry} from "../../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";

contract SoulboundNFTTest is Test, CodeConstants {
    SoulboundNFT nft;
    MintStageRegistry registry;

    address public OWNER;
    address public USER = makeAddr("user");
    address public OTHER = makeAddr("other");
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 public stageId;

    function setUp() external {
        DeploySoulboundNFT deployer = new DeploySoulboundNFT();
        (nft, registry,) = deployer.deploySoulboundNFT("Soulbound", "SB", 100);

        OWNER = nft.owner();
        vm.deal(USER, STARTING_BALANCE);

        vm.startPrank(OWNER);
        stageId = registry.addStage(
            "Public Sale",
            0.01 ether,
            50,
            10,
            false,
            block.timestamp,
            block.timestamp + 30 days,
            true,
            false
        );
        vm.stopPrank();
    }

    // ─── Minting Works ──────────────────────────────────────────────────────

    function testCanMint() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        assertEq(nft.balanceOf(USER), 1);
    }

    // ─── Transfers Blocked ───────────────────────────────────────────────────

    function testRevertTransferFrom() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        vm.prank(USER);
        vm.expectRevert(SoulboundNFT.TokenIsSoulbound.selector);
        nft.transferFrom(USER, OTHER, 0);
    }

    function testRevertSafeTransferFrom() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        vm.prank(USER);
        vm.expectRevert(SoulboundNFT.TokenIsSoulbound.selector);
        nft.safeTransferFrom(USER, OTHER, 0);
    }

    // ─── Burns Allowed ───────────────────────────────────────────────────────

    function testCanBurnOwnToken() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        vm.prank(USER);
        nft.burn(0);

        assertEq(nft.balanceOf(USER), 0);
    }

    // ─── Airdrop Works ───────────────────────────────────────────────────────

    function testCanAirdrop() public {
        address[] memory recipients = new address[](2);
        recipients[0] = USER;
        recipients[1] = OTHER;

        vm.prank(OWNER);
        nft.batchAirdrop(recipients, 1);

        assertEq(nft.balanceOf(USER), 1);
        assertEq(nft.balanceOf(OTHER), 1);
    }

    function testRevertTransferAfterAirdrop() public {
        address[] memory recipients = new address[](1);
        recipients[0] = USER;

        vm.prank(OWNER);
        nft.batchAirdrop(recipients, 1);

        vm.prank(USER);
        vm.expectRevert(SoulboundNFT.TokenIsSoulbound.selector);
        nft.transferFrom(USER, OTHER, 0);
    }
}
