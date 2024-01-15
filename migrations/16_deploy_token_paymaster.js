const MorpherPriceOracle = artifacts.require("MorpherPriceOracle");
const MorpherTokenPaymaster = artifacts.require("MorpherTokenPaymaster");


module.exports = async function (deployer, network, accounts) {

  //TODO change that for polygon mainnet [mphtoken, wmatic, uniswaprouter]
  // await deployer.deploy(MorpherPriceOracle, '0x322531297FAb2e8FeAf13070a7174a83117ADAd4','0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889','0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6');
  // const morpherPriceOracle = await MorpherPriceOracle.deployed();

  // console.log({oracleAddress: morpherPriceOracle.address});
  const morpherPriceOracle = {
    address: '0xB207eC39332A521086fF8e04a7FCab51b341DfAa'
  }

  //TODO change that for polygon mainnet
  //change the imports in eth-infinitism to openzeppelin-contracts-5
  await deployer.deploy(MorpherTokenPaymaster, '0x322531297FAb2e8FeAf13070a7174a83117ADAd4','0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789','0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889','0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45',['100000000000000000000000000',100000000000000,20000,60],[60,morpherPriceOracle.address,'0x0000000000000000000000000000000000000000',true,false,false,100000],[100000000,300,100], accounts[0])
  const morpherTokenPaymaster = await MorpherTokenPaymaster.deployed();

  console.log({morpherPriceOracle: morpherPriceOracle.address, morpherTokenPaymaster: morpherTokenPaymaster.address})
};


/**
 * 
 *   /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            ))
        );
    }
 */

    /** BasePaymaster
     * import "../../../openzeppelin-contracts-5/contracts/access/Ownable.sol";
import "../../../openzeppelin-contracts-5/contracts/utils/introspection/IERC165.sol";
import "../interfaces/IPaymaster.sol";
import "../interfaces/IEntryPoint.sol";
import "./Helpers.sol";
import "./UserOperationLib.sol";
     */