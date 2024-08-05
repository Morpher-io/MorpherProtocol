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

# Use curl to access the RPC port opened by the program
curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":67}' ${ADMIN_RPC} | jq .result

BALANCEOF=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_call","params": [
        {
            "data": "0x70a082310000000000000000000000005AD2d0Ebe451B9bC2550e600f2D2Acd31113053E",
            "to": "0x65C9e3289e5949134759119DBc9F862E8d6F2fBE"
        },
        "latest"
    ],"id":68}' ${ADMIN_RPC} | jq -r .result)

echo $BALANCEOF
echo "\n"
echo "obase=10; ibase=16; $(echo "${BALANCEOF:2}" | tr '[:lower:]' '[:upper:]')" | bc
#sanity check that it works somehow in the logs. Outputs the balance of 0x5AD2d0Ebe451B9bC2550e600f2D2Acd31113053E in MPH on Polygon Mainnet 

#Admin slot 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
PROXYADMINVAR=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getStorageAt","params": [
        "0x65C9e3289e5949134759119DBc9F862E8d6F2fBE",
        "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103",
        "latest"
    ],"id":68}' ${ADMIN_RPC} | jq -r .result)

PROXYADMIN="0x${PROXYADMINVAR:26}"
echo "\n";
echo $PROXYADMIN

NEWADMIN="0x000000000000000000000000720b9742632566b76b53b60eee8d5fdc20ac74be"
# NEWADMIN="0x000000000000000000000000f39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

echo "SETTING new Proxy Admin $NEWADMIN"

curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"tenderly_setStorageAt\",\"params\": [
        \"${PROXYADMIN}\",
        \"0x0000000000000000000000000000000000000000000000000000000000000000\",
        \"${NEWADMIN}\"
    ],\"id\":1}" ${ADMIN_RPC} | jq -r .result


curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getStorageAt\",\"params\": [
        \"${PROXYADMIN}\",
        \"0x0000000000000000000000000000000000000000000000000000000000000000\",
        \"${NEWADMIN}\"
    ],\"id\":1}" ${TENDERLY_VIRTUAL_TESTNET_RPC_URL} | jq -r .result

echo "Funding Dev Address"
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x5AD2d0Ebe451B9bC2550e600f2D2Acd31113053E",
    "to": "0x65C9e3289e5949134759119DBc9F862E8d6F2fBE",
    "data": "0xa9059cbb0000000000000000000000009578a645c265267141fb2b9a8c6dba70edbe9dfc00000000000000000000000000000000000000000000003635c9adc5dea00000",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC} | jq -r .result

curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"tenderly_setBalance",
  "params":["0x720B9742632566b76B53B60Eee8d5FDC20aC74bE","0xDE0B6B3A7640000"],
  "id":1
}' ${ADMIN_RPC} | jq -r .result

curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"tenderly_setBalance",
  "params":["0x65C9e3289e5949134759119DBc9F862E8d6F2fBE","0xDE0B6B3A7640000"],
  "id":1
}' ${ADMIN_RPC} | jq -r .result

echo "Setting Dev Permissions - callback accounts"
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d456e80d7f83ecad5376797c2562c7d48cc4873cf784699120b78efad9ba18ecc00000000000000000000000058f0442c8f9c9ecd2a09b9de3f1d834068387304",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC} | jq -r .result
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d456e80d7f83ecad5376797c2562c7d48cc4873cf784699120b78efad9ba18ecc0000000000000000000000001fdd1bb9afc69f19ebbf55ceb5153c43b5c5bc1e",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC} | jq -r .result
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d456e80d7f83ecad5376797c2562c7d48cc4873cf784699120b78efad9ba18ecc000000000000000000000000181ad9eba392b8001eead315e50e9fd9572116d2",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC} | jq -r .result

##add trade engine as minter and burner
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6000000000000000000000000005cb9ad7c713bff25ed07f3d9e1c3945e543cd5",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC} | jq -r .result
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15d3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848000000000000000000000000005cb9ad7c713bff25ed07f3d9e1c3945e543cd5",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC}| jq -r .result
curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_sendTransaction",
  "params":[{
    "from": "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762",
    "to": "0x139950831d8338487db6807c6FdAeD1827726dF2",
    "data": "0x2f2ff15de5a0b4d50f56047f84728557fedbda92f956391bc9d5c762e8461996dd8e7ad7000000000000000000000000a6c5c9c90910c9c12f31c0eb7997c24dddc75afe",
    "gas": "0x20EF3F",
    "gasPrice": "0xFFFFFF"
  }],
  "id":1
}' ${ADMIN_RPC}| jq -r .result


echo "Deploying new contracts"

cd $SCRIPTPATH/../../
# forge script ./scripts/00-fund-deployer.s.sol --rpc-url http://localhost:8545 --broadcast --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --unlocked --chain-id 137 -vvvv --force
forge script ./scripts/01-Upgrade-proxy-v4.s.sol --rpc-url ${TENDERLY_VIRTUAL_TESTNET_RPC_URL} --broadcast --chain-id 137 -vv --force --slow --verifier-url=$TENDERLY_VIRTUAL_TESTNET_RPC_URL/verify/etherscan --verify --etherscan-api-key=$TENDERLY_ACCESS_KEY

