require("@nomiclabs/hardhat-truffle5");


/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    }
  },
  solidity: "0.8.11",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
};
