const MorpherState = artifacts.require("MorpherState");
const MorpherBridge = artifacts.require("MorpherBridge");
const MorpherUserBlocking = artifacts.require("MorpherUserBlocking");

module.exports = async function(deployer, network, accounts) {

    try {
        const morpherBridge = await MorpherBridge.deployed();
    
        await upgradeProxy(morpherBridge.address, MorpherBridge, {
          deployer,
        });
      } catch (e) {
        if (
          e.message !=
          "MorpherBridge has not been deployed to detected network (network/artifact mismatch)"
        ) {
          throw e;
        }

        const morpherState = await MorpherState.deployed();
        const recoveryEnabled = !process.env.SIDECHAIN;

        await deployProxy(MorpherBridge, [morpherState.address, recoveryEnabled], {
          deployer,
        }); // deployer is changed to owner later
    
        const morpherBridge = await MorpherBridge.deployed();
        await morpherState.setMorpherBridge(morpherBridge.address);

        const morpherToken = await MorpherToken.deployed();
    
        await morpherAccessControl.grantRole(
          await morpherToken.PAUSER_ROLE(),
          morpherBridge.address
        );
    
        await morpherAccessControl.grantRole(
          await morpherToken.MINTER_ROLE(),
          morpherBridge.address
        );
        
      }
};
