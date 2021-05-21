const MorpherState = artifacts.require("MorpherState");

const truffleAssert = require('truffle-assertions');

const CRYPTO_BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';
const CRYPTO_ETH = '0x5376ff169a3705b2003892fe730060ee74ec83e5701da29318221aa782271779';

contract('MorpherState', (accounts) => {
    it('test state changes and state function calls', async () => {
        const deployerAddress = accounts[0]; const addressAdministrator = accounts[1]; const testAddress2 = accounts[2];

        let morpherState = await MorpherState.deployed();

        // Grant state access to deployer and set testAddress1 as admin.
        await morpherState.grantAccess(deployerAddress, { from: deployerAddress });
        await morpherState.grantAccess(addressAdministrator, { from: deployerAddress });
        await morpherState.setGovernanceContract(deployerAddress, { from: deployerAddress });
        await morpherState.setAdministrator(addressAdministrator, { from: deployerAddress });

        // Activate the markets and test if function calls were successful.
        await morpherState.activateMarket(CRYPTO_BTC, { from: addressAdministrator });
        await morpherState.activateMarket(CRYPTO_ETH, { from: addressAdministrator });
        await morpherState.deActivateMarket(CRYPTO_ETH, { from: addressAdministrator });

        const isETHActive = await morpherState.getMarketActive(CRYPTO_ETH, { from: testAddress2 });
        const isBTCActive = await morpherState.getMarketActive(CRYPTO_BTC, { from: testAddress2 });

        assert.equal(isETHActive, false);
        assert.equal(isBTCActive, true);

        // Test max leverage change.
        await morpherState.setMaximumLeverage('500000000', { from: addressAdministrator });
        const maximumLeverage = (await morpherState.getMaximumLeverage({ from: testAddress2 })).toString();
        assert.equal(maximumLeverage, '500000000');

        // Test correct change of administrator.
        const administrator = await morpherState.getAdministrator({ from: testAddress2 });
        assert.equal(administrator, addressAdministrator);

        // Test MorpherToken minting.
        await morpherState.mint(testAddress2, '2000000', { from: addressAdministrator });
        let testAddress2Balance = (await morpherState.balanceOf(testAddress2, { from: testAddress2 })).toString();
        assert.equal(testAddress2Balance, '2000000');

        // Only state operators are allowed to call the Mint function.
        await truffleAssert.reverts(morpherState.mint(testAddress2, '2000000', { from: testAddress2 }), "Only Platform"); // fails
        await morpherState.mint(testAddress2, '3000000', { from: addressAdministrator }); // successful

        // Test state pause interaction.
        await truffleAssert.reverts(morpherState.pauseState({ from: testAddress2 }), "Caller is not the Administrator"); // fails
        await morpherState.pauseState({ from: addressAdministrator });

        await truffleAssert.reverts(morpherState.mint(testAddress2, '1000000', { from: addressAdministrator }), "Contract paused, aborting"); // fails
        await truffleAssert.reverts(morpherState.unPauseState({ from: testAddress2 }), "Caller is not the Administrator"); // fails

        await morpherState.unPauseState({ from: addressAdministrator });

        // Burn MorpherToken and assert the balances.
        await truffleAssert.reverts(morpherState.burn(testAddress2, '2000000', { from: testAddress2 }), "Only Platform"); // fails

        await morpherState.burn(testAddress2, '1000000', { from: addressAdministrator });

        testAddress2Balance = (await morpherState.balanceOf(testAddress2, { from: testAddress2 })).toString();
        assert.equal(testAddress2Balance, '4000000');

        // Test total cash supply functions.
        await truffleAssert.reverts(morpherState.setTotalInPositions('1000000000', { from: testAddress2 }), "Caller is not the Administrator"); // fails
        await morpherState.setTotalInPositions('2000000000', { from: addressAdministrator });

        let totalInPositions = (await morpherState.totalInPositions({ from: addressAdministrator })).toString();
        assert.equal(totalInPositions, '2000000000');

        await truffleAssert.reverts(morpherState.setTotalInPositions('3000000000', { from: testAddress2 }), "Caller is not the Administrator"); // fails
        await morpherState.setTotalInPositions('4000000000', { from: addressAdministrator });

        totalInPositions = (await morpherState.totalInPositions({ from: addressAdministrator })).toString();
        assert.equal(totalInPositions, '4000000000');

        // Test reward addresses functions.
        await truffleAssert.reverts(morpherState.setRewardAddress(testAddress2, { from: addressAdministrator })); // fails

        await morpherState.setRewardAddress(testAddress2, { from: deployerAddress });

        const rewardsAddress = await morpherState.morpherRewards({ from: testAddress2 });
        assert.equal(rewardsAddress, testAddress2);

        await truffleAssert.reverts(morpherState.setRewardBasisPoints(1000, { from: testAddress2 })); // fails
        await truffleAssert.reverts(morpherState.setRewardBasisPoints(65000, { from: deployerAddress })); // fails
        await truffleAssert.reverts(morpherState.setRewardBasisPoints(14000, { from: addressAdministrator })); // fails

        // Test set morpher bridge functions.
        await truffleAssert.reverts(morpherState.setMorpherBridge(deployerAddress, { from: addressAdministrator })); // fails
        await morpherState.setMorpherBridge(testAddress2, { from: deployerAddress });

        const morpherBridge = await morpherState.morpherBridge();
        assert.equal(morpherBridge, testAddress2);

        // Test sidechain merkel root test.
        await truffleAssert.reverts(morpherState.setSideChainMerkleRoot(CRYPTO_BTC, { from: addressAdministrator }), "Caller is not the Bridge"); // fails
        await morpherState.setSideChainMerkleRoot(CRYPTO_BTC, { from: testAddress2 });

        const sideChainMerkleRoot = await morpherState.getSideChainMerkleRoot();
        assert.equal(sideChainMerkleRoot, CRYPTO_BTC);

        // Test set position.
        await truffleAssert.reverts(morpherState.setPosition(addressAdministrator, CRYPTO_BTC, 12345, 1000, 0, 100, 1, 100000000, 90, { from: testAddress2 }), "Only Platform"); // fails
        await morpherState.setPosition(addressAdministrator, CRYPTO_BTC, 12345, 2000, 0, 200, 1, 100000000, 190, { from: addressAdministrator });

        const position = await morpherState.getPosition(addressAdministrator, CRYPTO_BTC, { from: testAddress2 });
        assert.equal(position._longShares.toString(), '2000');
        assert.equal(position._meanEntryPrice.toString(), '200');
        assert.equal(position._liquidationPrice.toString(), '190');
    });
});