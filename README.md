# ERC721 Swiss Knife

A production-grade, modular NFT toolkit built with **Foundry** and **Solidity ^0.8.20**. Ships six battle-tested ERC721 variants — from a vanilla mint to cross-chain transfers via LayerZero V2 — all sharing a common base layer with stage-gated minting, on-chain royalties, and a standalone registry architecture.

> **Why "Swiss Knife"?** One codebase, many blades. Pick the variant that fits your drop, plug in the registry, and deploy.

---

## Architecture

```
                          ┌─────────────────────────┐
                          │   MintStageRegistry     │
                          │  (Ownable2Step + Guard)  │
                          │                         │
                          │  - Stage CRUD           │
                          │  - Allowlist mgmt       │
                          │  - GTD / FCFS modes     │
                          │  - Per-user quota       │
                          │  - Time windows         │
                          └────────────┬────────────┘
                                       │ validateAndRecordMint()
                          ┌────────────▼────────────┐
                          │     BaseNFT (ETH)       │
                          │  ERC721AC + Royalties    │
                          │  + OwnableBasic          │
                          └────────────┬────────────┘
              ┌──────────┬─────────────┼─────────────┬──────────────┐
              ▼          ▼             ▼             ▼              ▼
        PreRevealNFT  SecureMintNFT  SoulboundNFT  OmnichainNFT  BaseNFTERC20
        (placeholder  (EIP-712 sig   (transfer     (LayerZero    (ERC20
         → reveal)     anti-bot)      lock)         V2 OApp)      payment)
```

**Key design decisions:**

- **Separation of concerns** — Mint logic lives in an external `MintStageRegistry`, keeping NFT contracts thin and upgradeable-friendly (deploy a new registry, rebind).
- **ERC721AC** (LimitBreak) — Optimised batch minting via ERC721A under the hood, with built-in creator-token royalty enforcement.
- **Composition over inheritance** — The omnichain variant uses `OApp` + `OAppOptionsType3` directly instead of inheriting `ONFT721`, avoiding a 30+ function diamond-inheritance collision between ERC721AC and OpenZeppelin's ERC721.

---

## Contract Variants

| Contract | Payment | Highlight | Use Case |
|---|---|---|---|
| **BaseNFT** | Native ETH | Core mint, airdrop, burn, royalties | Standard PFP / generative drop |
| **PreRevealNFT** | Native ETH | Placeholder URI → one-shot reveal | Mystery / delayed-art drops |
| **SecureMintNFT** | Native ETH | EIP-712 typed-data sigs, per-user nonces, expiry | Anti-bot / captcha-gated mints |
| **SoulboundNFT** | Native ETH | Transfers blocked, burns allowed | Credentials, achievements, POAPs |
| **BaseNFTOmnichain** | Native ETH | LayerZero V2 cross-chain send/receive, IONFT721 | Multi-chain collections |
| **BaseNFTERC20** | ERC20 token | SafeERC20 payments, same stage system | Stablecoin or token-gated mints |
| **SoulboundNFTERC20** | ERC20 token | Soulbound + ERC20 payment | On-chain identity with token payment |

---

## Mint Stage Registry

The `MintStageRegistry` is a standalone, stateful contract that manages the entire minting lifecycle for a single collection:

- **Multi-stage support** — Run allowlist, public, and team mints concurrently or sequentially.
- **GTD vs FCFS** — Guaranteed (allowlist count <= supply) or First-Come-First-Served (120% oversubscription allowed).
- **Per-user quotas** — Enforce max-per-wallet at the stage level.
- **Time windows** — Optional `startTime` / `endTime` per stage.
- **Supply invariant** — Total stage allocations can never exceed the collection's hard cap, enforced on every `addStage` / `updateStage` via a cross-contract read.
- **Reentrancy-safe** — All state-mutating functions are guarded with OpenZeppelin's `ReentrancyGuard`.

---

## Project Structure

```
ERC721-Swiss-Knife/
├── src/
│   ├── Base/
│   │   ├── BaseNFTNativePaymentToken.sol   # Core NFT (ETH)
│   │   └── BaseNFTERC20PaymentToken.sol    # Core NFT (ERC20)
│   ├── Registry/
│   │   └── MintStageRegistry.sol           # Stage management
│   ├── Interface/
│   │   └── IMintStageRegistry.sol
│   ├── PreRevealNFT.sol
│   ├── SecureMintNFT.sol
│   ├── SoulboundNFT.sol
│   └── O721NFT.sol                         # Omnichain (LayerZero V2)
├── script/
│   ├── HelperConfig.s.sol                  # Multi-chain config (Mainnet, Sepolia, Base, Anvil)
│   ├── DeployBaseNFT.s.sol
│   ├── DeployPreRevealNFT.s.sol
│   ├── DeploySecureMintNFT.s.sol
│   ├── DeploySoulboundNFT.s.sol
│   ├── DeployOmnichainNFT.s.sol
│   └── Interactions.s.sol                  # Post-deploy: add stages, allowlists, reveal
├── test/
│   └── unit/
│       ├── BaseNFT.t.sol                   # 18 tests
│       ├── PreRevealNFT.t.sol              # 13 tests
│       ├── SecureMintNFT.t.sol             #  8 tests
│       └── SoulboundNFT.t.sol              #  6 tests
├── Makefile
├── foundry.toml
└── .env.example
```

---

## Security Considerations

| Threat | Mitigation |
|---|---|
| Bot / mempool sniping | `SecureMintNFT`: EIP-712 sigs bound to `msg.sender` + nonce + deadline |
| Replay attacks | Per-user incrementing nonces, signature expiry |
| Metadata front-running | `PreRevealNFT`: placeholder URI until owner-triggered reveal |
| Unauthorized transfers | `SoulboundNFT`: `_beforeTokenTransfers` blocks wallet-to-wallet |
| Reentrancy on registry | `ReentrancyGuard` on all state-mutating functions |
| Supply overflow | Cross-contract cap enforcement on every stage mutation |
| Excess ETH stuck | Automatic refund of overpayment in `_executeMint` |

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Install

```bash
git clone https://github.com/<your-username>/ERC721-Swiss-Knife.git
cd ERC721-Swiss-Knife
forge install
```

### Build

```bash
make build
```

### Test

```bash
make test
```

```
Ran 4 test suites: 45 tests passed, 0 failed, 0 skipped
```

### Deploy (Local)

```bash
# Terminal 1 — start local node
make anvil

# Terminal 2 — deploy
make deploy-base-anvil
```

### Deploy (Sepolia)

```bash
cp .env.example .env
# Fill in SEPOLIA_RPC_URL, ETHERSCAN_API_KEY

make deploy-base-sepolia
```

---

## Deployment Flow

```
1. forge script DeployBaseNFT.s.sol
       │
       ├── new HelperConfig()          → resolves chain-specific addresses
       ├── new MintStageRegistry()     → deployed, owned by deployer
       ├── new BaseNFT(params)         → deployed with registry address
       └── registry.bindCollection()   → permanent one-to-one binding

2. forge script Interactions.s.sol:AddPublicStage
       │
       └── registry.addStage(...)      → FCFS public mint, 30-day window

3. Users call nft.batchMint{value}(stageId, amount)
       │
       ├── nft checks global supply
       ├── registry.validateAndRecordMint() → stage checks + quota
       ├── nft checks payment
       ├── _mint()
       └── refund excess ETH
```

---

## Tech Stack

- **Solidity** ^0.8.20
- **Foundry** (Forge, Anvil, Cast)
- **ERC721A / ERC721AC** — Gas-optimised batch minting (LimitBreak)
- **OpenZeppelin** — Ownable2Step, ERC2981 royalties, ECDSA, EIP-712, ReentrancyGuard, SafeERC20
- **LayerZero V2** — OApp, OAppOptionsType3, ONFT721MsgCodec for cross-chain messaging

---

## License

MIT
