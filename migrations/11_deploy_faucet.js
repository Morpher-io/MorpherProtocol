const MorpherState = artifacts.require("MorpherState");
const MorpherFaucet = artifacts.require("MorpherFaucet");
const MorpherToken = artifacts.require("MorpherToken");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

  const morpherState = await MorpherState.deployed();

  /**
   * Only setting the Governance on Mainchain
   */
  if (network === 'kovan' || network === 'test' || network === 'local') {
   
    await deployer.deploy(
      MorpherFaucet,
      MorpherToken.address,
      ownerAddress,
      web3.utils.toWei('100','ether')
    );

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherFaucet.address);
    
    await morpherState.enableTransfers(MorpherFaucet.address);

    /**
     * fund the contract with 1 million MPH
     */
    const morpherToken = await MorpherToken.deployed();
    await morpherToken.transfer(MorpherFaucet.address, web3.utils.toWei('1000000','ether'));
    
  }
};
