const BN = require('bn.js');

const MorpherToken = artifacts.require("MorpherToken");
const MorpherFaucet = artifacts.require("MorpherFaucet");


const truffleAssert = require('truffle-assertions');

contract('MorpherFaucet', (accounts) => {
    
    const [deployerAddress, testAddress1, testAddress2] = accounts;

    it('can top up with MorpherFaucet', async () => {

        const morpherToken = await MorpherToken.deployed();
        const morpherFaucet = await MorpherFaucet.deployed();

        const startingBalance = await morpherToken.balanceOf(testAddress1);

        const topUpAmount = await morpherFaucet.fillUpAmount();
        assert.equal(topUpAmount.toString(), web3.utils.toWei('100','ether'));

        await morpherFaucet.topUpToken({ from: testAddress1 });

        const endingBalance = await morpherToken.balanceOf(testAddress1)        

        assert.equal(startingBalance.toString(), "0");
        assert.equal(endingBalance.toString(), web3.utils.toWei('100','ether'));
    });

    it('topup again will fail', async () => {

        const morpherToken = await MorpherToken.deployed();
        const morpherFaucet = await MorpherFaucet.deployed();

        const startingBalance = await morpherToken.balanceOf(testAddress1);

        

        await truffleAssert.fails(morpherFaucet.topUpToken({ from: testAddress1 }), truffleAssert.ErrorType.REVERT);
       
        const endingBalance = await morpherToken.balanceOf(testAddress1);
        

        assert.equal(startingBalance.toString(), endingBalance.toString());
    });

});