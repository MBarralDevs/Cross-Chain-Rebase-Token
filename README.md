🌉 Cross-Chain Rebase Token (Sepolia ↔ zkSync Sepolia)

This project extends Chainlink CCIP with rebasing token logic that can flow seamlessly across chains.
Below is a high-level view of the moving pieces:

🔧 Architecture Overview

      ┌────────────────────────────┐
      │ Ethereum Sepolia           │
      │                            │
      │  [RebaseToken]             │
      │       │                    │
      │  [RebaseTokenPool]         │
      │       │                    │
      │   CCIP Router ─────────────┼─────▶ Chainlink Network
      │                            │
      └────────────────────────────┘

      ┌────────────────────────────┐
      │ zkSync Sepolia             │
      │                            │
      │  [RebaseToken]             │
      │       │                    │
      │  [RebaseTokenPool]         │
      │       │                    │
      │   CCIP Router ◀────────────┼───── Chainlink Network
      │                            │
      └────────────────────────────┘


- RebaseToken → ERC20 with supply rebasing

- RebaseTokenPool → CCIP bridge adapter for mint/burn on cross-chain transfer

- Vault → contracts that need mint/burn authority

- Chainlink CCIP → ensures secure delivery of tokens & messages

## ⚙️ Deployment Workflow
### Step 1 — Deploy Token + Pool + Vault

On each chain:
```
forge script script/Deployer.s.sol:TokenAndPoolDeployer \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```
```
forge script script/Deployer.s.sol:VaultDeployer \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast \
  --sig "run(address)" <rebaseTokenAddress>
```


### Result:

RebaseToken

RebaseTokenPool

Vault (granted mint/burn role)

### Step 2 — Configure Pools

Connect Sepolia ↔ zkSync Sepolia pools with chain selectors:

```
graph TD
  A[Sepolia Pool] -- remotePool=zkSync --> B[zkSync Pool]
  B -- remotePool=Sepolia --> A
```

Script command example (Sepolia → zkSync):

```
forge script script/ConfigurePool.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  <localPool> 6890753640027530172 <remotePool> <remoteToken> \
  true 1000e18 100e18 true 1000e18 100e18
```


Do the reverse on zkSync.

Step 3 — Fund LINK

Every CCIP transfer needs LINK as gas.

Sepolia LINK Faucet

zkSync Sepolia LINK Faucet

Step 4 — Bridge Tokens
```
 [User Wallet] ---approve---> [Sepolia Router]
         │
         └── ccipSend(amount, fee) ──────▶ [Chainlink CCIP] ──────▶ [zkSync Router]
                                                        │
                                                        ▼
                                               [RebaseTokenPool]
                                                        │
                                               [Mint on zkSync]
```


Example bridge script (100 RBT Sepolia → zkSync):

```
forge script script/BridgeTokens.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast \
  --sig "run(address,uint64,address,uint256,address,address)" \
  <recipient> 6890753640027530172 <localToken> 100e18 <linkToken> <router>
```

📌 Reference Addresses
```
Chain	Router	LINK	Selector
Sepolia	0xD0daae2231E9CB96b94C8512223533293C3693Bf	0x779877A7B0D9E8603169DdbD7836e478b4624789	16015286601757825753
zkSync Sepolia	0x2a7a9bE27A97F6b63a1d9C425B474E9f7706a32A	0xFe9f969faf8a0f2C5D9F91A58c7a4C15a0B4F53f	6890753640027530172
```

✅ After bridging, the recipient wallet on zkSync Sepolia receives 100 RBT with rebasing logic preserved.
