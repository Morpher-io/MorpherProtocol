const MorpherState = artifacts.require("MorpherState");
const MorpherFaucet = artifacts.require("MorpherFaucet");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

  const morpherState = await MorpherState.deployed();

  /**
   * Only setting the Governance on Mainchain
   */
  if (network === 'kovan' || network === 'test' || network === 'local' || network === 'dashboard') {
   
    await deployer.deploy(
      MorpherFaucet,
      MorpherToken.address,
      ownerAddress,
      web3.utils.toWei('100','ether')
    );
    
    //await morpherState.enableTransfers(MorpherFaucet.address);

    /**
     * fund the contract with 1 million MPH
     */
    const morpherToken = await MorpherToken.deployed();
    const morpherAccessControl = await MorpherAccessControl.deployed();
    await morpherAccessControl.grantRole(
      await morpherToken.MINTER_ROLE(),
      accounts[0]
    );
    await morpherToken.mint(MorpherFaucet.address, web3.utils.toWei('1000000','ether'));
    await morpherAccessControl.revokeRole(
      await morpherToken.MINTER_ROLE(),
      accounts[0]
    );
  }
};
