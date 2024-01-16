//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

interface IOracle {
    function decimals() external view returns (uint8);
    function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IUniswapV3Pool {
    function slot0(
  ) external view returns (
    uint160 sqrtPriceX96, 
    int24 tick, 
    uint16 observationIndex, 
    uint16 observationCardinality, 
    uint16 observationCardinalityNext, 
    uint8 feeProtocol, 
    bool unlocked
  );
}

interface UniswapQuoter {

    function factory() external view returns(address);
    function WETH9() external view returns(address);

    

    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external view returns (uint256 amountIn);

     
}

interface ERC20 {
    function decimals() external view returns (uint);
}

contract MorpherPriceOracle is IOracle {


    address mphToken = 0x322531297FAb2e8FeAf13070a7174a83117ADAd4;
    address wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    address uniswapQuoterAddress = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    constructor(address _mphToken, address _wmatic, address _uniswapQuoter) {
        mphToken = _mphToken;
        wmatic = _wmatic;
        uniswapQuoterAddress = _uniswapQuoter;
    }
     
     function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        UniswapQuoter quoter = UniswapQuoter(uniswapQuoterAddress);
        return IUniswapV3Pool(PoolAddress.computeAddress(quoter.factory(), PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    function decimals() external override view returns (uint8) {
        return uint8(ERC20(mphToken).decimals());
    }

    function latestRoundData()
    external
    override
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        IUniswapV3Pool pool = getPool(mphToken, wmatic, 3000);
        (uint sqrtPriceX96,,,,,,) = pool.slot0();
        return (0,int(uint(sqrtPriceX96) * uint(sqrtPriceX96)*(1e18) >> (96 * 2)),0,block.timestamp,0);
    }
} 