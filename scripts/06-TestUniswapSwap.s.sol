//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";

// Universal Router imports
import {Commands} from "../lib/universal-router/contracts/libraries/Commands.sol";
import {IUniversalRouter} from "../lib/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {MorpherSwapHelper} from "../contracts/MorpherSwapHelper.sol";

// Uniswap V3 imports
import {ECDSAUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

interface IWETH9 {
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address dst, uint wad) external returns (bool);
}

// Helper struct for account management
struct Account {
    address addr;
    uint256 key;
}

contract TestUniswapSwap is DeployOrUpgrade {
    using stdJson for string;

    // Universal Router addresses - will be set based on chainId
    address public UNIVERSAL_ROUTER;
    address public PERMIT2;
    address public WETH;
    address public SWAP_HELPER;
    
    // EIP-712 constants for permit
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
    
        if (chainId == 8453) {
            // Base Mainnet
            UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        } else if (chainId == 84532) {
            // Base Sepolia
            UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        } else {
            revert("Unsupported chain ID");
        }
    }

    // // Helper function to create a new account
    // function makeAccount(string memory name) internal returns (Account memory) {
    //     string memory mnemonic = "test test test test test test test test test test test junk";
    //     uint256 privateKey = vm.deriveKey(mnemonic, 0);
    //     address addr = vm.addr(privateKey);
        
              
    //     return Account({
    //         addr: addr,
    //         key: privateKey
    //     });
    // }
    
    function run() public {
        // Set up the correct addresses based on the chain
        setupAddresses();
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("Testing swap on chain ID:", uint256(block.chainid));
        console.log("Using Universal Router:", UNIVERSAL_ROUTER);
        console.log("Using Permit2:", PERMIT2);
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);
        
        // Load or deploy SwapHelper
        SWAP_HELPER = loadAddress("MorpherSwapHelper");
        if (SWAP_HELPER == address(0)) {
            vm.startBroadcast();
            MorpherSwapHelper swapHelper = new MorpherSwapHelper(UNIVERSAL_ROUTER, PERMIT2);
            SWAP_HELPER = address(swapHelper);
            saveAddress("MorpherSwapHelper", SWAP_HELPER);
            vm.stopBroadcast();
            console.log("Deployed new MorpherSwapHelper at:", SWAP_HELPER);
        } else {
            console.log("Using existing MorpherSwapHelper at:", SWAP_HELPER);
        }
        
        // Create a test account
        Account memory testUser = makeAccount("testUser");
        console.log("Created test account:", testUser.addr);
        
        // Mint some MPH tokens to the test account
        vm.startBroadcast();
        // Get admin role to mint tokens
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "MorpherAccessControl must be deployed");
        
        // Grant minter role to the deployer
        MorpherToken(morpherTokenAddress).morpherAccessControl().grantRole(keccak256("MINTER_ROLE"), msg.sender);
        
        // Mint 20 MPH to the test user
        uint256 mphAmount = 20 ether; // 20 MPH tokens
        MorpherToken(morpherTokenAddress).mint(testUser.addr, mphAmount);
        
        // Revoke minter role
        MorpherToken(morpherTokenAddress).morpherAccessControl().revokeRole(keccak256("MINTER_ROLE"), msg.sender);
        vm.stopBroadcast();
        
        console.log("Minted", mphAmount / 1e18, "MPH to test account");
        
        // Now we'll perform the swap using the test account with a permit signature
        
        // 1. Create the permit signature
        uint256 nonce = MorpherToken(morpherTokenAddress).nonces(testUser.addr);
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create the permit signature
        bytes32 structHash = keccak256(
            abi.encode(
                _PERMIT_TYPEHASH,
                testUser.addr,
                SWAP_HELPER,
                mphAmount,
                nonce,
                deadline
            )
        );
        
        // Get domain separator for the token
        bytes32 HASHED_NAME = keccak256("MorpherToken");
        bytes32 HASHED_VERSION = keccak256("1");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                _TYPE_HASH,
                HASHED_NAME,
                HASHED_VERSION,
                block.chainid,
                morpherTokenAddress
            )
        );
        
        // Create the digest that will be signed
        bytes32 digest = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);
        
        // Sign the digest with the test user's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(testUser.key, digest);
        
        console.log("Created permit signature for MPH -> WETH swap");
        
        // 2. Prepare the swap parameters
        uint24 poolFee = 3000; // 0.3%
        bytes memory path = abi.encodePacked(morpherTokenAddress, poolFee, WETH);
        uint256 minAmountOut = 0; // In production, use a real minimum amount
        
        // 3. Execute the swap as the test user
        vm.startPrank(testUser.addr);
        
        // Execute the swap through the helper with the permit signature
        MorpherSwapHelper(SWAP_HELPER).swapWithPermit(
            morpherTokenAddress,        // inputToken
            WETH,                       // outputToken
            mphAmount,                  // amountIn
            minAmountOut,               // amountOutMin
            path,                       // path
            deadline,                   // deadline
            deadline,                   // permitDeadline
            v, r, s                     // signature components
        );
        
        // Check balances after swap
        uint256 wethBalance = IWETH9(WETH).balanceOf(testUser.addr);
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(testUser.addr);
        
        console.log("After swap:");
        console.log("WETH balance:", wethBalance / 1e18);
        console.log("MPH balance:", mphBalance / 1e18);
        
        vm.stopPrank();
    }
}
