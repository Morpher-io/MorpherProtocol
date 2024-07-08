//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Chatter} from  "../src/Chatter.sol";

contract ChatterScript is Script {
    function run() public {
        Chatter chat = Chatter(0x5FbDB2315678afecb367f032d93F642f64180aa3);
        vm.startBroadcast();
        chat.sendMessage("hello hello");
    }
}