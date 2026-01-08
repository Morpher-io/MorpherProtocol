# Sidechain Migration Finalization

This directory contains scripts and contracts for finalizing the migration from the Morpher plasma sidechain to Base L2. The process involves:

1. Force-closing all open trading positions on all markets
2. Force-unstaking all users' staked tokens
3. Generating a Merkle tree of final balances for self-service migration on Base

## Prerequisites

- Foundry installed (`forge`, `cast`)
- Access to sidechain RPC endpoint
- Administrator private key (must be set as `administrator` in MorpherState)

## Sidechain Contract Addresses

From `docs/addressesAndRoles.json` in the `unproxied-contracts` branch:

| Contract | Address |
|----------|---------|
| MorpherState | `0xB4881186b9E52F8BD6EC5F19708450cE57b24370` |
| MorpherToken | `0xC44628734a9432a3DAA302E11AfbdFa8361424A5` |
| MorpherStaking | `0x318Ea6e12A3e49703666C85eEF372644b4022C49` |
| MorpherOracle | `0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb` |
| MorpherTradeEngine | `0xc4a877Ed48c2727278183E18fd558f4b0c26030A` |
| MorpherUserBlocking | `0x96F9174332F8030A59986C07CdAe51Ba549eBE52` |

**Roles:**
| Role | Address |
|------|---------|
| Owner | `0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762` |
| Administrator | `0xB59b29423e5Aa1E0E2cB8966DC14e553E580314D` |

---

## Migration Steps

### Step 0: Generate New Administrator Account (Optional)

If you want to use a fresh administrator account for the migration:

```bash
# Generate a new wallet
cast wallet new

# Or derive from mnemonic
cast wallet address --mnemonic "your mnemonic here" --mnemonic-index 0
```

Then set the new administrator in MorpherState (must be called by current owner):

```bash
export SIDECHAIN_RPC_URL="your-rpc-url"
export OWNER_PRIVATE_KEY="owner-private-key"
export NEW_ADMIN="new-admin-address"

cast send 0xB4881186b9E52F8BD6EC5F19708450cE57b24370 \
  "setAdministrator(address)" $NEW_ADMIN \
  --private-key $OWNER_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL
```

---

### Step 1: Delist All Markets

Force-close all open positions on all markets using the MorpherOracle's `delistMarket` function.

**Prepare the market-hashes.csv file:**

Place your `market-hashes.csv` in this directory. Format:
```csv
"market_id","hash"
"UCL_CHEL","0x876800e24f83128aaabe8a807ec28f2cb73570d4278ee005de3b27cd7ad4fcdb"
"STOCK_AWK","0x4ca7df2e8565a3db9b668e992c093dfb7e002390eeff1b55513d092611cd350a"
...
```

**Option A: Use the shell script (recommended for CSV input):**

```bash
export SIDECHAIN_RPC_URL="your-rpc-url"
export ADMIN_PRIVATE_KEY="admin-private-key"

./delist-markets.sh
# Or specify a custom CSV path:
./delist-markets.sh /path/to/market-hashes.csv
```

**Option B: Use the Foundry script:**

1. Edit `DelistMarkets.s.sol` and add market hashes to the `setUp()` function
2. Run:

```bash
forge script scripts/finalizeMigration/DelistMarkets.s.sol \
  --rpc-url $SIDECHAIN_RPC_URL \
  --private-key $ADMIN_PRIVATE_KEY \
  --broadcast \
  -vvvv
```

**Notes:**
- The `delistMarket` function may need multiple calls for markets with many positions
- It emits `DelistMarketIncomplete(marketId, processedUntilIndex)` if it stops early due to gas
- Re-run with `_startFromScratch = false` to continue from where it left off
- Once complete, it emits `DelistMarketComplete(marketId)`

**Manual single market delist (if needed):**

```bash
# First call (start from scratch)
cast send 0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb \
  "delistMarket(bytes32,bool)" \
  0x876800e24f83128aaabe8a807ec28f2cb73570d4278ee005de3b27cd7ad4fcdb \
  true \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL

# Continue if incomplete
cast send 0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb \
  "delistMarket(bytes32,bool)" \
  0x876800e24f83128aaabe8a807ec28f2cb73570d4278ee005de3b27cd7ad4fcdb \
  false \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL
```

---

### Step 2: Deploy MorpherStakingUnstakeOnly

Deploy a new staking contract that allows administrators to force-unstake users.

```bash
export SIDECHAIN_RPC_URL="your-rpc-url"
export DEPLOYER_PRIVATE_KEY="deployer-private-key"

forge script scripts/finalizeMigration/DeployStakingUnstakeOnly.s.sol \
  --rpc-url $SIDECHAIN_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  -vvvv
```

**After deployment, note the contract address and run these commands:**

```bash
export STAKING_UNSTAKE_ONLY="deployed-contract-address"
export ADMIN_PRIVATE_KEY="admin-private-key"

# Grant access to the new contract in MorpherState
cast send 0xB4881186b9E52F8BD6EC5F19708450cE57b24370 \
  "grantAccess(address)" $STAKING_UNSTAKE_ONLY \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL

# Enable transfers for the new contract
cast send 0xB4881186b9E52F8BD6EC5F19708450cE57b24370 \
  "enableTransfers(address)" $STAKING_UNSTAKE_ONLY \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL
```

**Optional: Disable old staking contract:**

```bash
# Revoke access from old staking contract
cast send 0xB4881186b9E52F8BD6EC5F19708450cE57b24370 \
  "denyAccess(address)" 0x318Ea6e12A3e49703666C85eEF372644b4022C49 \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL
```

---

### Step 3: Force Unstake All Users

Get the list of users with active stakes and force-unstake them.

**Option A: Use the Foundry script:**

1. Create `staked-users.csv` in this directory with one address per line:
   ```
   0x1234567890123456789012345678901234567890
   0xabcdefabcdefabcdefabcdefabcdefabcdefabcd
   0x9876543210987654321098765432109876543210
   ```

2. (Optional) Run a dry run first to see what will be unstaked:
   ```bash
   forge script scripts/finalizeMigration/AdminUnstakeBatch.s.sol \
     --sig "dryRun()" \
     --rpc-url $SIDECHAIN_RPC_URL \
     -vvvv
   ```

3. Run the actual unstaking:

```bash
export SIDECHAIN_RPC_URL="your-rpc-url"
export ADMIN_PRIVATE_KEY="admin-private-key"
export STAKING_UNSTAKE_ONLY_ADDRESS="deployed-contract-address"

forge script scripts/finalizeMigration/AdminUnstakeBatch.s.sol \
  --rpc-url $SIDECHAIN_RPC_URL \
  --private-key $ADMIN_PRIVATE_KEY \
  --broadcast \
  -vvvv
```

**Option B: Manual unstaking via cast:**

```bash
# Single user
cast send $STAKING_UNSTAKE_ONLY \
  "adminUnstake(address)" "0xUserAddress" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL

# Batch (up to ~50 users per transaction)
cast send $STAKING_UNSTAKE_ONLY \
  "adminUnstakeBatch(address[])" "[0xUser1,0xUser2,0xUser3]" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $SIDECHAIN_RPC_URL
```

**Query user stake info:**

```bash
# Get user's pool shares
cast call $STAKING_UNSTAKE_ONLY \
  "getStake(address)(uint256)" "0xUserAddress" \
  --rpc-url $SIDECHAIN_RPC_URL

# Get user's stake value in tokens
cast call $STAKING_UNSTAKE_ONLY \
  "getStakeValue(address)(uint256)" "0xUserAddress" \
  --rpc-url $SIDECHAIN_RPC_URL

# Get current pool share value
cast call $STAKING_UNSTAKE_ONLY \
  "getCurrentPoolShareValue()(uint256)" \
  --rpc-url $SIDECHAIN_RPC_URL
```

---

### Step 4: Generate Merkle Tree (Placeholder)

**⚠️ This step is not implemented in this directory.**

After all positions are closed and all stakes are unstaked, generate a Merkle tree of final user balances.

The Merkle tree will be used with `MorpherSidechainToBaseMigration.sol` on Base for self-service balance migration via `migrateBalanceSelfService()`.

**Leaf format:**
```solidity
bytes32 balanceHash = keccak256(abi.encodePacked(
    userAddress,
    balance,
    lockedAmount,
    lockDuration,
    lockedRewardAmount
));
```

**TODO:**
- [ ] Query all user balances from the sidechain database
- [ ] Include any locked amounts and lock durations
- [ ] Generate Merkle tree with leaves in the above format
- [ ] Set the Merkle root in the migration contract on Base:
  ```bash
  cast send $MIGRATION_CONTRACT \
    "setFinalBalanceMerkleRoot(bytes32)" $MERKLE_ROOT \
    --private-key $ADMIN_PRIVATE_KEY \
    --rpc-url $BASE_RPC_URL
  ```

---

## Contract: MorpherStakingUnstakeOnly

A minimal staking contract that:
- Reads pool share value from the old staking contract
- Calculates current value including accrued interest
- Allows administrators to force-unstake users (bypassing lockup)
- Supports batch unstaking for efficiency

**Key functions:**
- `getCurrentPoolShareValue()` - Returns the current pool share value
- `adminUnstake(address user)` - Force unstakes a single user
- `adminUnstakeBatch(address[] users)` - Force unstakes multiple users
- `getStake(address)` - Get user's pool shares
- `getStakeValue(address)` - Get user's stake value in tokens

---

## Verification Checklist

After completing the migration steps, verify:

- [ ] All markets show as inactive: `getMarketActive(marketHash) == false`
- [ ] No users have open positions: query `getPosition()` for sample users
- [ ] No users have active stakes: `getStake(user) == 0` for all staking users
- [ ] User balances reflect closed positions + unstaked tokens
- [ ] (On Base) Merkle root is set in migration contract
- [ ] (On Base) Users can successfully call `migrateBalanceSelfService()`

---

## Troubleshooting

**"Function can only be called by the Administrator"**
- Verify your account is set as administrator: `cast call 0xB4881186b9E52F8BD6EC5F19708450cE57b24370 "getAdministrator()(address)"`

**"MorpherState: Only Platform is allowed to execute operation"**
- The new contract needs access: call `grantAccess()` and `enableTransfers()` for it

**"DelistMarketIncomplete" events**
- Re-run `delistMarket` with `_startFromScratch = false` to continue

**Gas estimation errors**
- The sidechain has a bug where specifying >25M gas causes transactions to get stuck
- All scripts use `--gas-limit 8000000` to avoid this issue
- Process in smaller batches if needed

---

## Files in This Directory

| File | Description |
|------|-------------|
| `README.md` | This documentation |
| `MorpherStakingUnstakeOnly.sol` | Contract for admin force-unstaking |
| `DeployStakingUnstakeOnly.s.sol` | Foundry deployment script |
| `DelistMarkets.s.sol` | Foundry script for delisting markets |
| `AdminUnstakeBatch.s.sol` | Foundry script for batch unstaking (reads from CSV) |
| `delist-markets.sh` | Shell script for delisting from CSV |
| `market-hashes.csv` | (You provide) CSV with market IDs and hashes |
| `staked-users.csv` | (You provide) CSV with staked user addresses (one per line) |
