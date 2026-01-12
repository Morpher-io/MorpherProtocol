#!/bin/bash
set -e

# ----------------------------------------------------------------------------------
# Delist Markets Script
#
# This script reads market hashes from a CSV file and calls delistMarket on the
# MorpherOracle contract for each market. The delistMarket function closes all
# open positions for that market.
#
# IMPORTANT: This script must be run by an account that has Administrator role
# on the sidechain (controlled by MorpherState.getAdministrator()).
#
# Prerequisites:
# - cast installed (from foundry)
# - Environment variables set (see below)
# - CSV file with market hashes at scripts/finalizeMigration/market-hashes.csv
#
# Required Environment Variables:
# - SIDECHAIN_RPC_URL: RPC endpoint for the sidechain
# - ADMIN_PRIVATE_KEY: Private key of the administrator account
#
# Usage:
#   export SIDECHAIN_RPC_URL="your-rpc-url"
#   export ADMIN_PRIVATE_KEY="your-private-key"
#   ./delist-markets.sh
#
# Or to process a specific CSV:
#   ./delist-markets.sh /path/to/market-hashes.csv
# ----------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sidechain addresses from docs/addressesAndRoles.json
MORPHER_ORACLE="0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb"
MORPHER_STATE="0xB4881186b9E52F8BD6EC5F19708450cE57b24370"

# CSV file path (default to script directory)
CSV_FILE="${1:-$SCRIPT_DIR/market-hashes.csv}"

echo "=== Delist Markets Script ==="
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

# Check CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    echo "Error: CSV file not found at $CSV_FILE"
    exit 1
fi

# Get admin address from private key
ADMIN_ADDRESS=$(cast wallet address --private-key $ADMIN_PRIVATE_KEY)
echo "Admin Address: $ADMIN_ADDRESS"

# Verify admin is the administrator
CURRENT_ADMIN=$(cast call $MORPHER_STATE "getAdministrator()(address)" --rpc-url $SIDECHAIN_RPC_URL)
echo "Current State Administrator: $CURRENT_ADMIN"

# Case-insensitive comparison (compatible with Bash 3.x on macOS)
ADMIN_LOWER=$(echo "$ADMIN_ADDRESS" | tr '[:upper:]' '[:lower:]')
CURRENT_LOWER=$(echo "$CURRENT_ADMIN" | tr '[:upper:]' '[:lower:]')
if [ "$ADMIN_LOWER" != "$CURRENT_LOWER" ]; then
    echo "Warning: Your address is not the current administrator!"
    echo "You need to be the administrator to delist markets."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "Reading markets from: $CSV_FILE"
echo ""

# Count markets
MARKET_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l | tr -d ' ')
echo "Found $MARKET_COUNT markets to delist"
echo ""

# Process each market
PROCESSED=0
FAILED=0

while IFS=',' read -r market_id hash; do
    # Skip header row
    if [ "$market_id" == "\"market_id\"" ] || [ "$market_id" == "market_id" ]; then
        continue
    fi

    # Remove quotes if present
    market_id=$(echo "$market_id" | tr -d '"')
    hash=$(echo "$hash" | tr -d '"' | tr -d '\r')

    echo "Processing: $market_id ($hash)"

    # Check if market is active
    IS_ACTIVE=$(cast call $MORPHER_STATE "getMarketActive(bytes32)(bool)" $hash --rpc-url $SIDECHAIN_RPC_URL 2>/dev/null || echo "error")

    if [ "$IS_ACTIVE" == "false" ]; then
        echo "  Market already inactive, skipping"
        continue
    fi

    if [ "$IS_ACTIVE" == "error" ]; then
        echo "  Error checking market status, skipping"
        ((FAILED++))
        continue
    fi

    # Call delistMarket with _startFromScratch = true
    echo "  Calling delistMarket..."

    # Keep calling until complete (the function may need multiple calls for large markets)
    COMPLETE=false
    ATTEMPTS=0
    MAX_ATTEMPTS=10

    while [ "$COMPLETE" == "false" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        ((ATTEMPTS++))

        # First call with startFromScratch=true, subsequent calls with false
        if [ $ATTEMPTS -eq 1 ]; then
            START_FROM_SCRATCH="true"
        else
            START_FROM_SCRATCH="false"
        fi

        # Gas limit set to 8M to avoid sidechain bug where >25M causes stuck transactions
        # Using --legacy for non-EIP1559 chain and --gas-price 1 for minimal cost
        TX_RESULT_RAW=$(cast send $MORPHER_ORACLE \
            "delistMarket(bytes32,bool)" \
            $hash \
            $START_FROM_SCRATCH \
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
        else
            echo "  Raw output: $TX_RESULT_RAW"
            TX_STATUS="error"
        fi

        if [ "$TX_STATUS" != "0x1" ]; then
            echo "  Transaction failed on attempt $ATTEMPTS"
            if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
                echo "  Max attempts reached, moving to next market"
                ((FAILED++))
                break
            fi
            continue
        fi

        # Check logs for DelistMarketComplete or DelistMarketIncomplete
        TX_HASH=$(echo "$TX_RESULT" | jq -r '.transactionHash')

        # Get transaction receipt to check logs
        RECEIPT=$(cast receipt $TX_HASH --rpc-url $SIDECHAIN_RPC_URL --json)

        # Check for DelistMarketComplete event (topic0)
        # DelistMarketComplete(bytes32): keccak256 = 0x...
        LOGS=$(echo "$RECEIPT" | jq -r '.logs')

        # Simple check: if DelistMarketIncomplete is in logs, we need to continue
        # DelistMarketIncomplete signature: keccak256("DelistMarketIncomplete(bytes32,uint256)")
        INCOMPLETE_TOPIC="0x$(cast keccak "DelistMarketIncomplete(bytes32,uint256)" | cut -c3-)"
        COMPLETE_TOPIC="0x$(cast keccak "DelistMarketComplete(bytes32)" | cut -c3-)"

        if echo "$LOGS" | grep -q "$COMPLETE_TOPIC"; then
            COMPLETE=true
            echo "  Delisting complete (attempt $ATTEMPTS)"
        elif echo "$LOGS" | grep -q "$INCOMPLETE_TOPIC"; then
            echo "  Delisting incomplete, continuing... (attempt $ATTEMPTS)"
            # Sleep between delist attempts to allow oracle callbacks
            echo "  Waiting 3 seconds before next attempt..."
            sleep 3
        else
            # No recognizable event, assume complete
            COMPLETE=true
            echo "  Delisting finished (attempt $ATTEMPTS)"
        fi
    done

    if [ "$COMPLETE" == "true" ]; then
        # Wait for oracle callbacks to settle positions (async process)
        echo "  Waiting for oracle callbacks to settle..."
        sleep 5

        # Check if all positions are actually closed by checking getMaxMappingIndex
        echo "  Checking if all positions are closed..."
        MAX_WAIT_ATTEMPTS=10
        POSITIONS_CLOSED=false

        for (( wait_i=1; wait_i<=MAX_WAIT_ATTEMPTS; wait_i++ )); do
            EXPOSURE_COUNT=$(cast call $MORPHER_STATE \
                "getMaxMappingIndex(bytes32)(uint256)" \
                $hash \
                --rpc-url $SIDECHAIN_RPC_URL 2>/dev/null) || EXPOSURE_COUNT="error"

            # Remove any leading zeros and convert to number
            EXPOSURE_COUNT=$(echo "$EXPOSURE_COUNT" | sed 's/^0*//' | sed 's/^$/0/')

            if [ "$EXPOSURE_COUNT" == "0" ] || [ "$EXPOSURE_COUNT" == "" ]; then
                POSITIONS_CLOSED=true
                echo "  All positions closed (exposure count: 0)"
                break
            else
                echo "  Still have $EXPOSURE_COUNT positions, waiting... (attempt $wait_i/$MAX_WAIT_ATTEMPTS)"
                sleep 3
            fi
        done

        if [ "$POSITIONS_CLOSED" == "false" ]; then
            echo "  Warning: Positions may not be fully closed yet (exposure: $EXPOSURE_COUNT)"
            echo "  Proceeding with deactivation anyway..."
        fi

        # Deactivate the market in MorpherState
        echo "  Deactivating market..."
        DEACTIVATE_RESULT=$(cast send $MORPHER_STATE \
            "deActivateMarket(bytes32)" \
            $hash \
            --private-key $ADMIN_PRIVATE_KEY \
            --rpc-url $SIDECHAIN_RPC_URL \
            --gas-limit 8000000 \
            --legacy \
            --gas-price 1 \
            --json 2>&1) || true

        # Check if result is valid JSON and extract status
        if echo "$DEACTIVATE_RESULT" | jq -e . >/dev/null 2>&1; then
            DEACTIVATE_STATUS=$(echo "$DEACTIVATE_RESULT" | jq -r '.status // "error"')
        else
            DEACTIVATE_STATUS="error"
        fi

        if [ "$DEACTIVATE_STATUS" == "0x1" ]; then
            echo "  Market deactivated successfully"
            ((PROCESSED++))
        else
            echo "  Warning: Failed to deactivate market (positions were still closed)"
            echo "  Response: $DEACTIVATE_RESULT"
            ((PROCESSED++))
        fi
    fi

    # Sleep before processing next market
    echo "  Waiting 3 seconds before next market..."
    sleep 3
    echo ""

done < "$CSV_FILE"

echo "=== Summary ==="
echo "Markets processed successfully: $PROCESSED"
echo "Markets failed: $FAILED"
echo ""
echo "Done!"
