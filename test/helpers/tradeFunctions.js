const BN = require('bn.js');
function getLeverage(leverage) {
    return (new BN(leverage)).mul(new BN(100000000)).toString();
}

module.exports = { getLeverage };