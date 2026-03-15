// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployBaseNFT} from "../../script/DeployBaseNFT.s.sol";
import {BaseNFT} from "../../src/Base/BaseNFTNativePaymentToken.sol";
import {MintStageRegistry} from "../../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";

contract BaseNFTTest is Test, CodeConstants {
    BaseNFT nft;
    MintStageRegistry registry;
    HelperConfig helperConfig;

    address public OWNER;
    address public USER = makeAddr("user");
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 public stageId;

    function setUp() external {
        DeployBaseNFT deployer = new DeployBaseNFT();
        (nft, registry, helperConfig) = deployer.deployBaseNFT("TestNFT", "TNFT", 100);

        OWNER = nft.owner();
        vm.deal(USER, STARTING_BALANCE);

        // Create and activate a public FCFS stage
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

    // ─── Deployment ──────────────────────────────────────────────────────────

    function testDeploymentSetsCorrectName() public view {
        assertEq(nft.name(), "TestNFT");
    }

    function testDeploymentSetsCorrectSymbol() public view {
        assertEq(nft.symbol(), "TNFT");
    }

    function testDeploymentSetsCorrectMaxSupply() public view {
        assertEq(nft.i_maxSupply(), 100);
    }

    function testDeploymentSetsCorrectOwner() public view {
        assertEq(nft.owner(), OWNER);
    }

    function testRegistryBoundToNFT() public view {
        assertEq(registry.boundCollection(), address(nft));
    }

    // ─── Minting ─────────────────────────────────────────────────────────────

    function testMintSingleToken() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        assertEq(nft.balanceOf(USER), 1);
    }

    function testMintBatchTokens() public {
        vm.prank(USER);
        nft.batchMint{value: 0.05 ether}(stageId, 5);

        assertEq(nft.balanceOf(USER), 5);
    }

    function testMintRefundsExcess() public {
        uint256 balanceBefore = USER.balance;

        vm.prank(USER);
        nft.batchMint{value: 1 ether}(stageId, 1);

        assertEq(USER.balance, balanceBefore - 0.01 ether);
    }

    function testRevertMintInsufficientEther() public {
        vm.prank(USER);
        vm.expectRevert();
        nft.batchMint{value: 0.005 ether}(stageId, 1);
    }

    function testRevertMintExceedsMaxPerWallet() public {
        vm.prank(USER);
        vm.expectRevert();
        nft.batchMint{value: 0.11 ether}(stageId, 11); // maxPerWallet = 10
    }

    // ─── Airdrop ─────────────────────────────────────────────────────────────

    function testAirdropByOwner() public {
        address[] memory recipients = new address[](3);
        recipients[0] = makeAddr("r1");
        recipients[1] = makeAddr("r2");
        recipients[2] = makeAddr("r3");

        vm.prank(OWNER);
        nft.batchAirdrop(recipients, 1);

        assertEq(nft.balanceOf(recipients[0]), 1);
        assertEq(nft.balanceOf(recipients[1]), 1);
        assertEq(nft.balanceOf(recipients[2]), 1);
    }

    function testRevertAirdropByNonOwner() public {
        address[] memory recipients = new address[](1);
        recipients[0] = USER;

        vm.prank(USER);
        vm.expectRevert();
        nft.batchAirdrop(recipients, 1);
    }

    // ─── Burn ────────────────────────────────────────────────────────────────

    function testBurnOwnToken() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        uint256 tokenId = 0; // First token minted (ERC721A starts at 0)

        vm.prank(USER);
        nft.burn(tokenId);

        assertEq(nft.balanceOf(USER), 0);
    }

    function testRevertBurnNotOwner() public {
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        vm.prank(makeAddr("other"));
        vm.expectRevert();
        nft.burn(0);
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    function testSetBaseURI() public {
        vm.prank(OWNER);
        nft.setBaseURI("ipfs://newURI/");

        // Mint a token to verify URI
        vm.prank(USER);
        nft.batchMint{value: 0.01 ether}(stageId, 1);

        assertEq(nft.tokenURI(0), "ipfs://newURI/0");
    }

    function testRevertSetBaseURIByNonOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        nft.setBaseURI("ipfs://hack/");
    }

    // ─── Withdraw ────────────────────────────────────────────────────────────

    function testWithdraw() public {
        vm.prank(USER);
        nft.batchMint{value: 0.05 ether}(stageId, 5);

        uint256 ownerBalanceBefore = OWNER.balance;

        vm.prank(OWNER);
        nft.withdraw();

        assertEq(OWNER.balance, ownerBalanceBefore + 0.05 ether);
    }

    // ─── Supply Info ─────────────────────────────────────────────────────────

    function testGetSupplyInfo() public {
        vm.prank(USER);
        nft.batchMint{value: 0.03 ether}(stageId, 3);

        (
            uint256 maxSupply,
            uint256 totalMinted,
            uint256 remaining,
            ,,,
        ) = nft.getSupplyInfo();

        assertEq(maxSupply, 100);
        assertEq(totalMinted, 3);
        assertEq(remaining, 97);
    }
}
