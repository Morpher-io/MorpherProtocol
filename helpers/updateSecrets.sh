#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <environment_name> <chain_id>"
    echo "Example: $0 environment_dev 137"
    exit 1
fi

ENVIRONMENT=$1
CHAIN_ID=$2
DEPLOYMENT_FILE="deployments/${CHAIN_ID}.json"

if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "Error: Deployment file $DEPLOYMENT_FILE does not exist"
    exit 1
fi

# Function to get current secret value as JSON
get_current_secret() {
    local secret_name=$1
    local secret_value
    secret_value=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --query 'SecretString' --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$secret_value"
    else
        echo "{}"
    fi
}

# Read deployment file
DEPLOYMENT_DATA=$(cat "$DEPLOYMENT_FILE")

echo "Will update secret for environment: $ENVIRONMENT using chain ID: $CHAIN_ID"
echo "The following changes will be made:"
echo "----------------------------------------"

# Parse JSON and prepare changes
jq -r 'to_entries[] | select(.value != "0x0" and .value != "0x0000000000000000000000000000000000000000") | @base64' "$DEPLOYMENT_FILE" | while read -r item; do
    decoded=$(echo "$item" | base64 --decode)
    key=$(echo "$decoded" | jq -r '.key')
    value=$(echo "$decoded" | jq -r '.value')
    
    secret_key="${key}_${CHAIN_ID}"
    
    current_json=$(get_current_secret "$ENVIRONMENT")
    current_value=$(echo "$current_json" | jq -r --arg key "$secret_key" '.[$key] // "NOT_SET"' 2>/dev/null || echo "NOT_SET")
    
    if [ "$current_value" = "NOT_SET" ]; then
        echo "New key in secret: $ENVIRONMENT"
        echo "Key: $secret_key"
        echo "Value: $value"
    else
        echo "Update key in secret: $ENVIRONMENT"
        echo "Key: $secret_key"
        echo "Old value: $current_value"
        echo "New value: $value"
    fi
    echo "----------------------------------------"
done

read -p "Do you want to proceed with these changes? (yes/no) " confirm
if [ "$confirm" != "yes" ]; then
    echo "Operation cancelled"
    exit 0
fi

echo "Updating secret..."

# Create a temporary file to store the updates
UPDATES_JSON="{}"

# Build the updates JSON
while read -r item; do
    decoded=$(echo "$item" | base64 --decode)
    key=$(echo "$decoded" | jq -r '.key')
    value=$(echo "$decoded" | jq -r '.value')
    
    secret_key="${key}_${CHAIN_ID}"
    
    # Add to updates JSON
    UPDATES_JSON=$(echo "$UPDATES_JSON" | jq --arg key "$secret_key" --arg value "$value" '. + {($key): $value}')
done < <(jq -r 'to_entries[] | select(.value != "0x0" and .value != "0x0000000000000000000000000000000000000000") | @base64' "$DEPLOYMENT_FILE")

# Get current secret
CURRENT_JSON=$(get_current_secret "$ENVIRONMENT")

# Merge current JSON with updates, updates take precedence
MERGED_JSON=$(echo "$CURRENT_JSON" | jq -s --argjson updates "$UPDATES_JSON" '.[0] * $updates')

# Update the secret
aws secretsmanager put-secret-value \
    --secret-id "$ENVIRONMENT" \
    --secret-string "$MERGED_JSON" \
    --no-cli-pager >/dev/null 2>&1 || \
aws secretsmanager create-secret \
    --name "$ENVIRONMENT" \
    --secret-string "$MERGED_JSON" \
    --no-cli-pager >/dev/null 2>&1

echo "Secret update completed successfully"
