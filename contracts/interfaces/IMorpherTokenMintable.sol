//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import {IERC20} from "../../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";

interface IMorpherTokenMintable is IERC20 {
    function mint(address to, uint256 amount) external;
    // Add other MorpherToken specific functions if needed by MRO beyond minting & ERC20
}
