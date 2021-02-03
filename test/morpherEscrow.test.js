const MorpherToken = artifacts.require("MorpherToken");
const MorpherState = artifacts.require("MorpherState");
const MorpherEscrow = artifacts.require("MorpherEscrow");

const { advanceTimeAndBlock } = require('../helpers/utils');

contract('MorpherEscrow', (accounts) => {
    it('test MorpherEscrow fund releases', async () => {
        const deployerAddress = accounts[0]; const testAddress1 = accounts[1]; const testAddress2 = accounts[2];

        const morpherToken = await MorpherToken.deployed();
        const morpherEscrow = await MorpherEscrow.deployed();
        let morpherState = await MorpherState.deployed();

        // Grant access and enable transfers for the accounts.
        await morpherState.grantAccess(deployerAddress);
        await morpherState.grantAccess(morpherEscrow.address);
        await morpherState.enableTransfers(deployerAddress);
        await morpherState.enableTransfers(morpherEscrow.address);

        // Transfer morpher token to the escrow address
        await morpherToken.transfer(morpherEscrow.address, '21000000000000000000000000', { from: deployerAddress });
        await morpherEscrow.setRecipientAddress(testAddress1, { from: deployerAddress });

        let morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '21000000000000000000000000');

        await morpherEscrow.releaseFromEscrow({ from: testAddress2 });

        morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '21000000000000000000000000');

        // Simulate one month wait in blockchain (3600s * 24 hours * 31 days as a threshold).
        await advanceTimeAndBlock(3600 * 24 * 31);

        await morpherEscrow.releaseFromEscrow({ from: testAddress2 });

        morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '11000000000000000000000000');

        await morpherEscrow.releaseFromEscrow({ from: testAddress2 });

        morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '11000000000000000000000000');

        // Simulate one month wait in blockchain (3600s * 24 hours * 31 days as a threshold).
        await advanceTimeAndBlock(3600 * 24 * 31);

        await morpherEscrow.releaseFromEscrow({ from: testAddress2 });

        morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '1000000000000000000000000');

        await morpherEscrow.releaseFromEscrow({ from: testAddress2 });

        morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '1000000000000000000000000');

        // Simulate one month wait in blockchain (3600s * 24 hours * 31 days as a threshold).
        await advanceTimeAndBlock(3600 * 24 * 31);

        await morpherEscrow.releaseFromEscrow({ from: testAddress2 });

        morpherEscrowBalance = await morpherToken.balanceOf(morpherEscrow.address, { from: testAddress2 });
        assert.equal(morpherEscrowBalance.toString(), '0');

        testAddress1Balance = await morpherToken.balanceOf(testAddress1, { from: testAddress2 });
        assert.equal(testAddress1Balance.toString(), '21000000000000000000000000');
    });
});