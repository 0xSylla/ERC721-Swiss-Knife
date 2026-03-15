// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BaseNFT, BaseNFTParams} from "../src/Base/BaseNFTNativePaymentToken.sol";
import {MintStageRegistry} from "../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";

contract DeployBaseNFT is Script, CodeConstants {
    function run() external returns (BaseNFT, MintStageRegistry, HelperConfig) {
        return deployBaseNFT("SwissKnife", "SK721", DEFAULT_MAX_SUPPLY);
    }

    function deployBaseNFT(
        string memory name,
        string memory symbol,
        uint256 maxSupply
    ) public returns (BaseNFT, MintStageRegistry, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        address deployer = config.deployer != address(0) ? config.deployer : msg.sender;
        address royaltyReceiver = config.royaltyReceiver != address(0) ? config.royaltyReceiver : deployer;

        vm.startBroadcast(deployer);

        // 1. Deploy registry
        MintStageRegistry registry = new MintStageRegistry(deployer);

        // 2. Deploy NFT
        BaseNFT nft = new BaseNFT(
            BaseNFTParams.InitParams({
                collectionName: name,
                collectionSymbol: symbol,
                collectionOwner: deployer,
                collectionMaxSupply: maxSupply,
                baseURI: DEFAULT_BASE_URI,
                royaltyReceiver: royaltyReceiver,
                royaltyFeeBps: DEFAULT_ROYALTY_BPS,
                mintStageRegistry: address(registry)
            })
        );

        // 3. Bind registry to NFT
        registry.bindCollection(address(nft));

        vm.stopBroadcast();

        return (nft, registry, helperConfig);
    }
}
