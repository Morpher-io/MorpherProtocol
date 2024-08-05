
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
  "id":1
}' "http://127.0.0.1:8545"

curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"evm_setIntervalMining",
  "params":[5],
  "id":1
}' "http://127.0.0.1:8545"

curl -s -X POST -H "Content-Type: application/json" --data  \
'{
  "jsonrpc":"2.0",
  "method":"eth_blockNumber",
  "params":[],
  "id":1
}' "http://127.0.0.1:8545"
