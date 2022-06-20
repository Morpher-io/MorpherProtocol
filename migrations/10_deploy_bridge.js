const MorpherState = artifacts.require("MorpherState");
const MorpherBridge = artifacts.require("MorpherBridge");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");
const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");

//https://docs.uniswap.org/protocol/reference/deployments
const swapRouterAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; 

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
        const recoveryEnabled = false; //!process.env.SIDECHAIN;

        await deployProxy(MorpherBridge, [morpherState.address, recoveryEnabled, swapRouterAddress], {
          deployer,
        }); // deployer is changed to owner later
    
        const morpherBridge = await MorpherBridge.deployed();
        await morpherState.setMorpherBridge(morpherBridge.address);

        const morpherToken = await MorpherToken.deployed();
        const morpherAccessControl = await MorpherAccessControl.deployed();
    
        await morpherAccessControl.grantRole(
          await morpherToken.BURNER_ROLE(),
          morpherBridge.address
        );
    
        await morpherAccessControl.grantRole(
          await morpherToken.MINTER_ROLE(),
          morpherBridge.address
        );

        const sidechainOperator = process.env.SIDECHAIN_OPERATOR || accounts[0];
        await morpherAccessControl.grantRole(
          await morpherBridge.SIDECHAINOPERATOR_ROLE(),
          sidechainOperator
        );
        
      }
};
