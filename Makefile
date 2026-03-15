-include .env

.PHONY: all clean build test snapshot format anvil

# ─── Build & Compile ──────────────────────────────────────────────────────────
all: clean build test

build:; forge build
clean:; forge clean
test:; forge test -vvv
snapshot:; forge snapshot
format:; forge fmt

# ─── Local Node ───────────────────────────────────────────────────────────────
anvil:; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# ─── Deploy: BaseNFT ─────────────────────────────────────────────────────────
deploy-base-anvil:
	@forge script script/DeployBaseNFT.s.sol:DeployBaseNFT --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-base-sepolia:
	@forge script script/DeployBaseNFT.s.sol:DeployBaseNFT --rpc-url $(SEPOLIA_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# ─── Deploy: PreRevealNFT ────────────────────────────────────────────────────
deploy-prereveal-anvil:
	@forge script script/DeployPreRevealNFT.s.sol:DeployPreRevealNFT --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-prereveal-sepolia:
	@forge script script/DeployPreRevealNFT.s.sol:DeployPreRevealNFT --rpc-url $(SEPOLIA_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# ─── Deploy: SecureMintNFT ───────────────────────────────────────────────────
deploy-secure-anvil:
	@forge script script/DeploySecureMintNFT.s.sol:DeploySecureMintNFT --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-secure-sepolia:
	@forge script script/DeploySecureMintNFT.s.sol:DeploySecureMintNFT --rpc-url $(SEPOLIA_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# ─── Deploy: SoulboundNFT ────────────────────────────────────────────────────
deploy-soulbound-anvil:
	@forge script script/DeploySoulboundNFT.s.sol:DeploySoulboundNFT --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-soulbound-sepolia:
	@forge script script/DeploySoulboundNFT.s.sol:DeploySoulboundNFT --rpc-url $(SEPOLIA_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# ─── Deploy: OmnichainNFT ────────────────────────────────────────────────────
deploy-omnichain-sepolia:
	@forge script script/DeployOmnichainNFT.s.sol:DeployOmnichainNFT --rpc-url $(SEPOLIA_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# ─── Install Dependencies ────────────────────────────────────────────────────
install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install chiru-labs/ERC721A --no-commit
	forge install limitbreak/creator-token-standards --no-commit
