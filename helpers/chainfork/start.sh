#!/bin/bash

set -m

# download the last contracts from polygon
# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
# echo $SCRIPTPATH
cd $SCRIPTPATH
export $(grep -v '^#' ../../.env | xargs)
# node dl_source.js

# Start the program in the background
anvil -b 5 -f $FORK_URL  &

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

echo "Funding Dev Address"
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendUnsignedTransaction",
  "params":[{
    "from": "0x5AD2d0Ebe451B9bC2550e600f2D2Acd31113053E",
    "to": "0x65C9e3289e5949134759119DBc9F862E8d6F2fBE",
    "data": "0xa9059cbb0000000000000000000000009578a645c265267141fb2b9a8c6dba70edbe9dfc00000000000000000000000000000000000000000000003635c9adc5dea00000",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":71
}' "http://127.0.0.1:8545" | jq -r .result

curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"anvil_setBalance",
  "params":["0x720B9742632566b76B53B60Eee8d5FDC20aC74bE","0x021e19e0c9bab2400000"],
  "id":72
}' "http://127.0.0.1:8545" | jq -r .result

curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"anvil_setBalance",
  "params":["0x65C9e3289e5949134759119DBc9F862E8d6F2fBE","0x021e19e0c9bab2400000"],
  "id":72
}' "http://127.0.0.1:8545" | jq -r .result

echo "Setting Dev Permissions - callback accounts"
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendUnsignedTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d456e80d7f83ecad5376797c2562c7d48cc4873cf784699120b78efad9ba18ecc00000000000000000000000058f0442c8f9c9ecd2a09b9de3f1d834068387304",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":73
}' "http://127.0.0.1:8545" | jq -r .result
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendUnsignedTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d456e80d7f83ecad5376797c2562c7d48cc4873cf784699120b78efad9ba18ecc0000000000000000000000001fdd1bb9afc69f19ebbf55ceb5153c43b5c5bc1e",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":73
}' "http://127.0.0.1:8545" | jq -r .result
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendUnsignedTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d456e80d7f83ecad5376797c2562c7d48cc4873cf784699120b78efad9ba18ecc000000000000000000000000181ad9eba392b8001eead315e50e9fd9572116d2",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":73
}' "http://127.0.0.1:8545" | jq -r .result


echo "Deploying new contracts"

cd $SCRIPTPATH/../../
# forge script ./scripts/00-fund-deployer.s.sol --rpc-url http://localhost:8545 --broadcast --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --unlocked --chain-id 137 -vvvv --force
forge script ./scripts/01-Upgrade-proxy-v4.s.sol --rpc-url http://localhost:8545 --broadcast --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --unlocked --chain-id 137 -vvvv --force


# Bring the background program back to the foreground using the job ID
fg %$JOB_ID

