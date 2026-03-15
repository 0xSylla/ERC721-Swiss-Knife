// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BaseNFTOmnichain} from "../src/O721NFT.sol";
import {BaseNFTParams} from "../src/Base/BaseNFTNativePaymentToken.sol";
import {MintStageRegistry} from "../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";

contract DeployOmnichainNFT is Script, CodeConstants {
    function run() external returns (BaseNFTOmnichain, MintStageRegistry, HelperConfig) {
        return deployOmnichainNFT("Omnichain", "O721", DEFAULT_MAX_SUPPLY);
    }

    function deployOmnichainNFT(
        string memory name,
        string memory symbol,
        uint256 maxSupply
    ) public returns (BaseNFTOmnichain, MintStageRegistry, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        address deployer = config.deployer != address(0) ? config.deployer : msg.sender;
        address royaltyReceiver = config.royaltyReceiver != address(0) ? config.royaltyReceiver : deployer;

        require(config.lzEndpoint != address(0), "LZ endpoint required for omnichain deploy");

        vm.startBroadcast(deployer);

        MintStageRegistry registry = new MintStageRegistry(deployer);

        BaseNFTOmnichain nft = new BaseNFTOmnichain(
            BaseNFTParams.InitParams({
                collectionName: name,
                collectionSymbol: symbol,
                collectionOwner: deployer,
                collectionMaxSupply: maxSupply,
                baseURI: DEFAULT_BASE_URI,
                royaltyReceiver: royaltyReceiver,
                royaltyFeeBps: DEFAULT_ROYALTY_BPS,
                mintStageRegistry: address(registry)
            }),
            config.lzEndpoint,
            deployer // delegate
        );

        registry.bindCollection(address(nft));

        vm.stopBroadcast();

        return (nft, registry, helperConfig);
    }
}
