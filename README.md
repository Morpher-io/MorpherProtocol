# Introduction
This is the repository for the core Morpher smart contract components of https://morpher.com

Morpher Smart Contracts are a collection of solidity files for on-chain transactions to invest into different asset classes, such as Stocks, Commodities, Forex, but also into Unique Markets like Watches, Shoes and Football. 😳

![](https://img.shields.io/github/last-commit/Morpher-io/MorpherProtocol) ![](https://img.shields.io/github/license/Morpher-io/MorpherProtocol)

---

Morpher rebuilds financial markets from the ground up on EVM based Blockchains. All in the pursuit of the perfect trading experience.

[![Image of Morpher](./docs/laptop_phone_shot.3303f142.webp)](https://morpher.com)

# Audit

Morpher Smart Contracts are fully and regularly audited. 🙌

 * Audited by Solidified on April 12, 2021. [Full Report](./docs/solidified-audit-12.04.2021.pdf)
 * Audited by Capacity on April 20, 2020. [Full Report](./docs/Capacity-MorpherAudit2Result.pdf)


# Getting Started

## Prerequisites
* Git, Foundry, NodeJs

## Foundry and Truffle in the same projects

We migrated all the functionality from Truffle to Foundry. There is no Hardhat, Truffle or anything else necessary, just Foundry. However, the contract upgrade helper which are checking storage slots for proxy upgrades are running those with nodejs, hence NodeJs is required.

## 1. Clone the Repository

```
git clone https://github.com/Morpher-io/MorpherProtocol.git
cd MorpherProtocol
git checkout account-abstraction
git submodule update --init --recursive
```

## 2. How to run the Tests
Tests are implemented using [Foundry](https://book.getfoundry.sh).

Run the following commands to start the test suite. 😎
* Run `forge test` to run the tests

If you want to see exactly what assertions are being made, you can take a look at the `tests` folder. Tests can also be executed using `forge test -vvv` for a verbose debug output.

## Local Dev Environment

There is a setup for a local development environment. This will:

1. Start anvil with a Polygon Mainnet Fork
2. Download the old sources from the polygonscan block explorer
3. Override Storage slots for Proxy Admins, as well as AccessControl Roles with local Addresses
4. Run the deployment script which checks for storage slot errors and deploys the contracts

`./helpers/chainfork/start.sh`


# Smart Contract Components

There are several components playing together, these are here described in more detail in order of their importance.

Also, there are two versions of the Morpher Protocol. One with Proxies meant for deployment on l2 public chains, and another, older one, without Proxies. On the Morpher Production Sidechain, as well as the Ethereum Mainchain, both versions are mixed, as the state was previously stored in MorpherState, but the Bridge was updated.

Polygon contains OpenZeppelin v0.4 proxies. There are currently no intentions to deploy the Protocol to any other chain.

## MorpherAccessControl.sol

This contract was introduced in the proxied contracts to manage access controls to the Morpher Contracts Ecosystem. The roles are defined in the respective Contracts, but can be summarized as follows:

* **MINTER_ROLE**: Is allowed to mint tokens, usually only given to other smart contracts. E.g. TradeEngine can mint, staking can mint, the faucet (on dev only) can mint
* **BURNER_ROLE**: Same as minterrole, just for burning
* **PAUSER_ROLE**: Can pause any mint/burn/transfer. Effectively pauses the whole protocol. Is assigned to the owner.
* **SIDECHAINOPERATOR_ROLE**: Is updating the Merkle Root, as well as triggers withdrawal functionality. (deprecated on sunsetting the morpher sidechain)
* **ADMINISTRATOR_ROLE**: Can do market delistings, administrative liquidations, update the interest rate etc.
* ORACLEOPERATOR_ROLE: Is responsible for the callback handling from the oracle
* STAKINGADMIN_ROLE: Can do all the adminstrative actions regarding the staking, staking rewards, staking interest rates.
* GOVERNANCE_ROLE: Current not in use, will be superseeded by a proper voting based governance.
* TRANSFER_ROLE: Regulatory role for chains which need a token transfer restriction to allow only certain addresses to transfer Tokens. E.g. on Sidechain it wasn't possible to transfer tokens, only for specific contracts or specific actions, such as account migrations.
* ORACLE_ROLE: Only the Oracle (contract) is allowed to kick of position creation in the TradeEngine.
* POSITIONADMIN_ROLE: The admin contract can modify positions, such as for market migrations (migrating a market from one symbol to another) or during migration of the permissioned private sidechain to the public blockchain.
* USERBLOCKINGADMIN_ROLE: Regulatory role for blocking users from Trading.
* POLYGONMINTER_ROLE: Role that was once assigned to the Polygon Bridge for depositing/withdrawing tokens. Currently not in use, because polygon does not support upgradeable contracts or dynamic role assignments. Might be in use for other bridges later on.

## MorpherState.sol

It holds a pointer to the other contracts. The State does nothing substantial other than being a focal point for managing contract addresses in the MorpherProtocol space. All the actual information is stored on the proxied contracts themselves (Tokens in MorpherToken, Positions in TradeEngine, etc...)

### Non-Proxy Version (deprecated)

This smart contract is _the brain_ of what happens with users, balances, trading and governance. It is the central point which stores balances for each user. It also stores the addresses of other smart contracts, such as the ERC20 token, the bridge or the governance functionality.

## MorpherToken.sol

Its an ERC20 Token, that can be Minted and burned, as well as transferred. It's derived from OpenZeppelin Tokens. It's upgradeable. It also can do Permit via EIP712 Signature Scheme. The hashed version is 1, the hashed name is MorpherToken.

### Non-Proxy Version (deprecated) 

It is the ERC20 Compatible token for Morpher. All the balances are stored in MorpherState.sol, it's just the interface. It can do allowance, but not Permits.


## MorpherTradeEngine.sol

This is the contract that processes and stores orders. The orders can only be given by another entity with an ORACLE_ROLE. Usually this is the Oracle Contract, a smart contract that is the trusted entity taking prices from outside into the sandboxed blockchain.


## MorpherBridge.sol (deprecated, since sidechain is sunset)

Morpher Bridge takes care of bridging functionality from Main-Chain to Side-Chain and vice versa. It contains functionality to burn tokens upon deposit on the main-chain and credit (or mint) tokens on the side-chain. It can also take the merkle-proofs from the side-chain and let you withdraw tokens on the main-chain. 

If side chain operator doesn't write a merkle root hash to main chain for more than 72 hours positions and balaces from side chain can be transferred to main chain.

## MorpherGovernance.sol

Every user able and willig to lock up sufficient token can become a validator of the Morpher protocol. Validators function similiar to a board of directors and vote on the protocol Administrator and the Oracle contract.

## MorpherAirdrop.sol

Holds the Airdrop Token balance on contract address. AirdropAdmin can authorize addresses to receive airdrop. Users have to claim their airdrop actively or Admin initiates transfer.

## MorpherEscrow.sol

Escrow contract to safely store and release the token allocated to Morpher at protocol inception.

## MorpherOracle.sol

The oracle initates a new trade by calling trade engine and requesting a new orderId. An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked for a market/user and return the information via the callback function. Since calling the callback function requires gas, the user must send a fixed amount of Ether when creating their order.

## Important Functionality

MorpherState, by default, doesn't let anyone transfer tokens. This has to be enabled, but is disabled by default. By calling the following functions the access to transfers, minting, burning and creating positions will be enabled:

```
grantAccess(morpherTokenAddress)
grantAccess(morpherTradeEngineAddress)
grantAccess(morpherBridgeAddress)
grantAccess(morpherGovernanceAddress)
```

To let a sidechain operator set the amount of tokens on a sidechain, it has to be set by the owner initially:
```
setSideChainOperator(sideChainOperatorAddress)
```

For sidechain operations (only relevant on sidechain) some transfers need to be enabled:
```
enableTransfers(addressOfDeployer)
enableTransfers(morpherAirdropAddress)
```

Initially the governance contract did not vote on an administrator or oracle yet. To have an Admin or Oracle until there is a vote in the governance contract two addresses need to be set:
```
setGovernanceContract(addressOfDeployer)
setAdministrator(addressOfDeployer)
```

To set the protocol contracts in state, the following functions need to be called:

```
setTokenContract(morpherTokenAddress)
setMorpherBridge(bridgeAddress)
setOracleContract(oracleAddress)
```

To enable "CRYPTO_BTC" and "CRYPTO_ETH" as markets for testing purposes;
```
activateMarket(0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9)
activateMarket(0x5376ff169a3705b2003892fe730060ee74ec83e5701da29318221aa782271779)
```

To set the governance properly _on main chain only_:
```
setGovernanceContract(morpherGovernanceAddress)
```

And to transfer the ownership, potentially to a 0x0 address:

```
transferOwnership(ownerAddress)
```

# Deployed Contracts

The Smart Contracts are deployed on the Ethereum Mainnet and on the Morpher Sidechain, as well as Polygon.

Mainchain and Sidechain contains a mix of Proxied and non-proxied contracts. To understand which ones are which, please consult the [Master-Branch Readme](https://github.com/Morpher-io/MorpherProtocol) which gives an overview

Polygon and all Test-Networks contains exclusively the Proxied contracts. Run:

`truffle dashboard` to connect to MetaMask and select the right network. 
Then run `truffle exec ./helpers/printAddresses.js --network dashboard` to print the addresses.

At the time of writing, these are the addresses for Polygon:

```
ChainID : 137
MorpherAccessControl : 0x139950831d8338487db6807c6FdAeD1827726dF2
MorpherAdmin : NO NETWORK DETECTED
MorpherAdministratorProxy : NO NETWORK DETECTED
MorpherAirdrop : NO NETWORK DETECTED
MorpherBridge : 0xE409f27e977E6bC10cc0a064eD3004F78A40A648
MorpherFaucet : NO NETWORK DETECTED
MorpherGovernance : NO NETWORK DETECTED
MorpherMintingLimiter : 0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb
MorpherOracle : 0x21Fd95b46FC655BfF75a8E74267Cfdc7efEBdb6A
MorpherStaking : 0x0Fc936d3008d08F065BfD37FCAF7aa8515525417
MorpherState : 0x1ce1efda5d52dE421BD3BC1CCc85977D7a0a0F1e
MorpherToken : 0x65C9e3289e5949134759119DBc9F862E8d6F2fBE
MorpherTradeEngine : 0x005cb9Ad7C713bfF25ED07F3d9e1C3945e543cd5
MorpherUserBlocking : 0x92Ea01229335854000dc648Fcf4Ea2931A78c363
MorpherDeprecatedTokenMapper : NO NETWORK DETECTED
```
