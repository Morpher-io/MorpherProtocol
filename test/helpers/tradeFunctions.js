const BN = require('bn.js');
function getLeverage(leverage) {
    return (new BN(leverage)).mul(new BN(100000000)).toString();
}

function roundToInteger(price) {
    return Math.round(price * Math.pow(10, 8));
}

module.exports = { getLeverage, roundToInteger };