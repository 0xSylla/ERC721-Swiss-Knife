// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PreRevealNFT} from "../src/PreRevealNFT.sol";
import {BaseNFTParams} from "../src/Base/BaseNFTNativePaymentToken.sol";
import {MintStageRegistry} from "../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";

contract DeployPreRevealNFT is Script, CodeConstants {
    function run() external returns (PreRevealNFT, MintStageRegistry, HelperConfig) {
        return deployPreRevealNFT("PreReveal", "PR721", DEFAULT_MAX_SUPPLY);
    }

    function deployPreRevealNFT(string memory name, string memory symbol, uint256 maxSupply)
        public
        returns (PreRevealNFT, MintStageRegistry, HelperConfig)
    {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        address deployer = config.deployer != address(0) ? config.deployer : msg.sender;
        address royaltyReceiver = config.royaltyReceiver != address(0) ? config.royaltyReceiver : deployer;

        vm.startBroadcast(deployer);

        MintStageRegistry registry = new MintStageRegistry(deployer);

        PreRevealNFT nft = new PreRevealNFT(
            BaseNFTParams.InitParams({
                collectionName: name,
                collectionSymbol: symbol,
                collectionOwner: deployer,
                collectionMaxSupply: maxSupply,
                baseURI: "",
                royaltyReceiver: royaltyReceiver,
                royaltyFeeBps: DEFAULT_ROYALTY_BPS,
                mintStageRegistry: address(registry)
            }),
            DEFAULT_PLACEHOLDER_URI
        );

        registry.bindCollection(address(nft));

        vm.stopBroadcast();

        return (nft, registry, helperConfig);
    }
}
