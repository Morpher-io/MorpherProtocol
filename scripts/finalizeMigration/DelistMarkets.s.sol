// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title DelistMarkets
 * @notice Delists specified markets on the sidechain MorpherOracle
 *
 * This script calls delistMarket on the MorpherOracle to close all positions
 * for each market. The delistMarket function may need to be called multiple
 * times for markets with many positions (it stops when gas is low).
 *
 * Usage:
 *   forge script scripts/finalizeMigration/DelistMarkets.s.sol \
 *     --rpc-url $SIDECHAIN_RPC_URL \
 *     --private-key $ADMIN_PRIVATE_KEY \
 *     --broadcast \
 *     -vvvv
 *
 * Important: The caller must be the administrator set in MorpherState.
 */

interface IMorpherOracle {
    function delistMarket(bytes32 _marketId, bool _startFromScratch) external;
}

interface IMorpherState {
    function getMarketActive(bytes32 _marketId) external view returns (bool);
    function getAdministrator() external view returns (address);
}

contract DelistMarkets is Script {
    // Sidechain addresses from docs/addressesAndRoles.json
    address constant MORPHER_ORACLE = 0xf8B5b1699A00EDfdB6F15524646Bd5071bA419Fb;
    address constant MORPHER_STATE = 0xB4881186b9E52F8BD6EC5F19708450cE57b24370;

    IMorpherOracle oracle = IMorpherOracle(MORPHER_ORACLE);
    IMorpherState state = IMorpherState(MORPHER_STATE);

    // Add market hashes here from the CSV file
    // Format: keccak256(abi.encodePacked("MARKET_NAME"))
    bytes32[] public marketsToDelistHashes;

    function setUp() public {
        // Example markets - replace with actual hashes from market-hashes.csv
        // These are just examples, add all market hashes here:

        // marketsToDelistHashes.push(0x876800e24f83128aaabe8a807ec28f2cb73570d4278ee005de3b27cd7ad4fcdb); // UCL_CHEL
        // marketsToDelistHashes.push(0x4ca7df2e8565a3db9b668e992c093dfb7e002390eeff1b55513d092611cd350a); // STOCK_AWK
        // marketsToDelistHashes.push(0xdd5335cfea597eb747a8842474a34e6c81fb6c7047d3cad7f110355e60ee1dc1); // UCL_CHEW
        // marketsToDelistHashes.push(0x5dedee071d7744e8368a1e0fc5b3a11afadc2b160e2fe3a49a6965b734a19799); // CRYPTO_MX
        // marketsToDelistHashes.push(0x15a0133b3bd3139a0a56dae604a5ad396425771480f8cddd04bb76f3fd7eea53); // STOCK_A

        console.log("=== DelistMarkets Script ===");
        console.log("Markets to delist:", marketsToDelistHashes.length);
        console.log("");
        console.log("NOTE: Add market hashes to the setUp() function before running.");
        console.log("Or use the shell script delist-markets.sh which reads from CSV.");
    }

    function run() external {
        require(marketsToDelistHashes.length > 0, "No markets to delist. Add hashes to setUp()");

        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address adminAddress = vm.addr(adminPrivateKey);

        console.log("Admin Address:", adminAddress);
        console.log("Current State Administrator:", state.getAdministrator());
        console.log("");

        vm.startBroadcast(adminPrivateKey);

        for (uint256 i = 0; i < marketsToDelistHashes.length; i++) {
            bytes32 marketHash = marketsToDelistHashes[i];

            console.log("Processing market:", i + 1, "/", marketsToDelistHashes.length);
            console.logBytes32(marketHash);

            // Check if market is active
            bool isActive = state.getMarketActive(marketHash);
            if (!isActive) {
                console.log("  Market already inactive, skipping");
                continue;
            }

            // Call delistMarket with startFromScratch = true
            // Note: For markets with many positions, this may need to be called multiple times
            // The function emits DelistMarketIncomplete if it runs out of gas
            try oracle.delistMarket(marketHash, true) {
                console.log("  Delist call succeeded");
            } catch Error(string memory reason) {
                console.log("  Delist failed:", reason);
            } catch {
                console.log("  Delist failed with unknown error");
            }

            console.log("");
        }

        vm.stopBroadcast();

        console.log("=== Done ===");
        console.log("Note: Check logs for DelistMarketIncomplete events.");
        console.log("Re-run the script if any markets need additional calls.");
    }

    /**
     * @notice Helper to delist a single market
     * Call this if you need to continue delisting after a DelistMarketIncomplete event
     */
    function delistSingleMarket(bytes32 _marketHash, bool _startFromScratch) external {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        vm.startBroadcast(adminPrivateKey);
        oracle.delistMarket(_marketHash, _startFromScratch);
        vm.stopBroadcast();
    }
}
