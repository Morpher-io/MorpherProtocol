const MorpherToken = artifacts.require("MorpherToken");
const MorpherAirdrop = artifacts.require("MorpherAirdrop");

const truffleAssert = require('truffle-assertions');

contract('MorpherAirdrop', (accounts) => {
    it('test airdrop authorizations', async () => {
        const deployerAddress = accounts[0]; const testAddress1 = accounts[1]; const testAddress2 = accounts[2];

        const morpherAirdrop = await MorpherAirdrop.deployed();
        const morpherToken = await MorpherToken.deployed();

        await morpherToken.transfer(morpherAirdrop.address, '20000000', { from: deployerAddress });

        let totalAirdropAuthorized = await morpherAirdrop.totalAirdropAuthorized({ from: testAddress1 });
        let totalAirdropClaimed = await morpherAirdrop.totalAirdropClaimed({ from: testAddress2 });

        assert.equal(totalAirdropAuthorized, '0');
        assert.equal(totalAirdropClaimed, '0');

        // Test setting airdrop admins and numbers.
        await truffleAssert.reverts(morpherAirdrop.setAirdropAdmin(testAddress1, { from: testAddress1 })); // fails
        await truffleAssert.reverts(morpherAirdrop.setAirdropAuthorized(testAddress1, '10000', { from: testAddress1 })); // fails

        await morpherAirdrop.setAirdropAuthorized(testAddress1, '10000', { from: deployerAddress });
        await morpherAirdrop.setAirdropAuthorized(testAddress2, '450000', { from: deployerAddress });

        totalAirdropAuthorized = await morpherAirdrop.totalAirdropAuthorized({ from: testAddress1 });
        totalAirdropClaimed = await morpherAirdrop.totalAirdropClaimed({ from: testAddress1 });
        assert.equal(totalAirdropAuthorized, '460000');
        assert.equal(totalAirdropClaimed, '0');

        let airdropAuthorized1 = await morpherAirdrop.getAirdropAuthorized(testAddress1, { from: testAddress2 });
        let airdropAuthorized2 = await morpherAirdrop.getAirdropAuthorized(testAddress2, { from: testAddress1 });
        assert.equal(airdropAuthorized1, '10000');
        assert.equal(airdropAuthorized2, '450000');

        // Test airdrop claim.
        await morpherAirdrop.claimSomeAirdrop('150000', { from: testAddress2 });
        let airdropClaimed2 = await morpherAirdrop.getAirdropClaimed(testAddress2, { from: testAddress2 });
        airdropAuthorized2 = await morpherAirdrop.getAirdropAuthorized(testAddress2, { from: testAddress1 });
        totalAirdropClaimed = await morpherAirdrop.totalAirdropClaimed({ from: testAddress1 });
        assert.equal(airdropClaimed2, '150000');
        assert.equal(airdropAuthorized2, '450000');
        assert.equal(totalAirdropClaimed, '150000');

        await morpherAirdrop.setAirdropAuthorized(testAddress2, '400000', { from: deployerAddress });
        totalAirdropClaimed = await morpherAirdrop.totalAirdropClaimed({ from: testAddress1 });
        assert.equal(totalAirdropClaimed, '150000');

        totalAirdropAuthorized = await morpherAirdrop.totalAirdropAuthorized({ from: testAddress1 });
        airdropAuthorized2 = await morpherAirdrop.getAirdropAuthorized(testAddress2, { from: testAddress2 });
        assert.equal(totalAirdropAuthorized, '410000');
        assert.equal(airdropAuthorized2, '400000');

        await truffleAssert.reverts(morpherAirdrop.adminSendSomeAirdrop(testAddress2, '400000', { from: deployerAddress })); // fails
        await morpherAirdrop.adminSendSomeAirdrop(testAddress2, '100000', { from: deployerAddress });
        totalAirdropClaimed = await morpherAirdrop.totalAirdropClaimed({ from: testAddress1 });
        assert.equal(totalAirdropClaimed, '250000');

        await morpherAirdrop.setAirdropAuthorized(testAddress2, '420000', { from: deployerAddress });
        await morpherAirdrop.adminSendAirdrop(testAddress2, { from: deployerAddress });
        totalAirdropClaimed = await morpherAirdrop.totalAirdropClaimed({ from: testAddress1 });
        assert.equal(totalAirdropClaimed, '420000');

        airdropClaimed2 = await morpherAirdrop.getAirdropClaimed(testAddress2, { from: testAddress2 });
        airdropAuthorized2 = await morpherAirdrop.getAirdropAuthorized(testAddress2, { from: testAddress2 });
        assert.equal(airdropClaimed2, '420000');
        assert.equal(airdropAuthorized2, '420000');

        await morpherAirdrop.claimAirdrop({ from: testAddress1 });

        airdropClaimed1 = await morpherAirdrop.getAirdropClaimed(testAddress1, { from: testAddress1 });
        airdropAuthorized1 = await morpherAirdrop.getAirdropAuthorized(testAddress1, { from: testAddress1 });
        assert.equal(airdropClaimed1, '10000');
        assert.equal(airdropAuthorized1, '10000');
    });
});