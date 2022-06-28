const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherMintingLimiter = artifacts.require("MorpherMintingLimiter");

module.exports = async function (callback) {
  const addressesAndRoles = require("../docs/addressesAndRoles.json");
  console.log("Deploying a new TradeEngine with Truffle Dashboard...");
  const chain = "sidechain";

  const [, contracts, roles] = Object.values(addressesAndRoles[chain]);

  /**
   * Owner Actions:
   * 1. Deploy new Trade Engine
   * 2. Set new Trade Engine in Oracle
   * 3. Set Minting Limiter on new Trade Engine
   */

  //select deployer account
  await waitForAccount(roles.owner);

  const deployedTimestamp = 1613399217;
  const newTradeEngine = await MorpherTradeEngine.new(
    contracts.MorpherState.address,
    roles.owner,
    contracts.MorpherStaking.address,
    true,
    deployedTimestamp,
    contracts.MorpherState.address, //set minting limiter to state first
    contracts.MorpherUserBlocking.address
  );
  console.log("New Trade Engine", newTradeEngine.address);

  const morpherState = await MorpherState.at(contracts.MorpherState.address);
  await morpherState.grantAccess(newTradeEngine.address, {
    from: roles.owner,
  });
  console.log("✅ Granted access for new Trade Engine");
  await morpherState.enableTransfers(newTradeEngine.address, {
    from: roles.owner,
  });
  console.log("✅ Granted Transfers for new Trade Engine");


  const morpherOracle = await MorpherOracle.at(contracts.MorpherOracle.address);
  await morpherOracle.setTradeEngineAddress(newTradeEngine.address);
  console.log("✅ Set new Trade Engine in Oracle");

  if (chain != "sidechainDev") {
    // const morpherMintingLimiter = await MorpherMintingLimiter.at(
    //   contracts.MorpherMintingLimiter.address
    // );
    // await morpherMintingLimiter.setTradeEngineAddress(newTradeEngine.address); //on dev not necessary
    await newTradeEngine.setMorpherMintingLimiter(
      contracts.MorpherMintingLimiter.address
    );

    console.log("✅ Removing minting limiter from old tradeEngine");
    const oldTradeEngine = await MorpherTradeEngine.at(
      contracts.MorpherTradeEngine.address
    );
    await oldTradeEngine.setMorpherMintingLimiter(
      contracts.MorpherState.address
    );
  }

  /**
   * Administrative Actions:
   * 1. Remove Minting Limiter from Old Trade Engine
   * 2. Set Minting Limiter on New Trade Engine
   * 3. Grant Access
   * 4. Grant Transfers for new Trade Engine
   */
  await waitForAccount(roles.administrator);

  if (chain != "sidechainDev") {
    const morpherMintingLimiter = await MorpherMintingLimiter.at(contracts.MorpherMintingLimiter.address);
    await morpherMintingLimiter.setTradeEngineAddress(newTradeEngine.address); //on dev not necessary
    // await newTradeEngine.setMorpherMintingLimiter(
    //   contract.MorpherMintingLimiter.address
    // );
  }


  if (
    addressesAndRoles[chain].contracts.MorpherTradeEngine.oldAddresses ==
    undefined
  ) {
    addressesAndRoles[chain].contracts.MorpherTradeEngine.oldAddresses = [];
  }
  addressesAndRoles[chain].contracts.MorpherTradeEngine.oldAddresses.push({
    address: contracts.MorpherTradeEngine.address,
    replacedOn: Date.now(),
  });
  addressesAndRoles[chain].contracts.MorpherTradeEngine.address =
    newTradeEngine.address;
  //print the new addressesAndRoles object
  console.log(JSON.stringify(addressesAndRoles, undefined, 2));
  return callback();
};

const keypress = async () => {
  process.stdin.setRawMode(true);
  return new Promise((resolve) =>
    process.stdin.once("data", () => {
      process.stdin.setRawMode(false);
      resolve();
    })
  );
};

const waitForAccount = async (account) => {
  let [currentAccount] = await web3.eth.getAccounts();
  if (account != currentAccount) {
    console.log(
      "Please select account " +
        account +
        "! Current Account: " +
        currentAccount
    );
    await keypress();
    [currentAccount] = await web3.eth.getAccounts();
    if (account != currentAccount) {
      await waitForAccount(account);
    }
  }
};
