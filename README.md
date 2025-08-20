# 🌉 Cross-Chain Rebase Token

A decentralized cross-chain rebasing token built on Chainlink CCIP, enabling seamless token transfers between Ethereum Sepolia and zkSync Sepolia while preserving rebasing mechanics.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Configuration](#configuration)
- [Usage](#usage)
- [Reference](#reference)
- [Testing](#testing)
- [Contributing](#contributing)

## 🔍 Overview

This project extends Chainlink's Cross-Chain Interoperability Protocol (CCIP) with rebasing token logic, allowing tokens to maintain their rebase functionality across different blockchain networks. The system supports bidirectional transfers between Ethereum Sepolia and zkSync Sepolia testnets.

## 🏗️ Architecture

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│         Ethereum Sepolia        │      │         zkSync Sepolia          │
│                                 │      │                                 │
│  ┌─────────────────┐            │      │            ┌─────────────────┐  │
│  │   RebaseToken   │            │      │            │   RebaseToken   │  │
│  └─────────┬───────┘            │      │            └───────┬─────────┘  │
│            │                    │      │                    │            │
│  ┌─────────▼───────┐            │      │            ┌───────▼─────────┐  │
│  │ RebaseTokenPool │            │      │            │ RebaseTokenPool │  │
│  └─────────┬───────┘            │      │            └───────┬─────────┘  │
│            │                    │      │                    │            │
│      ┌─────▼─────┐              │      │              ┌─────▼─────┐      │
│      │CCIP Router├──────────────┼──────┼──────────────┤CCIP Router│      │
│      └───────────┘              │      │              └───────────┘      │
│                                 │      │                                 │
└─────────────────────────────────┘      └─────────────────────────────────┘
                                │                   │
                                └─── Chainlink ────┘
                                     Network
```

### Core Components

- **RebaseToken**: ERC20 token with automated supply adjustment (rebasing) functionality
- **RebaseTokenPool**: CCIP bridge adapter that handles cross-chain mint/burn operations
- **Vault**: Secure contract with mint/burn authority for token management
- **Chainlink CCIP**: Provides secure cross-chain message and token delivery

## ✨ Features

- 🔄 **Rebasing Logic**: Automatic token supply adjustments preserved across chains
- 🌐 **Cross-Chain Compatibility**: Seamless transfers between Ethereum and zkSync
- 🔒 **Security**: Built on Chainlink's battle-tested CCIP infrastructure
- ⚡ **Efficient**: Optimized for gas costs and transaction speed
- 🛡️ **Access Control**: Role-based permissions for minting and burning

## 📋 Prerequisites

Before deploying, ensure you have:

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Private key with testnet ETH on both chains
- LINK tokens for CCIP fees
- RPC URLs for both networks

### Environment Setup

Create a `.env` file:

```bash
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_key
ZKSYNC_SEPOLIA_RPC_URL=https://sepolia.era.zksync.dev
```

## 🚀 Deployment

### Step 1: Deploy Core Contracts

Deploy the token, pool, and vault contracts on both chains.

**On Ethereum Sepolia:**
```bash
forge script script/Deployer.s.sol:TokenAndPoolDeployer \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Deploy Vault (use RebaseToken address from previous step):**
```bash
forge script script/Deployer.s.sol:VaultDeployer \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --sig "run(address)" <REBASE_TOKEN_ADDRESS>
```

**Repeat the same process on zkSync Sepolia** with `$ZKSYNC_SEPOLIA_RPC_URL`.

### Step 2: Configure Cross-Chain Pools

Connect the pools on both chains to enable cross-chain communication.

**Configure Sepolia → zkSync:**
```bash
forge script script/ConfigurePool.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  <LOCAL_POOL_ADDRESS> \
  6890753640027530172 \
  <REMOTE_POOL_ADDRESS> \
  <REMOTE_TOKEN_ADDRESS> \
  true 1000000000000000000000 100000000000000000000 \
  true 1000000000000000000000 100000000000000000000
```

**Configure zkSync → Sepolia:**
```bash
forge script script/ConfigurePool.s.sol \
  --rpc-url $ZKSYNC_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  <LOCAL_POOL_ADDRESS> \
  16015286601757825753 \
  <REMOTE_POOL_ADDRESS> \
  <REMOTE_TOKEN_ADDRESS> \
  true 1000000000000000000000 100000000000000000000 \
  true 1000000000000000000000 100000000000000000000
```

### Step 3: Fund with LINK

CCIP requires LINK tokens to pay for cross-chain fees.

- **Sepolia LINK Faucet**: [https://faucets.chain.link/](https://faucets.chain.link/)
- **zkSync Sepolia LINK**: Bridge from Sepolia or use available faucets

Send LINK tokens to your deployed Router contracts.

## 💫 Usage

### Bridging Tokens

Transfer 100 RBT from Sepolia to zkSync Sepolia:

```bash
forge script script/BridgeTokens.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --sig "run(address,uint64,address,uint256,address,address)" \
  <RECIPIENT_ADDRESS> \
  6890753640027530172 \
  <LOCAL_TOKEN_ADDRESS> \
  100000000000000000000 \
  <LINK_TOKEN_ADDRESS> \
  <ROUTER_ADDRESS>
```

### Bridge Flow Diagram

```
┌─────────────┐    approve     ┌──────────────────┐
│ User Wallet ├───────────────►│  Sepolia Router  │
└─────┬───────┘                └────────┬─────────┘
      │                                 │
      │ ccipSend(amount, fee)           │
      └─────────────────────────────────┘
                      │
                      ▼
            ┌─────────────────┐
            │ Chainlink CCIP  │
            └─────────┬───────┘
                      │
                      ▼
            ┌─────────────────┐    mint    ┌──────────────┐
            │  zkSync Router  ├───────────►│ User Wallet  │
            └─────────────────┘            │ (zkSync)     │
                                          └──────────────┘
```

## 📖 Reference

### Network Information

| Chain | Router Address | LINK Token | Chain Selector |
|-------|---------------|------------|----------------|
| **Ethereum Sepolia** | `0xD0daae2231E9CB96b94C8512223533293C3693Bf` | `0x779877A7B0D9E8603169DdbD7836e478b4624789` | `16015286601757825753` |
| **zkSync Sepolia** | `0x2a7a9bE27A97F6b63a1d9C425B474E9f7706a32A` | `0xFe9f969faf8a0f2C5D9F91A58c7a4C15a0B4F53f` | `6890753640027530172` |

### Contract Addresses

After deployment, update this section with your deployed contract addresses:

```
// Ethereum Sepolia
RebaseToken: 0x...
RebaseTokenPool: 0x...
Vault: 0x...

// zkSync Sepolia  
RebaseToken: 0x...
RebaseTokenPool: 0x...
Vault: 0x...
```

## 🧪 Testing

Run the test suite:

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test file
forge test --match-path test/RebaseToken.t.sol
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This project is for educational and testing purposes only. The contracts are deployed on testnets and should not be used with real assets without proper auditing and security reviews.

---

**Built with ❤️ using Chainlink CCIP and Foundry**
