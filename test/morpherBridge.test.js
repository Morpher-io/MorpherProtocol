const MorpherToken = artifacts.require("MorpherToken");
const MorpherBridge = artifacts.require("MorpherBridge");

const truffleAssert = require('truffle-assertions');

const { MerkleTree } = require('merkletreejs')

const { keccak256 } = require('ethereumjs-util');
const { BN } = require("bn.js")


contract('MorpherBridge: withdrawal tests', (accounts) => {

    it('is possible to change 24hours limits', async() => {
        const morpherBridge = await MorpherBridge.deployed();
        let result = await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei('1', 'ether'));
        await truffleAssert.eventEmitted(result, 'WithdrawLimitDailyChanged');
        let currentLimit = await morpherBridge.withdrawalLimitDaily();
        assert.equal(currentLimit.toString(), web3.utils.toWei('1','ether'));

        //set it back
        await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei('200000', 'ether'));
    });

    it('is possible to change 30 days limits', async() => {
        const morpherBridge = await MorpherBridge.deployed();
        let result = await morpherBridge.updateWithdrawLimitMonthly(web3.utils.toWei('1', 'ether'));
        await truffleAssert.eventEmitted(result, 'WithdrawLimitMonthlyChanged');
        let currentLimit = await morpherBridge.withdrawalLimitMonthly();
        assert.equal(currentLimit.toString(), web3.utils.toWei('1','ether'));

        //set it back
        await morpherBridge.updateWithdrawLimitMonthly(web3.utils.toWei('1000000', 'ether'));
    });

    it('test withdrawal trustlessTransferFromLinkedChain', async () => {
        const [deployer, addr1, addr2, addr3, addr4] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal

        const leaves = [];
        leaves.push(web3.utils.soliditySha3(addr1, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr2, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr3, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr4, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf

        leaves.sort();

        const nearestPowerOf2 = Math.ceil(Math.log(leaves.length) / Math.log(2));

        const zeroHash = '0x0000000000000000000000000000000000000000000000000000000000000000';

        // Create empty array to input the necessary amount of leaves.
        const leavesOut = [];

        // Fill new array with existing leaves and trivial leaves if needed.
        for (let i = 0; i < leaves.length; i++) {
            leavesOut[i] = leaves[i];
        }

        for (let k = leaves.length; k < 2 ** nearestPowerOf2; k++) {
            leavesOut.push(zeroHash);
        }


        // Initiate helper MerkleTree class for calculations.
        const merkleTree = new MerkleTree(leavesOut, keccak256, { sortPairs: true })
        const newMerkleTreeRoot = '0x' + merkleTree.getRoot().toString('hex');

        await morpherBridge.updateSideChainMerkleRoot(newMerkleTreeRoot);
        await morpherBridge.set24HourWithdrawLimit(web3.utils.toWei("20", "ether"));

        const addrBalanceBeforeClaim = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeClaim.toString(), "0");

        const proofForAddr1 = merkleTree.getHexProof(web3.utils.soliditySha3(addr1, web3.utils.toWei("20", "ether")));

        let result = await morpherBridge.trustlessTransferFromLinkedChain(web3.utils.toWei("20", "ether"), web3.utils.toWei("20", "ether"), proofForAddr1, { from: addr1 });
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");

        const addr1BalanceAfterClaim = await morpherToken.balanceOf(addr1);

        assert.equal(addr1BalanceAfterClaim.toString(), web3.utils.toWei('20', 'ether'));

    });


    it('test withdrawal limit global for all users', async () => {
        const [deployer, addr1, addr2, addr3, addr4] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal

        const leaves = [];
        leaves.push(web3.utils.soliditySha3(addr1, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr2, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr3, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr4, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf

        leaves.sort();

        const nearestPowerOf2 = Math.ceil(Math.log(leaves.length) / Math.log(2));

        const zeroHash = '0x0000000000000000000000000000000000000000000000000000000000000000';

        // Create empty array to input the necessary amount of leaves.
        const leavesOut = [];

        // Fill new array with existing leaves and trivial leaves if needed.
        for (let i = 0; i < leaves.length; i++) {
            leavesOut[i] = leaves[i];
        }

        for (let k = leaves.length; k < 2 ** nearestPowerOf2; k++) {
            leavesOut.push(zeroHash);
        }


        // Initiate helper MerkleTree class for calculations.
        const merkleTree = new MerkleTree(leavesOut, keccak256, { sortPairs: true })
        const newMerkleTreeRoot = '0x' + merkleTree.getRoot().toString('hex');

        await morpherBridge.updateSideChainMerkleRoot(newMerkleTreeRoot);
        await morpherBridge.set24HourWithdrawLimit(web3.utils.toWei("1", "ether"));

        const addrBalanceBeforeClaim = await morpherToken.balanceOf(addr2);
        assert.equal(addrBalanceBeforeClaim.toString(), "0");

        const proofForAddr2 = merkleTree.getHexProof(web3.utils.soliditySha3(addr2, web3.utils.toWei("20", "ether")));

        await truffleAssert.fails(
            morpherBridge.trustlessTransferFromLinkedChain(web3.utils.toWei("20", "ether"), web3.utils.toWei("20", "ether"), proofForAddr2, { from: addr2 }),
            truffleAssert.ErrorType.REVERT,
            "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit. Please try again in a few hours."
        );

        const addr1BalanceAfterClaim = await morpherToken.balanceOf(addr2);

        assert.equal(addr1BalanceAfterClaim.toString(), '0');

    });



    it('test withdrawal limit 24 hours per user', async () => {
        const [deployer, addr1, addr2, addr3, addr4] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal

        const leaves = [];
        let current24hLimit = new BN(await morpherBridge.withdrawalLimitDaily());

        await morpherBridge.set24HourWithdrawLimit(web3.utils.toWei("1000000000", "ether"));

        leaves.push(web3.utils.soliditySha3(addr2, current24hLimit.add(new BN(1)))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr3, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf

        leaves.sort();

        const nearestPowerOf2 = Math.ceil(Math.log(leaves.length) / Math.log(2));

        const zeroHash = '0x0000000000000000000000000000000000000000000000000000000000000000';

        // Create empty array to input the necessary amount of leaves.
        const leavesOut = [];

        // Fill new array with existing leaves and trivial leaves if needed.
        for (let i = 0; i < leaves.length; i++) {
            leavesOut[i] = leaves[i];
        }

        for (let k = leaves.length; k < 2 ** nearestPowerOf2; k++) {
            leavesOut.push(zeroHash);
        }


        // Initiate helper MerkleTree class for calculations.
        const merkleTree = new MerkleTree(leavesOut, keccak256, { sortPairs: true })
        const newMerkleTreeRoot = '0x' + merkleTree.getRoot().toString('hex');

        await morpherBridge.updateSideChainMerkleRoot(newMerkleTreeRoot);

        const addrBalanceBeforeClaim = await morpherToken.balanceOf(addr2);
        assert.equal(addrBalanceBeforeClaim.toString(), "0");

        const proofForAddr2 = merkleTree.getHexProof(web3.utils.soliditySha3(addr2, current24hLimit.add(new BN(1))));

        let result = await morpherBridge.trustlessTransferFromLinkedChain(current24hLimit, current24hLimit.add(new BN(1)), proofForAddr2, { from: addr2 }); //transfer the limit
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");


        //we transferred the maximum limit for 24 hours, another token would trigger an exception
        await truffleAssert.fails(
            morpherBridge.trustlessTransferFromLinkedChain("1", current24hLimit.add(new BN(1)), proofForAddr2, { from: addr2 }),
            truffleAssert.ErrorType.REVERT,
            "MorpherBridge: Withdrawal Amount exceeds daily limit"
        );

        const addr1BalanceAfterClaim = await morpherToken.balanceOf(addr2);

        assert.equal(addr1BalanceAfterClaim.toString(), current24hLimit.toString());

        //another user still can transfer


        const proofForAddr3 = merkleTree.getHexProof(web3.utils.soliditySha3(addr3, web3.utils.toWei('20', 'ether')));
        result = await morpherBridge.trustlessTransferFromLinkedChain("1", web3.utils.toWei('20', 'ether'), proofForAddr3, { from: addr3 }); //transfer the limit
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");


    });



    it('test withdrawal limit 30 days per user', async () => {
        const [deployer, addr1, addr2, addr3, addr4, addr5] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal

        const leaves = [];
        let settingsLimits24Hours = await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei('1000001', 'ether'));
        await truffleAssert.eventEmitted(settingsLimits24Hours, 'WithdrawLimitDailyChanged');
        let currentDailyLimit = await morpherBridge.withdrawalLimitDaily();
        assert.equal(currentDailyLimit.toString(), web3.utils.toWei('1000001', 'ether'));
        let currentMonthlyLimit = new BN(await morpherBridge.withdrawalLimitMonthly());

        leaves.push(web3.utils.soliditySha3(addr4, currentMonthlyLimit.add(new BN(1)))); //packaging 20 MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr5, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf

        leaves.sort();

        const nearestPowerOf2 = Math.ceil(Math.log(leaves.length) / Math.log(2));

        const zeroHash = '0x0000000000000000000000000000000000000000000000000000000000000000';

        // Create empty array to input the necessary amount of leaves.
        const leavesOut = [];

        // Fill new array with existing leaves and trivial leaves if needed.
        for (let i = 0; i < leaves.length; i++) {
            leavesOut[i] = leaves[i];
        }

        for (let k = leaves.length; k < 2 ** nearestPowerOf2; k++) {
            leavesOut.push(zeroHash);
        }


        // Initiate helper MerkleTree class for calculations.
        const merkleTree = new MerkleTree(leavesOut, keccak256, { sortPairs: true })
        const newMerkleTreeRoot = '0x' + merkleTree.getRoot().toString('hex');

        await morpherBridge.updateSideChainMerkleRoot(newMerkleTreeRoot);

        const addrBalanceBeforeClaim = await morpherToken.balanceOf(addr4);
        assert.equal(addrBalanceBeforeClaim.toString(), "0");

        const proofForAddr4 = merkleTree.getHexProof(web3.utils.soliditySha3(addr4, currentMonthlyLimit.add(new BN(1))));

        let result = await morpherBridge.trustlessTransferFromLinkedChain(currentMonthlyLimit, currentMonthlyLimit.add(new BN(1)), proofForAddr4, { from: addr4 }); //transfer the limit
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");


        //we transferred the maximum limit for 24 hours, another token would trigger an exception
        await truffleAssert.fails(
            morpherBridge.trustlessTransferFromLinkedChain("1", currentMonthlyLimit.add(new BN(1)), proofForAddr4, { from: addr4 }),
            truffleAssert.ErrorType.REVERT,
            "MorpherBridge: Withdrawal Amount exceeds monthly limit"
        );

        const addrBalanceAfterClaim = await morpherToken.balanceOf(addr4);

        assert.equal(addrBalanceAfterClaim.toString(), currentMonthlyLimit.toString());

        //another user still can transfer
        const proofForAddr5 = merkleTree.getHexProof(web3.utils.soliditySha3(addr5, web3.utils.toWei('20', 'ether')));
        result = await morpherBridge.trustlessTransferFromLinkedChain("1", web3.utils.toWei('20', 'ether'), proofForAddr5, { from: addr5 }); //transfer the limit
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");

    });


});