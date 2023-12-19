const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

const BN = require("bn.js");

function roundToInteger(price) {
    return Math.round(price * Math.pow(10, 8));
}
const deployedTimestampNumber = Number(process.env.MORPHER_TRADE_ENGINE_DEPLOYED_TIMESTAMP || 1613399217);

const INTEREST_RATES = [
    { validFrom: deployedTimestampNumber, rate: new BN(15000) },
    { validFrom: 1644491427, rate: new BN(30000) }
]

let deployedTimeStamp = new BN(deployedTimestampNumber);

const PRECISION = new BN(100000000);

contract('MorpherTradeEngine', (accounts) => {

   
    it('margin calculation works correctly', async () => {
        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        await morpherTradeEngine.add
        let createdTimestamp = Date.now() - 2592000000; //today  - 30 days
        //30 days should yield interest = price * (leverage - 1) * (days + 1) * 0.000015 percent
        //30000000000 * (200000000 - 100000000) * ( (2592000 / 86400) + 1) * (15000 / 100000000) / 100000000 percent = 13950000 is the interest on the exsting position 
        
        assert.equal((await calculateMarginInterest(new BN(roundToInteger(300)), new BN(200000000), new BN(createdTimestamp))).toString(), (await morpherTradeEngine.calculateMarginInterest(roundToInteger(300), 200000000, createdTimestamp)).toString(), 'Margin interest calculation doesnt work');
    })

});


async function calculateMarginInterest (averagePrice, averageLeverage, positionTimeStampInMs) {
    if (positionTimeStampInMs.div(new BN(1000)).lt(deployedTimeStamp)) {
        positionTimeStampInMs = deployedTimeStamp.mul(new BN(1000));
    }


    let now = new BN(Math.round(Date.now() / 1000));

    let marginInterest = averagePrice.mul(averageLeverage.sub(PRECISION));

    let blockTimestamp = new BN((await web3.eth.getBlock('latest')).timestamp);
    const diffDays = blockTimestamp
        .sub(positionTimeStampInMs.div(new BN(1000)))
        .div(new BN(86400));
    marginInterest = marginInterest.mul(diffDays.add(new BN(1)));
    marginInterest = (marginInterest.mul((await getInterestRate(Math.round(positionTimeStampInMs.div(new BN(1000)).toNumber())))).div(PRECISION)).div(PRECISION);

    return marginInterest;
};

async function getInterestRate(positionTimestamp) {

    let sumInterestRatesWeighted = new BN(0);
    let startingTimestamp = 0;
    let numInterestRates = INTEREST_RATES.length;

    // let blockTimestamp = Math.round(Date.now() / 1000);
    let blockTimestamp = (await web3.eth.getBlock('latest')).timestamp


    for (let i = 0; i < numInterestRates; i++) {
        if (i == numInterestRates - 1 || INTEREST_RATES[i + 1].validFrom > blockTimestamp) {
            //reached last interest rate
            sumInterestRatesWeighted = sumInterestRatesWeighted.add(INTEREST_RATES[i].rate.mul(new BN(blockTimestamp - INTEREST_RATES[i].validFrom)));
            if (startingTimestamp == 0) {
                startingTimestamp = INTEREST_RATES[i].validFrom;
            }
            break; //in case there are more in the future
        } else {
            //only take interest rates after the position was created
            if (INTEREST_RATES[i + 1].validFrom > positionTimestamp) {
                sumInterestRatesWeighted = sumInterestRatesWeighted.add(INTEREST_RATES[i].rate.mul(new BN(INTEREST_RATES[i + 1].validFrom - INTEREST_RATES[i].validFrom)));
                if (INTEREST_RATES[i].validFrom <= positionTimestamp) {
                    startingTimestamp = INTEREST_RATES[i].validFrom;
                }
            }
        }
    }
    return sumInterestRatesWeighted.div(new BN(blockTimestamp - startingTimestamp));

}