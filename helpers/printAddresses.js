const contracts = [
  "MorpherAccessControl",
  "MorpherAdmin",
  "MorpherAdministratorProxy",
  "MorpherAirdrop",
  "MorpherBridge",
  "MorpherFaucet",
  "MorpherGovernance",
  "MorpherMintingLimiter",
  "MorpherOracle",
  "MorpherStaking",
  "MorpherState",
  "MorpherToken",
  "MorpherTradeEngine",
  "MorpherUserBlocking",
  "MorpherDeprecatedTokenMapper",
];

module.exports = async function (callback) {
  console.log("ChainID", ":", await web3.eth.getChainId());
  for (const contract of contracts) {
    try {
      console.log(contract, ":", artifacts.require(contract).address);
    } catch (e) {
      console.log(contract, ":", "NO NETWORK DETECTED");
    }
  }
};
