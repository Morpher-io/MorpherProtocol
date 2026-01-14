#!/bin/bash
set -e

# ----------------------------------------------------------------------------------
# Unstake Users Script
#
# This script reads user addresses from a CSV file and calls adminUnstakeBatch on
# the MorpherStakingUnstakeOnly contract to force-unstake users in batches.
#
# Prerequisites:
# - cast installed (from foundry)
# - Environment variables set (see below)
# - CSV file with user addresses at scripts/finalizeMigration/staked-users.csv
#
# Required Environment Variables:
# - SIDECHAIN_RPC_URL: RPC endpoint for the sidechain
# - ADMIN_PRIVATE_KEY: Private key of the administrator account
# - STAKING_UNSTAKE_ONLY_ADDRESS: Address of the deployed MorpherStakingUnstakeOnly contract
#
# Usage:
#   export SIDECHAIN_RPC_URL="your-rpc-url"
#   export ADMIN_PRIVATE_KEY="your-private-key"
#   export STAKING_UNSTAKE_ONLY_ADDRESS="deployed-contract-address"
#   ./unstake-users.sh
#
# Or to process a specific CSV:
#   ./unstake-users.sh /path/to/staked-users.csv
# ----------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CSV file path (default to script directory)
CSV_FILE="${1:-$SCRIPT_DIR/staked-users.csv}"

# Batch size (number of users per transaction)
BATCH_SIZE=50

echo "=== Unstake Users Script ==="
echo ""

# Check required environment variables
if [ -z "$SIDECHAIN_RPC_URL" ]; then
    echo "Error: SIDECHAIN_RPC_URL not set"
    exit 1
fi

if [ -z "$ADMIN_PRIVATE_KEY" ]; then
    echo "Error: ADMIN_PRIVATE_KEY not set"
    exit 1
fi

if [ -z "$STAKING_UNSTAKE_ONLY_ADDRESS" ]; then
    echo "Error: STAKING_UNSTAKE_ONLY_ADDRESS not set"
    exit 1
fi

# Check CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    echo "Error: CSV file not found at $CSV_FILE"
    exit 1
fi

# Get admin address from private key
ADMIN_ADDRESS=$(cast wallet address --private-key $ADMIN_PRIVATE_KEY)
echo "Admin Address: $ADMIN_ADDRESS"
echo "Staking Contract: $STAKING_UNSTAKE_ONLY_ADDRESS"
echo ""

# Get current pool share value
POOL_SHARE_VALUE=$(cast call $STAKING_UNSTAKE_ONLY_ADDRESS \
    "getCurrentPoolShareValue()(uint256)" \
    --rpc-url $SIDECHAIN_RPC_URL 2>/dev/null) || POOL_SHARE_VALUE="error"
echo "Current Pool Share Value: $POOL_SHARE_VALUE"
echo ""

echo "Reading users from: $CSV_FILE"
echo "Batch size: $BATCH_SIZE"
echo ""

# Parse CSV and collect addresses into an array
declare -a ADDRESSES

while IFS=',' read -r address rest; do
    # Skip empty lines
    if [ -z "$address" ]; then
        continue
    fi

    # Remove BOM if present (appears as ï»¿ in some terminals)
    address=$(echo "$address" | sed 's/^\xef\xbb\xbf//' | sed 's/^\xEF\xBB\xBF//')

    # Remove quotes and whitespace
    address=$(echo "$address" | tr -d '"' | tr -d "'" | tr -d ' ' | tr -d '\r')

    # Skip header row (doesn't start with 0x)
    if [[ ! "$address" =~ ^0x ]]; then
        continue
    fi

    # Validate address format (basic check)
    if [[ ${#address} -ne 42 ]]; then
        echo "Warning: Invalid address length, skipping: $address"
        continue
    fi

    ADDRESSES+=("$address")
done < "$CSV_FILE"

TOTAL_USERS=${#ADDRESSES[@]}
echo "Found $TOTAL_USERS users to unstake"
echo ""

if [ $TOTAL_USERS -eq 0 ]; then
    echo "No users to unstake. Check CSV format."
    exit 1
fi

# Calculate number of batches
NUM_BATCHES=$(( (TOTAL_USERS + BATCH_SIZE - 1) / BATCH_SIZE ))
echo "Will process in $NUM_BATCHES batches"
echo ""

# Process in batches
PROCESSED=0
FAILED=0
TOTAL_UNSTAKED=0

for (( batch=0; batch<NUM_BATCHES; batch++ )); do
    START_IDX=$(( batch * BATCH_SIZE ))
    END_IDX=$(( START_IDX + BATCH_SIZE ))
    if [ $END_IDX -gt $TOTAL_USERS ]; then
        END_IDX=$TOTAL_USERS
    fi

    BATCH_NUM=$(( batch + 1 ))
    BATCH_COUNT=$(( END_IDX - START_IDX ))

    echo "=== Batch $BATCH_NUM / $NUM_BATCHES ($BATCH_COUNT users: $((START_IDX + 1))-$END_IDX) ==="

    # Build the address array for this batch
    BATCH_ADDRESSES=""
    for (( i=START_IDX; i<END_IDX; i++ )); do
        if [ -n "$BATCH_ADDRESSES" ]; then
            BATCH_ADDRESSES="$BATCH_ADDRESSES,"
        fi
        BATCH_ADDRESSES="${BATCH_ADDRESSES}${ADDRESSES[$i]}"
    done

    # Format as solidity array: [addr1,addr2,addr3]
    BATCH_ARRAY="[$BATCH_ADDRESSES]"

    echo "  Calling adminUnstakeBatch..."

    # Call the contract
    TX_RESULT_RAW=$(cast send $STAKING_UNSTAKE_ONLY_ADDRESS \
        "adminUnstakeBatch(address[])" \
        "$BATCH_ARRAY" \
        --private-key $ADMIN_PRIVATE_KEY \
        --rpc-url $SIDECHAIN_RPC_URL \
        --gas-limit 8000000 \
        --legacy \
        --gas-price 1 \
        --json 2>&1) || true

    # Extract only the JSON part (line starting with {)
    TX_RESULT=$(echo "$TX_RESULT_RAW" | grep '^{' | head -1)

    # Parse status, handling non-JSON output
    if [ -n "$TX_RESULT" ] && echo "$TX_RESULT" | jq -e . >/dev/null 2>&1; then
        TX_STATUS=$(echo "$TX_RESULT" | jq -r '.status // "error"')
        TX_HASH=$(echo "$TX_RESULT" | jq -r '.transactionHash // "none"')
        GAS_USED=$(echo "$TX_RESULT" | jq -r '.gasUsed // "none"')
    else
        echo "  Error: Invalid response from cast send"
        echo "  Raw output: $TX_RESULT_RAW"
        TX_STATUS="error"
        TX_HASH="none"
        GAS_USED="none"
    fi

    if [ "$TX_STATUS" == "0x1" ]; then
        echo "  Success! TX: $TX_HASH"
        echo "  Gas used: $GAS_USED"
        PROCESSED=$(( PROCESSED + BATCH_COUNT ))

        # Try to get the return value (total amount unstaked) from logs
        # The AdminUnstaked events contain the amounts
        RECEIPT=$(cast receipt $TX_HASH --rpc-url $SIDECHAIN_RPC_URL --json 2>/dev/null) || true
        if [ -n "$RECEIPT" ]; then
            # Count AdminUnstaked events
            EVENT_COUNT=$(echo "$RECEIPT" | jq '.logs | length' 2>/dev/null) || EVENT_COUNT=0
            echo "  Events emitted: $EVENT_COUNT"
        fi
    else
        echo "  Transaction failed!"
        echo "  --- DEBUG INFO ---"
        echo "  TX_STATUS: $TX_STATUS"
        echo "  TX_HASH: $TX_HASH"
        if [ -n "$TX_RESULT" ]; then
            REVERT_REASON=$(echo "$TX_RESULT" | jq -r '.revertReason // empty')
            if [ -n "$REVERT_REASON" ]; then
                echo "  REVERT_REASON: $REVERT_REASON"
            fi
        fi
        echo "  RAW OUTPUT:"
        echo "$TX_RESULT_RAW" | head -20 | sed 's/^/    /'
        echo "  --- END DEBUG ---"
        FAILED=$(( FAILED + BATCH_COUNT ))
    fi

    # Small delay between batches
    if [ $batch -lt $(( NUM_BATCHES - 1 )) ]; then
        echo "  Waiting 2 seconds before next batch..."
        sleep 2
    fi
    echo ""
done

echo "=== Summary ==="
echo "Total users in CSV: $TOTAL_USERS"
echo "Users processed successfully: $PROCESSED"
echo "Users failed: $FAILED"
echo "Batches: $NUM_BATCHES"
echo ""
echo "Done!"
