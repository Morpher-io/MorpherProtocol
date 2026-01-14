// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "./MorpherStakingUnstakeOnly.sol";

/**
 * @title DeployStakingUnstakeOnly
 * @notice Deploys the MorpherStakingUnstakeOnly contract to the sidechain
 *
 * Usage:
 *   forge script scripts/finalizeMigration/DeployStakingUnstakeOnly.s.sol \
 *     --rpc-url $SIDECHAIN_RPC_URL \
 *     --private-key $DEPLOYER_PRIVATE_KEY \
 *     --broadcast \
 *     -vvvv
 *
 * After deployment:
 *   1. Grant access to the new contract in MorpherState: grantAccess(newContractAddress)
 *   2. Enable transfers for the new contract: enableTransfers(newContractAddress)
 *   3. (Optional) Revoke access from old staking contract: denyAccess(oldStakingAddress)
 */
contract DeployStakingUnstakeOnly is Script {
    // Sidechain addresses from docs/addressesAndRoles.json
    address constant MORPHER_STATE = 0xB4881186b9E52F8BD6EC5F19708450cE57b24370;
    address constant OLD_STAKING = 0x318Ea6e12A3e49703666C85eEF372644b4022C49;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("=== Deploying MorpherStakingUnstakeOnly ===");
        console.log("MorpherState:", MORPHER_STATE);
        console.log("Old Staking:", OLD_STAKING);

        vm.startBroadcast(deployerPrivateKey);

        MorpherStakingUnstakeOnly stakingUnstakeOnly = new MorpherStakingUnstakeOnly(
            MORPHER_STATE,
            OLD_STAKING
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Successful ===");
        console.log("MorpherStakingUnstakeOnly deployed at:", address(stakingUnstakeOnly));
        console.log("Owner:", stakingUnstakeOnly.owner());
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Grant access to MorpherState:");
        console.log("   cast send", MORPHER_STATE, '"grantAccess(address)"', address(stakingUnstakeOnly));
        console.log("");
        console.log("2. Enable transfers in MorpherState:");
        console.log("   cast send", MORPHER_STATE, '"enableTransfers(address)"', address(stakingUnstakeOnly));
        console.log("");
        console.log("3. (Optional) Deny access to old staking:");
        console.log("   cast send", MORPHER_STATE, '"denyAccess(address)"', OLD_STAKING);
    }
}
