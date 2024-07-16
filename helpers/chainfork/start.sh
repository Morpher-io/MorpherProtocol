

#!/bin/bash

set -m

# download the last contracts from polygon
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SCRIPT_DIR
node dl_source.js

# Start the program in the background
anvil -f https://polygon-mainnet.infura.io/v3/f5998fb0f1d44ea890789d60a216c74a  &

# Capture the job ID using 'jobs'
JOB_ID=$(jobs -l | grep "anvil" | awk '{print $1}' | tr -d '[]+')

# Wait until the port is open
while ! nc -z localhost 8545; do   
  sleep 1
done

# Use curl to access the RPC port opened by the program
curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":67}' http://localhost:8545 | jq .result

BALANCEOF=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_call","params": [
        {
            "data": "0x70a082310000000000000000000000005AD2d0Ebe451B9bC2550e600f2D2Acd31113053E",
            "to": "0x65C9e3289e5949134759119DBc9F862E8d6F2fBE"
        },
        "latest"
    ],"id":68}' http://localhost:8545 | jq -r .result)

echo $BALANCEOF
echo "\n"
echo "obase=10; ibase=16; $(echo "${BALANCEOF:2}" | tr '[:lower:]' '[:upper:]')" | bc
#sanity check that it works somehow in the logs. Outputs the balance of 0x5AD2d0Ebe451B9bC2550e600f2D2Acd31113053E in MPH on Polygon Mainnet 

#Admin slot 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
PROXYADMINVAR=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getStorageAt","params": [
        "0x65C9e3289e5949134759119DBc9F862E8d6F2fBE",
        "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103",
        "latest"
    ],"id":68}' http://localhost:8545 | jq -r .result)

PROXYADMIN="0x${PROXYADMINVAR:26}"
echo "\n";
echo $PROXYADMIN

NEWADMIN="0x000000000000000000000000720b9742632566b76b53b60eee8d5fdc20ac74be"
# NEWADMIN="0x000000000000000000000000f39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

echo "OLD ProxyAdmin"
curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getStorageAt","params": [
        "'"$PROXYADMIN"'",
        "0x0",
        "latest"
    ],"id":69}' http://localhost:8545 | jq -r .result
echo "SETTING new Proxy Admin $NEWADMIN"

curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"hardhat_setStorageAt","params": [
        "'"$PROXYADMIN"'",
        "0x0",
        "'"$NEWADMIN"'"
    ],"id":70}' http://localhost:8545 | jq -r .resut


curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getStorageAt","params": [
        "'"$PROXYADMIN"'",
        "0x0",
        "latest"
    ],"id":71}' http://localhost:8545 | jq -r .result

# Bring the background program back to the foreground using the job ID
fg %$JOB_ID
