// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {SecureMintNFT} from "../src/SecureMintNFT.sol";
import {BaseNFTParams} from "../src/Base/BaseNFTNativePaymentToken.sol";
import {MintStageRegistry} from "../src/Registry/MintStageRegistry.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";

contract DeploySecureMintNFT is Script, CodeConstants {
    function run() external returns (SecureMintNFT, MintStageRegistry, HelperConfig) {
        return deploySecureMintNFT("SecureMint", "SM721", DEFAULT_MAX_SUPPLY);
    }

    function deploySecureMintNFT(
        string memory name,
        string memory symbol,
        uint256 maxSupply
    ) public returns (SecureMintNFT, MintStageRegistry, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        address deployer = config.deployer != address(0) ? config.deployer : msg.sender;
        address royaltyReceiver = config.royaltyReceiver != address(0) ? config.royaltyReceiver : deployer;
        address signer = config.backendSigner != address(0) ? config.backendSigner : deployer;

        vm.startBroadcast(deployer);

        MintStageRegistry registry = new MintStageRegistry(deployer);

        SecureMintNFT nft = new SecureMintNFT(
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
            signer
        );

        registry.bindCollection(address(nft));

        vm.stopBroadcast();

        return (nft, registry, helperConfig);
    }
}
