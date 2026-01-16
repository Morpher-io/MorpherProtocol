# Morpher Protocol Governance

## Overview

The Morpher Protocol uses on-chain governance to allow MPH token holders to propose and vote on protocol changes. The system is built on OpenZeppelin's Governor contracts (v5) with a custom quorum calculation based on circulating supply.

## Architecture

```
┌──────────────────┐     propose/vote      ┌─────────────────────┐
│                  │ ◄──────────────────── │                     │
│  MorpherGovernor │                       │    Token Holders    │
│                  │ ────────────────────► │   (MPH + delegate)  │
└────────┬─────────┘     voting power      └─────────────────────┘
         │
         │ queue (PROPOSER_ROLE)
         ▼
┌──────────────────────────┐
│                          │
│ MorpherTimelockController│ ◄── 2 day delay
│                          │
└────────┬─────────────────┘
         │
         │ execute (open execution)
         ▼
┌──────────────────────────┐
│   Protocol Contracts     │
│  (Token, State, etc.)    │
│                          │
│  Checks: hasRole(        │
│    ADMINISTRATOR_ROLE,   │
│    msg.sender=Timelock)  │
└──────────────────────────┘
```

## Contracts

### MorpherToken (ERC20Votes)

The MPH token includes OpenZeppelin's `ERC20VotesUpgradeable` extension which enables:

- **Delegation**: Token holders must delegate their voting power (to themselves or others) to participate in governance
- **Checkpoints**: Historical snapshots of voting power at each block
- **Permit**: Gasless delegation via EIP-712 signatures

**Important**: Holding MPH tokens does not automatically grant voting power. Users must call `delegate(address)` to activate their votes.

### MorpherGovernor

Built on OpenZeppelin Governor with the following extensions:
- `GovernorSettingsUpgradeable` - Configurable voting parameters
- `GovernorCountingSimpleUpgradeable` - For/Against/Abstain voting
- `GovernorVotesUpgradeable` - ERC20Votes integration
- `GovernorTimelockControlUpgradeable` - Timelock integration

**Parameters** (configured for Base chain with ~2 second blocks):

| Parameter | Value | Description |
|-----------|-------|-------------|
| Voting Delay | 43,200 blocks (~1 day) | Time before voting starts |
| Voting Period | 302,400 blocks (~7 days) | Duration of voting |
| Proposal Threshold | 10,000,000 MPH | Minimum tokens to create proposal |
| Quorum | 51% of circulating supply | Required participation to pass |

**Quorum Calculation**: Uses `MorpherToken.getCirculatingSupply()` which excludes locked rewards and time-locked tokens from the total supply.

### MorpherTimelockController

Extends OpenZeppelin's `TimelockControllerUpgradeable` with centralized role management via `MorpherAccessControl`.

**Configuration**:
- Minimum delay: 2 days
- Open execution: Anyone can execute ready proposals

**Roles** (managed via MorpherAccessControl):

| Role | Holder | Purpose |
|------|--------|---------|
| PROPOSER_ROLE | Governor | Can schedule operations |
| CANCELLER_ROLE | Governor | Can cancel pending operations |
| EXECUTOR_ROLE | (open) | Anyone can execute ready operations |
| ADMINISTRATOR_ROLE | Timelock | Execute admin functions on protocol |
| PROXYUPDATER_ROLE | Timelock | Upgrade protocol contracts |

## Proposal Lifecycle

### 1. Create Proposal

Anyone with >= 10M MPH (delegated) can create a proposal:

```solidity
governor.propose(
    targets,      // Contract addresses to call
    values,       // ETH values (usually 0)
    calldatas,    // Encoded function calls
    description   // Human-readable description
);
```

### 2. Voting Delay

After creation, there's a ~1 day delay before voting begins. This allows token holders to acquire tokens or change their delegation.

### 3. Voting Period

Token holders vote during the ~7 day voting period:

```solidity
governor.castVote(proposalId, support);
// support: 0 = Against, 1 = For, 2 = Abstain
```

Or with reason:
```solidity
governor.castVoteWithReason(proposalId, support, "My reasoning");
```

### 4. Queue

If the proposal passes (>50% For votes and quorum met), it must be queued in the timelock:

```solidity
governor.queue(targets, values, calldatas, descriptionHash);
```

### 5. Timelock Delay

The proposal waits in the timelock for 2 days. This gives users time to react to upcoming changes.

### 6. Execute

After the timelock delay, anyone can execute the proposal:

```solidity
governor.execute(targets, values, calldatas, descriptionHash);
```

The timelock contract calls the target contracts, which verify `hasRole(ADMINISTRATOR_ROLE, msg.sender)` where msg.sender is the timelock.

## Voting Power

### Activating Voting Power

To participate in governance, delegate your tokens:

```solidity
// Delegate to yourself
morpherToken.delegate(myAddress);

// Or delegate to a representative
morpherToken.delegate(representativeAddress);
```

### Gasless Delegation

Use EIP-712 permit signatures for gasless delegation:

```solidity
morpherToken.delegateBySig(delegatee, nonce, expiry, v, r, s);
```

### Checking Voting Power

```solidity
// Current voting power
morpherToken.getVotes(account);

// Voting power at a specific block (for proposals)
morpherToken.getPastVotes(account, blockNumber);
```

## Tally Integration

We plan to use [Tally](https://www.tally.xyz) as the frontend for governance. Tally provides:

- User-friendly proposal creation and voting interface
- Delegation management
- Proposal analytics and history
- Multi-sig support

**Status**: Not yet deployed. Registration will be done at https://www.tally.xyz/add-a-dao after the governance contracts are deployed to mainnet.

### Tally Compatibility

The MorpherGovernor contract implements the standard OpenZeppelin Governor interface, making it fully compatible with Tally without any custom integration work.

## Security Considerations

1. **Timelock Delay**: 2-day delay allows users to exit before potentially harmful changes
2. **High Quorum**: 51% of circulating supply ensures broad consensus
3. **Proposal Threshold**: 10M MPH prevents spam proposals
4. **Role Separation**: Governor can only propose/cancel; execution is permissionless after delay
5. **Centralized Access Control**: All roles managed via MorpherAccessControl for consistency

## Contract Addresses

*To be populated after deployment*

| Contract | Address |
|----------|---------|
| MorpherToken | |
| MorpherGovernor | |
| MorpherTimelockController | |
| MorpherAccessControl | |
