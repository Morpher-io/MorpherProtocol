//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
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

	// Get the Uniswap V3 pool address for a token pair
	function getPoolAddress(address token0, address token1, uint24 fee) internal view returns (address) {
		// Load the pool address from deployments
		// address poolAddress = loadAddress("UniswapV3Pool");
		// if (poolAddress != address(0)) {
		//     return poolAddress;
		// }

		// If not saved, compute it
		// Sort tokens (Uniswap pools are created with tokens in ascending order)
		if (token0 > token1) {
			(token0, token1) = (token1, token0);
		}

		// Compute the pool address using the same formula as Uniswap
		bytes32 poolCodeHash = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89f5b1c3c1d0c84f3;
		address factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
		if (block.chainid == 8453) {
			factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
		}

		bytes32 salt = keccak256(abi.encode(token0, token1, fee));
		return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factory, salt, poolCodeHash)))));
	}

	// Check pool balances
	function checkPoolBalances(address token0, address token1, uint24 fee) internal view {
		address poolAddress = getPoolAddress(token0, token1, fee);
		console.log("Pool address:", poolAddress);

		uint256 token0Balance = IERC20(token0).balanceOf(poolAddress);
		uint256 token1Balance = IERC20(token1).balanceOf(poolAddress);

		console.log("Pool balances:");
		console.log("- Token0 (%s): %s", address(token0), uint256(token0Balance / 1e18));
		console.log("- Token1 (%s): %s", token1, uint256(token1Balance / 1e18));
	}

	function run() public {
		setupAddresses();

		vm.startBroadcast();
		address morpherTokenAddress = loadAddress("MorpherToken");
		require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");

		console.log("Testing swap on chain ID:", block.chainid);
		console.log("Using Universal Router:", UNIVERSAL_ROUTER);
		console.log("Using Permit2:", PERMIT2);
		console.log("MorpherToken address:", morpherTokenAddress);

		// Check pool balances before proceeding
		uint24 poolFee = 3000; // 0.3%
		checkPoolBalances(morpherTokenAddress, WETH, poolFee);

		// Load or deploy SwapHelper
		SWAP_HELPER = loadAddress("MorpherSwapHelper");
		if (SWAP_HELPER == address(0)) {
			// vm.startBroadcast();
			SWAP_HELPER = address(new MorpherSwapHelper(UNIVERSAL_ROUTER, PERMIT2));
			saveAddress("MorpherSwapHelper", SWAP_HELPER);
			// vm.stopBroadcast();
			console.log("Deployed new MorpherSwapHelper at:", SWAP_HELPER);
		} else {
			console.log("Using existing MorpherSwapHelper at:", SWAP_HELPER);
		}

		// Create test account and mint tokens
		Account memory testUser = makeAccount("testUser");
		console.log("Created test account:", testUser.addr);

		_mintTokensToUser(morpherTokenAddress, testUser.addr);

		// Add liquidity to the pool if needed
		// _addLiquidityToPool(morpherTokenAddress, testUser);

		// Execute the swap
		_executeSwap(morpherTokenAddress, testUser);
		vm.stopBroadcast();
	}

	function _mintTokensToUser(address morpherTokenAddress, address userAddr) internal {
		// vm.startBroadcast();
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(accessControlAddress != address(0), "MorpherAccessControl must be deployed");

		MorpherToken(morpherTokenAddress).morpherAccessControl().grantRole(keccak256("MINTER_ROLE"), msg.sender);
		MorpherToken(morpherTokenAddress).mint(userAddr, 20 ether);
		MorpherToken(morpherTokenAddress).morpherAccessControl().revokeRole(keccak256("MINTER_ROLE"), msg.sender);
		// vm.stopBroadcast();

		console.log("Minted 20 MPH to test account");
	}

	// Add liquidity to the pool if needed
	function _addLiquidityToPool(address morpherTokenAddress) internal {
		// Check if we need to add liquidity
		address poolAddress = getPoolAddress(morpherTokenAddress, WETH, 3000);
		uint256 wethBalance = IERC20(WETH).balanceOf(poolAddress);

		// If pool has less than 0.1 WETH, add some liquidity
		if (wethBalance < 0.1 ether) {
			console.log("Pool has insufficient liquidity. Adding liquidity...");

			vm.startBroadcast();

			// Convert some ETH to WETH for liquidity
			uint256 wethAmount = 0.2 ether;
			IWETH9(WETH).deposit{value: wethAmount}();

			// Transfer some MPH to the pool directly (simple approach for testing)
			uint256 mphAmount = 1000 ether;
			MorpherToken(morpherTokenAddress).morpherAccessControl().grantRole(keccak256("MINTER_ROLE"), msg.sender);
			MorpherToken(morpherTokenAddress).mint(poolAddress, mphAmount);
			MorpherToken(morpherTokenAddress).morpherAccessControl().revokeRole(keccak256("MINTER_ROLE"), msg.sender);

			// Transfer WETH to the pool
			IWETH9(WETH).transfer(poolAddress, wethAmount);

			vm.stopBroadcast();

			console.log("Added liquidity to pool:");
			console.log("- Added WETH: %s", wethAmount / 1e18);
			console.log("- Added MPH: %s", mphAmount / 1e18);

			// Check updated pool balances
			checkPoolBalances(morpherTokenAddress, WETH, 3000);
		}
	}

	// Helper function to create swap path
	function _createSwapPath(address tokenIn, address tokenOut) internal pure returns (bytes memory) {
		return abi.encodePacked(tokenIn, uint24(3000), tokenOut);
	}

	function _executeSwap(address morpherTokenAddress, Account memory testUser) internal {
		// Use a smaller amount for the swap to ensure it's within pool limits
		uint256 mphAmount = 1 ether; // Swap 1 MPH token
		uint256 deadline = block.timestamp + 1 hours;

		// Get signature components for permit
		(uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
			morpherTokenAddress,
			testUser,
			SWAP_HELPER,
			mphAmount,
			deadline
		);

		console.log("Created permit signature for MPH -> WETH swap");
		console.log("Attempting to swap %s MPH tokens", mphAmount / 1e18);

		// Create swap path
		bytes memory path = _createSwapPath(morpherTokenAddress, WETH);

		// Execute the swap
		_executeSwapWithPermit(
			testUser.addr,
			morpherTokenAddress,
			WETH,
			mphAmount,
			path,
			deadline,
			v, r, s
		);

		// Log results
		console.log("After swap attempt:");
		console.log("WETH balance: %s", IWETH9(WETH).balanceOf(testUser.addr) / 1e18);
		console.log("MPH balance: %s", IERC20(morpherTokenAddress).balanceOf(testUser.addr) / 1e18);
	}

	// Helper function to create permit signature
	function _createPermitSignature(
		address token,
		Account memory user,
		address spender,
		uint256 amount,
		uint256 deadline
	) internal returns (uint8 v, bytes32 r, bytes32 s) {
		bytes32 structHash = keccak256(
			abi.encode(
				_PERMIT_TYPEHASH,
				user.addr,
				spender,
				amount,
				MorpherToken(token).nonces(user.addr),
				deadline
			)
		);

		// Get the domain separator directly from the token contract
		bytes32 domainSeparator = MorpherToken(token).DOMAIN_SEPARATOR();
		bytes32 digest = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);

		return vm.sign(user.key, digest);
	}

	// Helper function to execute the swap with permit
	function _executeSwapWithPermit(
		address userAddr,
		address inputToken,
		address outputToken,
		uint256 amount,
		bytes memory path,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal {
		try
			MorpherSwapHelper(SWAP_HELPER).swapWithPermit(
				userAddr,
				inputToken,
				outputToken,
				amount,
				0, // minAmountOut
				path,
				deadline,
				deadline,
				v, r, s
			)
		returns (uint256 amountOut) {
			console.log("Swap successful! Received %s WETH", amountOut / 1e18);
		} catch Error(string memory reason) {
			console.log("Swap failed with reason: %s", reason);
		} catch {
			console.log("Swap failed with unknown error");
		}
	}
}
