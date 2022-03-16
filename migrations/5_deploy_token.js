const MorpherAccessControl = artifacts.require("MorpherAccessControl");
const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");

const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer, network, accounts) {
  const treasuryAddress = process.env.MORPHER_TREASURY || accounts[0];

  const morpherState = await MorpherState.deployed();
  const morpherAccessControl = await MorpherAccessControl.deployed();
  try {
    const morpherToken = await MorpherToken.deployed();

    await upgradeProxy(morpherToken.address, MorpherToken, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherToken has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    await deployProxy(MorpherToken, [morpherAccessControl.address], {
      deployer,
    }); // deployer is changed to owner later

    const morpherToken = await MorpherToken.deployed();

    await morpherAccessControl.grantRole(
      await morpherToken.PAUSER_ROLE(),
      accounts[0]
    );
    await morpherAccessControl.grantRole(
      await morpherToken.ADMINISTRATOR_ROLE(),
      accounts[0]
    );

    await morpherAccessControl.grantRole(
      await morpherToken.MINTER_ROLE(),
      accounts[0]
    );
    const _sideChainMint = web3.utils.toWei("575000000", "ether");
    const _mainChainMint = web3.utils.toWei("425000000", "ether");
    if (process.env.SIDECHAIN) {
      await morpherToken.mint(treasuryAddress, _sideChainMint);
      await morpherToken.setTotalTokensOnOtherChain(_mainChainMint);
      await morpherToken.setRestrictTransfers(true);
    } else {
      await morpherToken.mint(treasuryAddress, _mainChainMint);
      await morpherToken.setTotalTokensOnOtherChain(_sideChainMint);
    }
    await morpherAccessControl.revokeRole(
      await morpherToken.MINTER_ROLE(),
      accounts[0]
    );

    /**
     * configure State
     */
    await morpherState.setMorpherToken(MorpherToken.address);
  }
};
