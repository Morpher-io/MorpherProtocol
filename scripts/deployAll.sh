#!/bin/bash

# Sepolia:
# source .env
# forge script scripts/01-MorpherAccessControl.s.sol --private-key ${DEPLOYER_PK} --rpc-url ${SEPOLIA_RPC_URL} --slow --broadcast -vvvv --force --etherscan-api-key ${ETHERSCAN_API_KEY} --verify

# Execute deployment scripts in order, passing through all arguments
forge script scripts/01-MorpherAccessControl.s.sol "$@"
forge script scripts/02-MorpherState.s.sol "$@"
forge script scripts/03-MorpherUserBlocking.s.sol "$@"
forge script scripts/04-MorpherToken.s.sol "$@"
forge script scripts/05-MorpherInterestRateManager.s.sol "$@"
forge script scripts/06-MorpherStaking.s.sol "$@"
forge script scripts/07-MorpherMintingLimiter.s.sol "$@"
forge script scripts/08-MorpherTradeEngine.s.sol "$@"
forge script scripts/09-MorpherOracle.s.sol "$@"
