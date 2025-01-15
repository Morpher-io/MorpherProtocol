#!/bin/bash

# Execute deployment scripts in order, passing through all arguments
forge script scripts/01-MorpherAccessControl.s.sol "$@"
forge script scripts/02-MorpherState.s.sol "$@"
