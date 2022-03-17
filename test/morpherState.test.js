const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

const truffleAssert = require('truffle-assertions');

const CRYPTO_BTC = web3.utils.sha3("CRYPTO_BTC");
const CRYPTO_ETH = web3.utils.sha3("CRYPTO_ETH");
const ADMINISTRATOR_ROLE = web3.utils.sha3("ADMINISTRATOR_ROLE");
const MINTER_ROLE = web3.utils.sha3("MINTER_ROLE");
const PAUSER_ROLE = web3.utils.sha3("PAUSER_ROLE");
const BURNER_ROLE = web3.utils.sha3("BURNER_ROLE");

contract('MorpherState', (accounts) => {
    it('test state changes and state function calls', async () => {
        const [deployerAddress, addressAdministrator, testAddress2] = accounts;

        let morpherState = await MorpherState.deployed();
        let morpherAccessControl = await MorpherAccessControl.deployed();
        let morpherToken = await MorpherToken.deployed();

        // Grant state access to deployer and set testAddress1 as admin.
        await morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, addressAdministrator);

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

        await morpherAccessControl.revokeRole(ADMINISTRATOR_ROLE, addressAdministrator);

        await morpherAccessControl.grantRole(MINTER_ROLE, addressAdministrator);
        // Test MorpherToken minting.

        await morpherToken.mint(testAddress2, '2000000', { from: addressAdministrator });
        let testAddress2Balance = (await morpherToken.balanceOf(testAddress2, { from: testAddress2 })).toString();
        assert.equal(testAddress2Balance, '2000000');

        // Only state operators are allowed to call the Mint function.
        await truffleAssert.reverts(morpherToken.mint(testAddress2, '2000000', { from: testAddress2 }), "MorpherState: Only Platform is allowed to execute operation."); // fails
        await morpherState.mint(testAddress2, '3000000', { from: addressAdministrator }); // successful

        // Test state pause interaction.
        await truffleAssert.reverts(morpherToken.pause({ from: testAddress2 }), "Caller is not the Administrator"); // fails

        await morpherAccessControl.grantRole(PAUSER_ROLE, addressAdministrator);
        await morpherToken.pause({ from: addressAdministrator });

        await truffleAssert.reverts(morpherToken.mint(testAddress2, '1000000', { from: addressAdministrator }), "Contract paused, aborting"); // fails
        await truffleAssert.reverts(morpherToken.unpause({ from: testAddress2 }), "Caller is not the Administrator"); // fails

        await morpherToken.unpause({ from: addressAdministrator });

        // Burn MorpherToken and assert the balances.
        await truffleAssert.reverts(morpherToken.burn(testAddress2, '2000000', { from: testAddress2 }), "Only Platform"); // fails

        await morpherAccessControl.grantRole(BURNER_ROLE, addressAdministrator);
        await morpherToken.burn(testAddress2, '1000000', { from: addressAdministrator });

        // testAddress2Balance = (await morpherState.balanceOf(testAddress2, { from: testAddress2 })).toString();
        // assert.equal(testAddress2Balance, '4000000');

        // // Test total cash supply functions.
        // await truffleAssert.reverts(morpherState.setTotalInPositions('1000000000', { from: testAddress2 }), "Caller is not the Administrator"); // fails
        // await morpherState.setTotalInPositions('2000000000', { from: addressAdministrator });

        // let totalInPositions = (await morpherState.totalInPositions({ from: addressAdministrator })).toString();
        // assert.equal(totalInPositions, '2000000000');

        // await truffleAssert.reverts(morpherState.setTotalInPositions('3000000000', { from: testAddress2 }), "Caller is not the Administrator"); // fails
        // await morpherState.setTotalInPositions('4000000000', { from: addressAdministrator });

        // totalInPositions = (await morpherState.totalInPositions({ from: addressAdministrator })).toString();
        // assert.equal(totalInPositions, '4000000000');

        // // Test reward addresses functions.
        // await truffleAssert.reverts(morpherState.setRewardAddress(testAddress2, { from: addressAdministrator })); // fails

        // await morpherState.setRewardAddress(testAddress2, { from: deployerAddress });

        // const rewardsAddress = await morpherState.morpherRewards({ from: testAddress2 });
        // assert.equal(rewardsAddress, testAddress2);

        // await truffleAssert.reverts(morpherState.setRewardBasisPoints(1000, { from: testAddress2 })); // fails
        // await truffleAssert.reverts(morpherState.setRewardBasisPoints(65000, { from: deployerAddress })); // fails
        // await truffleAssert.reverts(morpherState.setRewardBasisPoints(14000, { from: addressAdministrator })); // fails

        // // Test set morpher bridge functions.
        // await truffleAssert.reverts(morpherState.setMorpherBridge(deployerAddress, { from: addressAdministrator })); // fails
        // await morpherState.setMorpherBridge(testAddress2, { from: deployerAddress });

        // const morpherBridge = await morpherState.morpherBridge();
        // assert.equal(morpherBridge, testAddress2);

        // // Test sidechain merkel root test.
        // await truffleAssert.reverts(morpherState.setSideChainMerkleRoot(CRYPTO_BTC, { from: addressAdministrator }), "Caller is not the Bridge"); // fails
        // await morpherState.setSideChainMerkleRoot(CRYPTO_BTC, { from: testAddress2 });

        // const sideChainMerkleRoot = await morpherState.getSideChainMerkleRoot();
        // assert.equal(sideChainMerkleRoot, CRYPTO_BTC);

        // // Test set position.
        // await truffleAssert.reverts(morpherState.setPosition(addressAdministrator, CRYPTO_BTC, 12345, 1000, 0, 100, 1, 100000000, 90, { from: testAddress2 }), "Only Platform"); // fails
        // await morpherState.setPosition(addressAdministrator, CRYPTO_BTC, 12345, 2000, 0, 200, 1, 100000000, 190, { from: addressAdministrator });

        // const position = await morpherState.getPosition(addressAdministrator, CRYPTO_BTC, { from: testAddress2 });
        // assert.equal(position._longShares.toString(), '2000');
        // assert.equal(position._meanEntryPrice.toString(), '200');
        // assert.equal(position._liquidationPrice.toString(), '190');
    });
});