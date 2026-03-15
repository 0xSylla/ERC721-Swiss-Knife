// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MintStageRegistry} from "../src/Registry/MintStageRegistry.sol";

/**
 * @notice Add a public FCFS mint stage to a deployed registry.
 * @dev Usage: forge script script/Interactions.s.sol:AddPublicStage \
 *        --rpc-url $RPC_URL --broadcast --sig "run(address)" <REGISTRY_ADDR>
 */
contract AddPublicStage is Script {
    function run(address registry) external {
        vm.startBroadcast();

        MintStageRegistry(registry)
            .addStage(
                "Public Sale", // name
                0.01 ether, // price
                5000, // maxSupply for stage
                100, // maxPerWallet
                false, // requiresAllowlist
                block.timestamp, // startTime (now)
                block.timestamp + 30 days, // endTime
                true, // isActive
                false // isGTD (FCFS)
            );

        vm.stopBroadcast();
        console.log("Public FCFS stage added to registry:", registry);
    }
}

/**
 * @notice Add an allowlist GTD mint stage.
 */
contract AddAllowlistStage is Script {
    function run(address registry) external {
        vm.startBroadcast();

        MintStageRegistry(registry)
            .addStage(
                "Allowlist Sale", // name
                0.005 ether, // price (discounted)
                2000, // maxSupply for stage
                3, // maxPerWallet
                true, // requiresAllowlist
                block.timestamp, // startTime
                block.timestamp + 7 days, // endTime
                true, // isActive
                true // isGTD
            );

        vm.stopBroadcast();
        console.log("Allowlist GTD stage added to registry:", registry);
    }
}

/**
 * @notice Add addresses to an allowlist for a given stage.
 */
contract AddToAllowlist is Script {
    function run(address registry, uint256 stageId, address[] calldata accounts) external {
        vm.startBroadcast();
        MintStageRegistry(registry).batchAddToAllowlist(stageId, accounts);
        vm.stopBroadcast();

        console.log("Added", accounts.length, "addresses to allowlist for stage", stageId);
    }
}

/**
 * @notice Activate/deactivate a stage.
 */
contract SetStageStatus is Script {
    function run(address registry, uint256 stageId, bool isActive) external {
        vm.startBroadcast();
        MintStageRegistry(registry).setStageStatus(stageId, isActive);
        vm.stopBroadcast();

        console.log("Stage", stageId, "status set to", isActive);
    }
}

/**
 * @notice Reveal a PreRevealNFT collection.
 */
contract RevealCollection is Script {
    function run(address nft, string calldata realBaseURI) external {
        vm.startBroadcast();

        (bool success,) = nft.call(abi.encodeWithSignature("reveal(string)", realBaseURI));
        require(success, "Reveal failed");

        vm.stopBroadcast();
        console.log("Collection revealed:", nft);
    }
}
