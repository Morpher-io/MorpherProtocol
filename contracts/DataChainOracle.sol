//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;


import "./interfaces/CallbackableContract.sol";

import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "./DataProviderCollateralStorage.sol";


contract DataChainOracle is PausableUpgradeable {

    DataProviderCollateralStorage collateralStorage = DataProviderCollateralStorage(address(0x11));

    uint256 constant TIMESTAMP_DELAY_THRESHOLD = 3000; // milliseconds

    event Oracle(uint256 reqId, bytes32 identifier);

    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct OracleMessage {
        address provider;
        uint64 timestamp;
        uint256 value;
        Signature signature;
    }

    struct VerifiedOracleMessage {
        bool verified;
        OracleMessage message;
    }


    struct OracleRequest {
        address requester;
        uint256 requestId;
        bytes32 identifier;
        uint256 valueLocked;
        address[] requestedProviders;
    }

    struct OracleCacheData {
        uint256 blockNumber;
        address[] providers;
        mapping(address => uint) providerValue;
    }


    mapping(uint256 => OracleRequest) requests;
    uint256 requestIds;

    mapping(bytes32 => OracleCacheData) cache;
    

    mapping(address => uint) public tickPrice;



    /**
     * sets the price of the tick for a data provider
     * 
     * Does intentionally leave out the check if enough staked, because its only valid for the msg.sender
     */
    function setTickPrice(uint price) public {
        tickPrice[msg.sender] = price;
    }

    


/**
 * TODO: Error handling for callbacks
 */

    function checkProviderSignature(bytes32 identifier, bytes32 salt, uint8 _v, bytes32 _r, bytes32 _s) external view returns (bool) {
        bytes memory prefix = "\x19Oracle Signed Message:\n64";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, abi.encodePacked(identifier, salt)));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return collateralStorage.dataProviderHasEnoughStake(signer);
    }


    function getTotalPriceForRequestedProviders(address[] memory requestedProviders) public view returns(uint) {
        uint totalPrice;
        if (requestedProviders.length == 0) {
            address[] memory allProviders = collateralStorage.getDataProviders();
            for(uint i = 0; i < allProviders.length; i++) {
                totalPrice += tickPrice[allProviders[i]];
            }
        } else {
            for(uint i = 0; i < requestedProviders.length; i++) {
                totalPrice += tickPrice[requestedProviders[i]];
            }
        }
        return totalPrice;
    }

    //we might want to check the price at the receiver side instead and throw an error if not enough funds
    function getOracleData(uint256 requestId, bytes32 identifier, address[] memory requestedProviders) external payable {
        require(getTotalPriceForRequestedProviders(requestedProviders) <= msg.value, "Not enough funds sent to pay for oracle data");
        if (cache[identifier].blockNumber == block.number) {
            respondToOracleRequest(msg.sender, requestId, identifier, msg.value, requestedProviders);
        } else {
            requests[requestIds] = OracleRequest(msg.sender, requestId, identifier, msg.value, requestedProviders);
            emit Oracle(requestIds, identifier);
            requestIds++;
        }
    }


    function isValidProviderMessage(OracleMessage memory m) private view returns (bool) {
        bytes memory prefix = "\x19Oracle Signed Message:\n60";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, abi.encodePacked(m.provider, m.timestamp, m.value)));
        address signer = ecrecover(prefixedHashMessage, m.signature.v, m.signature.r, m.signature.s);
        uint256 delay = block.timestamp * 1000 > m.timestamp ? block.timestamp * 1000 - m.timestamp : m.timestamp - block.timestamp * 1000;
        if (signer == m.provider && delay < TIMESTAMP_DELAY_THRESHOLD && collateralStorage.dataProviderHasEnoughStake(signer)) {
            return true;
        }
        return false;
    }
    function cacheReceipt(OracleMessage[] memory data, bytes32 identifier) private {
        cache[identifier].blockNumber = block.number;
        delete cache[identifier].providers;
        for (uint256 i=0; i<data.length; i++) {
            if (isValidProviderMessage(data[i])) {
                cache[identifier].providers.push(data[i].provider);
                cache[identifier].providerValue[data[i].provider] = data[i].value;
            }
        }
    }

    // TODO(mic) resolve attack: validator can choose not to send some providers' messages
    function callback(uint256 oracleRequestId, OracleMessage[] memory response) external {
        OracleRequest memory request = requests[oracleRequestId];
        cacheReceipt(response, request.identifier);
        respondToOracleRequest(request.requester, request.requestId, request.identifier, request.valueLocked, request.requestedProviders);
    }

    function respondToOracleRequest(address to, uint256 requestId, bytes32 identifier, uint256 valueLocked, address[] memory requestedProviders) private {
        
        uint256 validIndex = 0;
        uint256 average = 0;
        uint256 valueSpent = 0;
        if (requestedProviders.length == 0) {
            for (uint256 i = 0; i < cache[identifier].providers.length; i++) {
                if (cache[identifier].providerValue[cache[identifier].providers[i]] > 0) {
                    average = average / (validIndex + 1) * (validIndex) + cache[identifier].providerValue[cache[identifier].providers[i]] / (validIndex + 1);
                    validIndex += 1;
                    valueSpent += tickPrice[cache[identifier].providers[i]];
                    payable(cache[identifier].providers[i]).transfer(tickPrice[cache[identifier].providers[i]]);
                }
            }
        } else {
            for (uint256 i=0; i<requestedProviders.length; i++) {
                if (cache[identifier].providerValue[requestedProviders[i]] > 0) {
                    average = average / (validIndex + 1) * (validIndex) + cache[identifier].providerValue[requestedProviders[i]] / (validIndex + 1);
                    validIndex += 1;
                    valueSpent += tickPrice[requestedProviders[i]];
                    payable(requestedProviders[i]).transfer(tickPrice[requestedProviders[i]]);
                }
            }
        }
        // should never happen
        require(valueSpent <= valueLocked, "Not enough value locked to pay all the providers");
        if (valueSpent < valueLocked) {
            payable(to).transfer(valueLocked - valueSpent);
        }
        CallbackableContract(to).__callback(requestId, average);
    }
}
