// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {SoulboundNFT} from "../src/SoulboundNFT.sol";
import {BaseNFTParams} from "../src/Base/BaseNFTNativePaymentToken.sol";
import {MintStageRegistry} from "../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";

contract DeploySoulboundNFT is Script, CodeConstants {
    function run() external returns (SoulboundNFT, MintStageRegistry, HelperConfig) {
        return deploySoulboundNFT("Soulbound", "SB721", DEFAULT_MAX_SUPPLY);
    }

    function deploySoulboundNFT(
        string memory name,
        string memory symbol,
        uint256 maxSupply
    ) public returns (SoulboundNFT, MintStageRegistry, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        address deployer = config.deployer != address(0) ? config.deployer : msg.sender;
        address royaltyReceiver = config.royaltyReceiver != address(0) ? config.royaltyReceiver : deployer;

        vm.startBroadcast(deployer);

        MintStageRegistry registry = new MintStageRegistry(deployer);

        SoulboundNFT nft = new SoulboundNFT(
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

        registry.bindCollection(address(nft));

        vm.stopBroadcast();

        return (nft, registry, helperConfig);
    }
}
