# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MorpherProtocol is a DeFi protocol for synthetic asset trading deployed on EVM blockchains. It enables trading of various asset classes (stocks, commodities, forex, unique markets) without holding the underlying assets.

## Build and Test Commands

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vvv

# Run a specific test file
forge test --match-path tests/MorpherToken.test.sol

# Run a specific test function
forge test --match-test testMint

# Build contracts
forge build

# Deploy all contracts (pass deployment args like --broadcast --rpc-url)
./scripts/deployAll.sh --private-key $PK --rpc-url $RPC --broadcast

# Deploy a single contract
forge script scripts/04-MorpherToken.s.sol --rpc-url $RPC --broadcast

# Local dev environment (starts anvil fork, deploys contracts)
./helpers/chainfork/start.sh
```

## Architecture

### Contract Hierarchy

All core contracts are upgradeable using OpenZeppelin's UUPS proxy pattern. The protocol uses OpenZeppelin v5 for new contracts.

**Central Contracts:**
- `MorpherAccessControl` - RBAC for the entire protocol. All role checks go through this contract.
- `MorpherState` - Registry pointing to all other contract addresses. Acts as the protocol's address book.
- `MorpherToken` - ERC20 token (MPH) with mint/burn capabilities and EIP-712 permit support.

**Trading System:**
- `MorpherTradeEngine` - Core trading logic. Stores positions, processes orders, handles liquidations.
- `MorpherOracle` - Bridge between off-chain price feeds and on-chain execution. Only the oracle can submit prices to TradeEngine.

**Supporting Contracts:**
- `MorpherStaking` - Staking rewards system
- `MorpherMintingLimiter` - Rate limits token minting
- `MorpherInterestRateManager` - Manages historical interest rates
- `MorpherBridge` - Cross-chain bridging (deprecated, sidechain sunset)
- `MorpherAirdrop` - Token distribution
- `MorpherUserBlocking` - Regulatory compliance

### Role System

Key roles defined in contracts and managed via `MorpherAccessControl`:
- `MINTER_ROLE` / `BURNER_ROLE` - Token mint/burn permissions (granted to TradeEngine, Staking, Bridge)
- `ORACLE_ROLE` - Can submit prices to TradeEngine (granted to MorpherOracle)
- `ORACLEOPERATOR_ROLE` - Can call oracle callback functions
- `ADMINISTRATOR_ROLE` - Administrative functions (market delistings, liquidations)
- `POSITIONADMIN_ROLE` - Can modify positions (for migrations)
- `STAKINGADMIN_ROLE` - Staking configuration

### Key Patterns

1. **State Pointer Pattern**: Contracts get other contract addresses from `MorpherState` rather than storing them directly.

2. **Role-Based Access**: Modifiers check roles via `MorpherAccessControl.hasRole()`.

3. **UUPS Upgrades**: All proxies are UUPS. Upgrade authorization is in the implementation contract.

### Directory Structure

- `contracts/` - Main contract source files
- `contracts/interfaces/` - Interface definitions
- `contracts/libraries/` - Shared libraries
- `tests/` - Foundry test files (use `BaseSetup.sol` for test fixtures)
- `scripts/` - Deployment scripts (numbered for execution order)
- `deployments/` - Deployed contract addresses per chain (JSON files by chain ID)
- `lib/` - Git submodule dependencies

### Deployment

Deployment scripts are numbered and run in order. Each script:
1. Loads existing addresses from `deployments/{chainId}.json`
2. Deploys or upgrades a contract
3. Saves the new address back to the JSON file

Use `scripts/DeploymentUtils.sol` for address management in deployment scripts.

### Precision and Constants

- `PRECISION = 10**8` - Used for leverage calculations
- `DECIMALS = 18` - Token decimals
- Market IDs are `keccak256` hashes of market names (e.g., `keccak256("CRYPTO_BTC")`)

## Workflow Requirements

**Commit after every change**: After completing each logical unit of work (implementing a feature, fixing a bug, refactoring, etc.), use the `git-committer` subagent to create a commit. This ensures every change is captured as a snapshot in git history. Do not batch multiple changes into a single commit - commit frequently to maintain granular history.
