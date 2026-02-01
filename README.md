# Intentra: Hybrid DeFi Execution

**Intentra** is a hybrid DeFi execution system designed to bridge the gap between off-chain efficiency and on-chain reliability. By combining **Yellow Network RFQ (Request-for-Quote)** settlement with **Uniswap v4 AMM liquidity**, Intentra ensures that traders get the best possible prices without the risk of failed execution.

Our signature **"Fair Fill"** mechanism simplifies chain abstraction by providing a guaranteed fallback: if a market maker fails to deliver, the system automatically routes the intent to on-chain liquidity.

---

## 🚀 Key Features

* **Hybrid Execution:** Off-chain speed via RFQ + On-chain reliability via Uniswap v4.
* **Fair Fill Mechanism:** Guaranteed settlement even if solvers/market makers flake.
* **Chain Abstraction:** Simplifies complex cross-chain intents into a single user flow.

---

## 🛠 Getting Started

### 1. Build & Deploy Contracts

Navigate to the EVM contracts directory to compile and deploy the intent channel using Foundry.

```bash
cd packages/contracts/evm
forge build
forge script script/RunDemo.s.sol:RunDemo --rpc-url $RPC_URL --broadcast

```

### 2. Configure Environment

Create a `.env` file or export the following variables to your terminal:

```bash
export RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your_key
export PRIVATE_KEY=0xYOUR_USER_PRIVATE_KEY
export MAKER_PRIVATE_KEY=0xYOUR_MAKER_PRIVATE_KEY

```

### 3. Run the Watcher

Start the Intentra SDK watcher to monitor and execute intents:

```bash
RPC_URL=$RPC_URL INTENT_CHANNEL=0xYOUR_DEPLOYED_ADDRESS node packages/sdk/dist/cli/watch.js

```

---

## 🏗 System Architecture

Intentra operates on a tiered execution logic:

1. **RFQ Phase:** Solvers compete to provide the best price off-chain.
2. **Verification:** The system checks if the solver can fulfill the intent.
3. **Fallback (The "Fair Fill"):** If the solver fails, the intent is automatically filled via Uniswap v4 liquidity pools.

