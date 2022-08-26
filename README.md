# Introduction
This is the repository for the core Morpher smart contract components of https://morpher.com

Morpher Smart Contracts are a collection of solidity files for on chain transactions and trustless state recovery from sidechain. 😳

![](https://img.shields.io/david/Morpher-io/MorpherProtocol) ![](https://img.shields.io/github/last-commit/Morpher-io/MorpherProtocol) ![](https://img.shields.io/github/license/Morpher-io/MorpherProtocol)

---

Morpher rebuilds financial markets from the ground up on the Ethereum Blockchain. All in the pursuit of the perfect trading experience.

[![Image of Morpher](./docs/laptop_phone_shot.3303f142.webp)](https://morpher.com)

# Audit

The Non-Proxy versions of Morpher Smart Contracts are fully and regularly audited. 🙌

 * Audited by Solidified on April 12, 2021. [Full Report](./docs/solidified-audit-12.04.2021.pdf)
 * Audited by Capacity on April 20, 2020. [Full Report](./docs/Capacity-MorpherAudit2Result.pdf)

 # Proxied vs Non-Proxied versions

There are two versions of the smart contracts:

## Non Proxied Contracts

Initially MorpherProtocol was written in a non-proxy way using Solidity 0.5 and the Eternal Storage Pattern.

Contracts are residing on [the nonproxy-master Branch](https://github.com/Morpher-io/MorpherProtocol/tree/unproxied-contracts).

### Addresses for Non Proxied Contracts

Updates are barely possible, that's also why the deployments are not managed through truffle artifacts. Addresses are stored in [addressesAndRoles.json](./docs/addressesAndRoles.json).

## Proxied Contracts

Q1/2022 the Contracts were updated to support the following things:

1. Proxied through transparent proxies for updating the contract logic
    
    * No more Eternal Storage Pattern. 
    * Contract storage is now used directly. 
    * Lowered Gas costs and made maintenance easier
    * MorpherState now holds only a Pointer to the Contracts in the Ecosystem, instead of the Storage.

2. Advanced Roles and Access Lists instead of a simple Ownable

    * Allows for more fine-grained access control
    * State having Administrators and Owner roles are not managed through [OpenZeppelin Access Control](https://docs.openzeppelin.com/contracts/4.x/access-control)

3. Usage of Foundry over Truffle for Unit-Testing

    * Usage for Foundry over Truffle for Tests
    * Still maintain the migration functionality from Truffle
    * Run Truffle and Foundry in Parallel

The Proxied Contracts can be found in [the proxy-master Branch](https://github.com/Morpher-io/MorpherProtocol/tree/proxied-contracts).

### Addresses for Proxied Contracts

For proxied contracts the build-artifacts are stored in the branch, they are not deleted. There is a helper function called printAddresses in the helpers directory. 

1. Switch over to the proxied-contracts branch
2. Connect Truffle to MetaMask: `truffle dashboard`
3. Select the right network from MetaMask (e.g. Polygon)
4. Run `truffle exec ./helpers/printAddresses.js --network dashboard`

At the time of writing, these are the addresses for Morpher Sidechain (Chain-ID 21), Mainnet (Chain-ID 1) and Polygon (Chain-ID 137):

```
ChainID : 21
MorpherAccessControl : 0xA8aA5aF33D221F9FF7c75f7b0d88FE77EA821a6b
MorpherAdmin : NO NETWORK DETECTED
MorpherAdministratorProxy : 0xe45B66cc880976135ebc83f1BEafaDE7BD29358d
MorpherAirdrop : 0xbfd0aC3188BaEFF8e3fA67124e948674e2C42af4
MorpherBridge : 0xd4399F4f73A9e84c0A788D582B89F3702b4dA781
MorpherFaucet : NO NETWORK DETECTED
MorpherGovernance : NO NETWORK DETECTED
MorpherMintingLimiter : NO NETWORK DETECTED
MorpherOracle : NO NETWORK DETECTED
MorpherStaking : NO NETWORK DETECTED
MorpherState : 0x47d2B89c88a411Af2f280E7f9e4c580c4E33b118
MorpherToken : 0x1Ea92E8941cf0FbfD302118AaE7c35F8F29eBb07
MorpherTradeEngine : NO NETWORK DETECTED
MorpherUserBlocking : 0x195CaAA6023c03a7C7C1773cA51F95BA8eb4BfF4
MorpherDeprecatedTokenMapper : NO NETWORK DETECTED

ChainID : 1
MorpherAccessControl : 0xD6bFA0868A901BE396b9A294dE78441b240a45b8
MorpherAdmin : NO NETWORK DETECTED
MorpherAdministratorProxy : NO NETWORK DETECTED
MorpherAirdrop : NO NETWORK DETECTED
MorpherBridge : 0x005cb9Ad7C713bfF25ED07F3d9e1C3945e543cd5
MorpherFaucet : NO NETWORK DETECTED
MorpherGovernance : NO NETWORK DETECTED
MorpherMintingLimiter : NO NETWORK DETECTED
MorpherOracle : NO NETWORK DETECTED
MorpherStaking : NO NETWORK DETECTED
MorpherState : 0x88A610554eb712DCD91a47108aE59028B3De6614
MorpherToken : 0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb
MorpherTradeEngine : NO NETWORK DETECTED
MorpherUserBlocking : 0xB2b8B7b23B1C5F329adf0B4e5cB51c668Aa1cce1
MorpherDeprecatedTokenMapper : 0x334643882B849A286E01c386C3e033B1b5c75164

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

# Contracts


## Auxiliary Contracts
MerkleProof.sol: Calculate the Merkle Proof

* Replaced in Proxy Contracts for the [OpenZeppelin Implementation](https://docs.openzeppelin.com/contracts/4.x/api/utils#MerkleProof)

Migrations.sol: Used by Truffle to store migrations on chain

Ownable.sol: Ownable functionality

* Replaced in Proxy Contracts with [OpenZeppelin Access Control](https://docs.openzeppelin.com/contracts/4.x/access-control)

SafeMath.sol: Prevent Integer Overflows/Underflows in Solidity < 0.8

* Removed in Proxied Contracts, since upgraded to Solidity 0.8.x

## Morpher Core Contracts

MorpherAirdrop.sol: Manages the Airdrop functionality. 

* [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherAdmin.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherAdmin.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherAdmin.sol)

MorpherBridge.sol: Functionality to bridge tokens between chains in a trustless way

* [Sidechain: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherBridge.sol)
* [Mainchain: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherBridge.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherBridge.sol)

MorpherOracle.sol: Pricing Oracle Functionality that accepts high frequency price ticks from external trusted data sources

* [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherOracle.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherOracle.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherOracle.sol)

MorpherStaking.sol: Staking functionality for MPH

* [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherStaking.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherStaking.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherStaking.sol)

MorpherState.sol: Storing Data On Chain using the Eternal Storage Pattern (only non-proxied) or pointers to the contract ecosystem (proxied version)

* [Sidechain: Unproxied Version for Eternal Storage](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherState.sol)
* [Sidechain: Proxied Version for Address-Pointers - 0x47d2B89c88a411Af2f280E7f9e4c580c4E33b118](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherState.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherState.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherState.sol)

MorpherToken.sol: ERC20 Interface for the Morpher Token

* [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherToken.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherToken.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherToken.sol)

MorpherTradeEngine.sol: Processing Trades, calculating the position value

* [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherTradeEngine.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherTradeEngine.sol)
* [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherTradeEngine.sol)

## Morpher Auxiliary Contracts

MorpherAccessControl.sol: Access Control based on OpenZeppelin Contracts

* [Sidechain: 0xA8aA5aF33D221F9FF7c75f7b0d88FE77EA821a6b](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherAccessControl.sol)
* [Mainchain: 0xD6bFA0868A901BE396b9A294dE78441b240a45b8](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherAccessControl.sol)
* [Polygon: 0x139950831d8338487db6807c6FdAeD1827726dF2](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherAccessControl.sol)

MorpherAdmin.sol: Administrative functions, such as stockSplit calculations etc. Can only be called from Administrator roles.

* Can be deployed "ad-hoc"

MorpherAdministratorProxy.sol: A middle-layer between State, to bulk-activate Markets. Used for Mainchain where gas prices skyrocket sometimes.

* Deployed "ad-hoc" if necessary.

MorpherEscrow.sol: Used for token release at protocol inception.

* [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherEscrow.sol)
* [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherEscrow.sol)
* Polygon: not deployed

MorpherFaucet.sol: Used as faucet for test-networks and development-networks to get access to MPH without purchasing them.

* Only deployed to test-networks. Sol 0.8 version recommended.

MorpherGovernance.sol: Governance for Mainchain to vote in new Oracles or Administrators 

* No proxied version available, governance will be re-written when necessary

MorpherMintingLimiter.sol: Delays the payout when closing positions when the close amount is above a certain threshold, so it can be investigated for potential platform bugs.

 * [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherMintingLimiter.sol)
 * [Mainchain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherMintingLimiter.sol)
 * [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherMintingLimiter.sol)

MorpherUserBlocking.sol: Allows specific users to be blocked from Trading.

 * [Sidechain: Unproxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/unproxied-contracts/contracts/MorpherUserBlocking.sol)
 * Mainchain: Not Deployed
 * [Polygon: Proxied Version](https://github.com/Morpher-io/MorpherProtocol/blob/proxied-contracts/contracts/MorpherUserBlocking.sol)

## Interfaces

Interfaces are only available in the unproxied-contracts.

IERC20.sol: Interface for the ERC20 Token

IMorpherStaking.sol: Interface for the Staking functionality

IMorpherState.sol: Interface for the State functions

IMorpherToken.sol: Interface for the Morpher Token
