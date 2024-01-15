const AdminOverrideProxy = artifacts.require("MorpherAdministratorProxy.sol");
const MorpherState = artifacts.require("MorpherState");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

const markets = require("../docs/markets.json");

module.exports = async function (deployer, network, accounts) {
  const morpherState = await MorpherState.deployed();

  if (network !== "mainchain") {
    // await deployer.deploy(
    //   AdminOverrideProxy,
    //   accounts[0],
    //   morpherState.address
    // );
    const morpherAccessControl = await MorpherAccessControl.deployed();

    // const marketHashObject = require("../docs/markets");

    // const marketHashes = Object.keys(marketHashObject);
    const adminOverrideProxy = await AdminOverrideProxy.deployed();
    await morpherAccessControl.grantRole(
      await morpherState.ADMINISTRATOR_ROLE(),
      adminOverrideProxy.address
    );
    let marketsToAdd = [];
    let marketNames = [];
    for (let i = 60; i < markets.length; i++) {
      marketsToAdd.push(web3.utils.sha3(markets[i].id));
      marketNames.push(markets[i].id)
      if (marketsToAdd.length == 20) {
        await adminOverrideProxy.bulkActivateMarkets(marketsToAdd);
        marketsToAdd = [];
        console.log("Added 20 Markets", marketNames);
        marketNames = [];
        // if (network !== "mainchain") {
        //   break;
        // }
      }
    }
    if (marketsToAdd.length > 0) {
      await adminOverrideProxy.bulkActivateMarkets(marketsToAdd);
      console.log("Added", marketsToAdd.length, "Markets", marketNames);
      marketsToAdd = [];
      marketNames = [];
    }

    await morpherAccessControl.revokeRole(
      await morpherState.ADMINISTRATOR_ROLE(),
      adminOverrideProxy.address
    );
  }
};
