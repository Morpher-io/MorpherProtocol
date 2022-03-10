const BN = require('bn.js');

const MorpherToken = artifacts.require("MorpherToken");
const MorpherState = artifacts.require("MorpherState");


const truffleAssert = require('truffle-assertions');

contract('MorpherToken', (accounts) => {
    
    const [deployerAddress, testAddress1, testAddress2] = accounts;

    it('Can transfer/approve/transferFrom Tokens', async () => {

        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();

        // Grant access and enable transfers for test accounts.
        await morpherState.grantAccess(testAddress1);
        await morpherState.grantAccess(testAddress2);
        await morpherState.enableTransfers(testAddress1);
        await morpherState.enableTransfers(testAddress2);

        const deployerStartingTokenBalance = await morpherState.balanceOf(deployerAddress);

        const toTestAddress1 = web3.utils.toWei(new BN(1), 'ether'); //1 MPH
        const toTestAddress2 = web3.utils.toWei(new BN(0.1), 'ether'); //0.1 MPH
        const toTestAddress2FromTestAddress1 = web3.utils.toWei(new BN(0.01), 'ether'); //0.01 MPH
        const toTestAddress2FromTestAddress1Approve = web3.utils.toWei(new BN(0.001), 'ether'); //0.001 MPH

        await morpherToken.transfer(testAddress1, toTestAddress1, { from: deployerAddress });
        await morpherToken.transfer(testAddress2, toTestAddress2, { from: deployerAddress });
        await morpherToken.transfer(testAddress2, toTestAddress2FromTestAddress1, { from: testAddress1 });
        await morpherToken.approve(testAddress2, toTestAddress2FromTestAddress1Approve, { from: testAddress1 });
        await morpherToken.transferFrom(testAddress1, testAddress2, toTestAddress2FromTestAddress1Approve, { from: testAddress2 });

        // ASSERTS:
        const deployerBalance = await morpherState.balanceOf(deployerAddress);
        const testAddress1Balance = await morpherState.balanceOf(testAddress1)
        const testAddress2Balance = await morpherState.balanceOf(testAddress2);
        const allowance = await morpherState.getAllowance(testAddress1, testAddress2);

        assert.equal(deployerBalance.toString(), (deployerStartingTokenBalance.sub(toTestAddress1).sub(toTestAddress2).sub(toTestAddress2FromTestAddress1Approve)).toString()); // 4.249×10^26
        assert.equal(testAddress1Balance.toString(), toTestAddress1.sub(toTestAddress2FromTestAddress1).sub(toTestAddress2FromTestAddress1Approve).toString()); // 9.09x10^22
        assert.equal(testAddress2Balance.toString(), toTestAddress2.add(toTestAddress2FromTestAddress1).add(toTestAddress2FromTestAddress1Approve).toString()); // 9.1x10^21
        assert.equal(allowance.toString(), '0'); // 9x10^20
    });

    it("Transferring too many tokens will fail", async () => {

        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();

        // Grant access and enable transfers for test accounts.
        await morpherState.grantAccess(testAddress1);
        await morpherState.grantAccess(testAddress2);
        await morpherState.enableTransfers(testAddress1);
        await morpherState.enableTransfers(testAddress2);

        const deployerStartingTokenBalance = await morpherState.balanceOf(deployerAddress);

        const toTestAddress1 = deployerStartingTokenBalance.add(new BN(1)); //1 MPH more than I own

        truffleAssert.fails(morpherToken.transfer(testAddress1, toTestAddress1, { from: deployerAddress }), truffleAssert.ErrorType.REVERT, 'ERC20: transfer amount exceeds balance');

        // ASSERTS: token balance must have stayed the same, no transfer happened
        const deployerBalance = await morpherState.balanceOf(deployerAddress);
        assert.equal(deployerBalance.toString(), deployerStartingTokenBalance.toString());
    });

    it("transferFrom too many tokens will fail", async () => {

        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();

        // Grant access and enable transfers for test accounts.
        await morpherState.grantAccess(testAddress1);
        await morpherState.grantAccess(testAddress2);
        await morpherState.enableTransfers(testAddress1);
        await morpherState.enableTransfers(testAddress2);

        const deployerStartingTokenBalance = await morpherState.balanceOf(deployerAddress);

        const toTestAddress1 = deployerStartingTokenBalance.add(new BN(1)); //1 MPH more than I own
        morpherToken.approve(testAddress1, toTestAddress1, { from: deployerAddress });
        truffleAssert.fails(morpherToken.transferFrom(deployerAddress, testAddress1, toTestAddress1, {from: deployerAddress}), truffleAssert.ErrorType.REVERT, 'ERC20: transfer amount exceeds balance');

        // ASSERTS: token balance must have stayed the same, no transfer happened
        const deployerBalance = await morpherState.balanceOf(deployerAddress);
        assert.equal(deployerBalance.toString(), deployerStartingTokenBalance.toString());
    });

    it("transferFrom without approval will fail", async () => {

        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();

        // Grant access and enable transfers for test accounts.
        await morpherState.grantAccess(testAddress1);
        await morpherState.grantAccess(testAddress2);
        await morpherState.enableTransfers(testAddress1);
        await morpherState.enableTransfers(testAddress2);

        const deployerStartingTokenBalance = await morpherState.balanceOf(deployerAddress);

        const approvalAmount = '0';
        const sendingAmount = '1';

        morpherToken.approve(testAddress1, approvalAmount, { from: deployerAddress });
        truffleAssert.fails(morpherToken.transferFrom(deployerAddress, testAddress1, sendingAmount, {from: deployerAddress}), truffleAssert.ErrorType.REVERT, 'ERC20: transfer amount exceeds allowance');

        // ASSERTS: token balance must have stayed the same, no transfer happened
        const deployerBalance = await morpherState.balanceOf(deployerAddress);
        assert.equal(deployerBalance.toString(), deployerStartingTokenBalance.toString());
    });
});