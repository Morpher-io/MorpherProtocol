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

# Function to update secret with merged JSON
update_secret() {
    local secret_name=$1
    local new_value=$2
    local current_json
    current_json=$(get_current_secret "$secret_name")
    
    # Merge current JSON with new value, new value takes precedence
    local merged_json
    merged_json=$(echo "$current_json" | jq -s --arg new "$new_value" '.[0] * ($new | fromjson)')
    
    aws secretsmanager put-secret-value \
        --secret-id "$secret_name" \
        --secret-string "$merged_json" \
        --no-cli-pager >/dev/null 2>&1 || \
    aws secretsmanager create-secret \
        --name "$secret_name" \
        --secret-string "$merged_json" \
        --no-cli-pager >/dev/null 2>&1
}

# Read deployment file
DEPLOYMENT_DATA=$(cat "$DEPLOYMENT_FILE")

echo "Will update secrets for environment: $ENVIRONMENT using chain ID: $CHAIN_ID"
echo "The following changes will be made:"
echo "----------------------------------------"

# Parse JSON and prepare changes
jq -r 'to_entries[] | select(.value != "0x0" and .value != "0x0000000000000000000000000000000000000000") | @base64' "$DEPLOYMENT_FILE" | while read -r item; do
    decoded=$(echo "$item" | base64 --decode)
    key=$(echo "$decoded" | jq -r '.key')
    value=$(echo "$decoded" | jq -r '.value')
    
    secret_name="${key}_${CHAIN_ID}"
    full_secret_name="${ENVIRONMENT}/${secret_name}"
    
    current_value=$(get_current_secret "$full_secret_name")
    
    current_json=$(get_current_secret "$full_secret_name")
    current_value=$(echo "$current_json" | jq -r --arg key "${key}_${CHAIN_ID}" '.[$key] // "NOT_SET"' 2>/dev/null || echo "NOT_SET")
    
    if [ "$current_value" = "NOT_SET" ]; then
        echo "New key in secret: $full_secret_name"
        echo "Key: ${key}_${CHAIN_ID}"
        echo "Value: $value"
    else
        echo "Update key in secret: $full_secret_name"
        echo "Key: ${key}_${CHAIN_ID}"
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

echo "Updating secrets..."

# Perform the actual updates
jq -r 'to_entries[] | select(.value != "0x0" and .value != "0x0000000000000000000000000000000000000000") | @base64' "$DEPLOYMENT_FILE" | while read -r item; do
    decoded=$(echo "$item" | base64 --decode)
    key=$(echo "$decoded" | jq -r '.key')
    value=$(echo "$decoded" | jq -r '.value')
    
    secret_name="${key}_${CHAIN_ID}"
    full_secret_name="${ENVIRONMENT}/${secret_name}"
    
    # Create JSON object with the new key-value pair
    new_json=$(jq -n \
        --arg key "${key}_${CHAIN_ID}" \
        --arg value "$value" \
        '{($key): $value}')
    
    update_secret "$full_secret_name" "$new_json"
    echo "Updated key ${key}_${CHAIN_ID} in $full_secret_name"
done

echo "Secret updates completed successfully"
