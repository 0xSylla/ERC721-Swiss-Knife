// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

abstract contract CodeConstants {
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    // Default collection params
    uint256 public constant DEFAULT_MAX_SUPPLY = 10_000;
    uint96 public constant DEFAULT_ROYALTY_BPS = 500; // 5%
    string public constant DEFAULT_BASE_URI = "ipfs://QmPlaceholder/";
    string public constant DEFAULT_PLACEHOLDER_URI = "ipfs://QmPlaceholderPreReveal";

    // LayerZero Endpoint V2 addresses
    address public constant LZ_ENDPOINT_MAINNET = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant LZ_ENDPOINT_SEPOLIA = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address public constant LZ_ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant LZ_ENDPOINT_BASE_SEPOLIA = 0x6EDCE65403992e310A62460808c4b910D972f10f;
}

contract HelperConfig is CodeConstants, Script {
    struct NetworkConfig {
        address deployer;
        address royaltyReceiver;
        address lzEndpoint; // LayerZero endpoint (zero if not omnichain)
        address paymentToken; // ERC20 payment token (zero for native ETH)
        address backendSigner; // For SecureMintNFT (zero if unused)
    }

    mapping(uint256 chainId => NetworkConfig) private s_networkConfigs;

    constructor() {
        s_networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetConfig();
        s_networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaConfig();
        s_networkConfigs[BASE_CHAIN_ID] = getBaseConfig();
        s_networkConfigs[BASE_SEPOLIA_CHAIN_ID] = getBaseSepoliaConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilConfig();
        }
        return s_networkConfigs[chainId];
    }

    function setConfig(uint256 chainId, NetworkConfig memory config) public {
        s_networkConfigs[chainId] = config;
    }

    // ─── Per-Chain Configs ───────────────────────────────────────────────────

    function getMainnetConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            deployer: address(0), // Set via --account or .env
            royaltyReceiver: address(0), // TODO: set before mainnet deploy
            lzEndpoint: LZ_ENDPOINT_MAINNET,
            paymentToken: address(0),
            backendSigner: address(0)
        });
    }

    function getSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            deployer: address(0),
            royaltyReceiver: address(0),
            lzEndpoint: LZ_ENDPOINT_SEPOLIA,
            paymentToken: address(0),
            backendSigner: address(0)
        });
    }

    function getBaseConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            deployer: address(0),
            royaltyReceiver: address(0),
            lzEndpoint: LZ_ENDPOINT_BASE,
            paymentToken: address(0),
            backendSigner: address(0)
        });
    }

    function getBaseSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            deployer: address(0),
            royaltyReceiver: address(0),
            lzEndpoint: LZ_ENDPOINT_BASE_SEPOLIA,
            paymentToken: address(0),
            backendSigner: address(0)
        });
    }

    // ─── Anvil (Local) ──────────────────────────────────────────────────────

    function getOrCreateAnvilConfig() internal returns (NetworkConfig memory) {
        // Return cached if already created
        if (s_networkConfigs[LOCAL_CHAIN_ID].deployer != address(0)) {
            return s_networkConfigs[LOCAL_CHAIN_ID];
        }

        // Default Anvil account #0
        address anvilDeployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        NetworkConfig memory config = NetworkConfig({
            deployer: anvilDeployer,
            royaltyReceiver: anvilDeployer,
            lzEndpoint: address(0), // No LZ on local
            paymentToken: address(0),
            backendSigner: anvilDeployer // Use deployer as signer on local
        });

        s_networkConfigs[LOCAL_CHAIN_ID] = config;
        return config;
    }
}
