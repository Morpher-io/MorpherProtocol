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

# Function to get current secret value
get_current_secret() {
    local secret_name=$1
    aws secretsmanager get-secret-value --secret-id "$secret_name" --query 'SecretString' --output text 2>/dev/null || echo "NOT_FOUND"
}

# Read deployment file
DEPLOYMENT_DATA=$(cat "$DEPLOYMENT_FILE")

echo "Will update secrets for environment: $ENVIRONMENT using chain ID: $CHAIN_ID"
echo "The following changes will be made:"
echo "----------------------------------------"

# Parse JSON and prepare changes
while IFS=":" read -r key value; do
    # Clean up the key and value
    key=$(echo "$key" | tr -d '"' | tr -d ' ' | tr -d '{' | tr -d '}' | tr -d ',')
    value=$(echo "$value" | tr -d '"' | tr -d ' ' | tr -d '{' | tr -d '}' | tr -d ',')
    
    # Skip empty or invalid lines
    if [ -z "$key" ] || [ -z "$value" ]; then
        continue
    fi

    # Skip 0x0 addresses
    if [ "$value" = "0x0" ]; then
        continue
    fi

    secret_name="${key}_${CHAIN_ID}"
    full_secret_name="${ENVIRONMENT}/${secret_name}"
    
    current_value=$(get_current_secret "$full_secret_name")
    
    if [ "$current_value" = "NOT_FOUND" ]; then
        echo "New secret: $full_secret_name"
        echo "Value: $value"
    else
        echo "Update secret: $full_secret_name"
        echo "Old value: $current_value"
        echo "New value: $value"
    fi
    echo "----------------------------------------"
done < <(echo "$DEPLOYMENT_DATA" | jq -r 'to_entries | .[] | "\(.key):\(.value)"')

read -p "Do you want to proceed with these changes? (yes/no) " confirm
if [ "$confirm" != "yes" ]; then
    echo "Operation cancelled"
    exit 0
fi

echo "Updating secrets..."

# Perform the actual updates
while IFS=":" read -r key value; do
    # Clean up the key and value
    key=$(echo "$key" | tr -d '"' | tr -d ' ' | tr -d '{' | tr -d '}' | tr -d ',')
    value=$(echo "$value" | tr -d '"' | tr -d ' ' | tr -d '{' | tr -d '}' | tr -d ',')
    
    # Skip empty or invalid lines
    if [ -z "$key" ] || [ -z "$value" ]; then
        continue
    fi

    # Skip 0x0 addresses
    if [ "$value" = "0x0" ]; then
        continue
    fi

    secret_name="${key}_${CHAIN_ID}"
    full_secret_name="${ENVIRONMENT}/${secret_name}"
    
    aws secretsmanager put-secret-value \
        --secret-id "$full_secret_name" \
        --secret-string "$value" \
        --no-cli-pager >/dev/null 2>&1 || \
    aws secretsmanager create-secret \
        --name "$full_secret_name" \
        --secret-string "$value" \
        --no-cli-pager >/dev/null 2>&1
    
    echo "Updated $full_secret_name"
done < <(echo "$DEPLOYMENT_DATA" | jq -r 'to_entries | .[] | "\(.key):\(.value)"')

echo "Secret updates completed successfully"
