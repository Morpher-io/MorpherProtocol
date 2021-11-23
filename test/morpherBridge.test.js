const MorpherToken = artifacts.require("MorpherToken");
const MorpherBridge = artifacts.require("MorpherBridge");

const truffleAssert = require('truffle-assertions');

const { MerkleTree } = require('merkletreejs')

const { keccak256 } = require('ethereumjs-util');
const { BN } = require("bn.js")


contract('MorpherBridge: change Limits tests', (accounts) => {

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

    it('is possible to change 365 days limits', async() => {
        const morpherBridge = await MorpherBridge.deployed();
        let result = await morpherBridge.updateWithdrawLimitYearly(web3.utils.toWei('1', 'ether'));
        await truffleAssert.eventEmitted(result, 'WithdrawLimitYearlyChanged');
        let currentLimit = await morpherBridge.withdrawalLimitYearly();
        assert.equal(currentLimit.toString(), web3.utils.toWei('1','ether'));

        //set it back
        await morpherBridge.updateWithdrawLimitYearly(web3.utils.toWei('5000000', 'ether'));
    });
});

contract('MorpherBridge: transferToSidechain tests', (accounts) => {

    /**
     * tests first if up to 24h withdrawal limit works
     * 
     * the tests if going beyond the withdrawal limit fails
     */
    it('test withdrawal transferToSideChain daily limit', async () => {
        const [deployer, addr1] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal
        
        await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei("20", "ether"));
        await morpherToken.transfer(addr1, web3.utils.toWei("20","ether"), { from: deployer });

        const addrBalanceBeforeBurn = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeBurn.toString(), web3.utils.toWei('20', 'ether'));


        let result = await morpherBridge.transferToSideChain(web3.utils.toWei("20", "ether"), { from: addr1 });
        await truffleAssert.eventEmitted(result, "TransferToLinkedChain");
        const addr1BalanceAfterBurn = await morpherToken.balanceOf(addr1);
        assert.equal(addr1BalanceAfterBurn.toString(), web3.utils.toWei('0', 'ether'));

        //now lets go beyond the 24h withdrawal limit
        await morpherToken.transfer(addr1, web3.utils.toWei("1","ether"), { from: deployer });

        const addrBalanceBeforeBurn1 = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeBurn1.toString(), web3.utils.toWei('1', 'ether'));

        await truffleAssert.fails(
                    morpherBridge.transferToSideChain(web3.utils.toWei("1", "ether"), { from: addr1 }),
                    truffleAssert.ErrorType.REVERT,
                    "MorpherBridge: Withdrawal Amount exceeds daily limit"
                );

        const addr1BalanceAfterBurn1 = await morpherToken.balanceOf(addr1);

        //nothing changed, the burn didn't happen, send the 1mph back because we need a clean account
        assert.equal(addr1BalanceAfterBurn1.toString(), web3.utils.toWei('1', 'ether'));
        await morpherToken.transfer(deployer, web3.utils.toWei("1","ether"), { from: addr1 });

    });


    /**
     * tests first if up to 30 days withdrawal limit works
     * 
     * the tests if going beyond the withdrawal limit fails
     */
    it('test withdrawal transferToSideChain 30 days limit', async () => {
        const [deployer, addr1] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal
        
        await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei("2000000", "ether"));
        await morpherBridge.updateWithdrawLimitMonthly(web3.utils.toWei("40", "ether")); //double it from the daily limit test above
        await morpherToken.transfer(addr1, web3.utils.toWei("20","ether"), { from: deployer });

        const addrBalanceBeforeBurn = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeBurn.toString(), web3.utils.toWei('20', 'ether'));


        let result = await morpherBridge.transferToSideChain(web3.utils.toWei("20", "ether"), { from: addr1 });
        await truffleAssert.eventEmitted(result, "TransferToLinkedChain");
        const addr1BalanceAfterBurn = await morpherToken.balanceOf(addr1);
        assert.equal(addr1BalanceAfterBurn.toString(), web3.utils.toWei('0', 'ether'));

        //now lets go beyond the 24h withdrawal limit
        await morpherToken.transfer(addr1, web3.utils.toWei("1","ether"), { from: deployer });

        const addrBalanceBeforeBurn1 = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeBurn1.toString(), web3.utils.toWei('1', 'ether'));

        await truffleAssert.fails(
                    morpherBridge.transferToSideChain(web3.utils.toWei("1", "ether"), { from: addr1 }),
                    truffleAssert.ErrorType.REVERT,
                    "MorpherBridge: Withdrawal Amount exceeds monthly limit"
                );

        const addr1BalanceAfterBurn1 = await morpherToken.balanceOf(addr1);

        //nothing changed, the burn didn't happen, send the 1mph back because we need a clean account
        assert.equal(addr1BalanceAfterBurn1.toString(), web3.utils.toWei('1', 'ether'));
        await morpherToken.transfer(deployer, web3.utils.toWei("1","ether"), { from: addr1 });

    });

    /**
     * tests if up to 365 days withdrawal limit works
     * 
     * the tests if going beyond the withdrawal limit fails
     */
    it('test withdrawal transferToSideChain 365 days limit', async () => {
        const [deployer, addr1] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal
        
        await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei("2000000", "ether"));
        await morpherBridge.updateWithdrawLimitMonthly(web3.utils.toWei("2000000", "ether")); //double it from the daily limit test above
        await morpherBridge.updateWithdrawLimitYearly(web3.utils.toWei("60", "ether")); //double it from the daily limit test above
        await morpherToken.transfer(addr1, web3.utils.toWei("20","ether"), { from: deployer });

        const addrBalanceBeforeBurn = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeBurn.toString(), web3.utils.toWei('20', 'ether'));


        let result = await morpherBridge.transferToSideChain(web3.utils.toWei("20", "ether"), { from: addr1 });
        await truffleAssert.eventEmitted(result, "TransferToLinkedChain");
        const addr1BalanceAfterBurn = await morpherToken.balanceOf(addr1);
        assert.equal(addr1BalanceAfterBurn.toString(), web3.utils.toWei('0', 'ether'));

        //now lets go beyond the withdrawal limit
        await morpherToken.transfer(addr1, web3.utils.toWei("1","ether"), { from: deployer });
        const addrBalanceBeforeBurn1 = await morpherToken.balanceOf(addr1);
        assert.equal(addrBalanceBeforeBurn1.toString(), web3.utils.toWei('1', 'ether'));

        await truffleAssert.fails(
                    morpherBridge.transferToSideChain(web3.utils.toWei("1", "ether"), { from: addr1 }),
                    truffleAssert.ErrorType.REVERT,
                    "MorpherBridge: Withdrawal Amount exceeds yearly limit"
                );

        const addr1BalanceAfterBurn1 = await morpherToken.balanceOf(addr1);

        //nothing changed, the burn didn't happen, send the 1mph back because we need a clean account
        assert.equal(addr1BalanceAfterBurn1.toString(), web3.utils.toWei('1', 'ether'));
        await morpherToken.transfer(deployer, web3.utils.toWei("1","ether"), { from: addr1 });

    });
});

contract('MorpherBridge: trustlessTransferFromLinkedChain tests', (accounts) => {


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


    it('test withdrawal limit 365 days per user', async () => {
        const [deployer, addr1, addr2, addr3, addr4, addr5, addr6, addr7] = accounts;
        const morpherBridge = await MorpherBridge.deployed();
        const morpherToken = await MorpherToken.deployed();

        //setup a merkle tree to test withdrawal

        const leaves = [];
        let settingsLimits24Hours = await morpherBridge.updateWithdrawLimitDaily(web3.utils.toWei('5000001', 'ether'));
        await truffleAssert.eventEmitted(settingsLimits24Hours, 'WithdrawLimitDailyChanged');
        let currentDailyLimit = await morpherBridge.withdrawalLimitDaily();
        assert.equal(currentDailyLimit.toString(), web3.utils.toWei('5000001', 'ether'));
        let settingsLimits30Days = await morpherBridge.updateWithdrawLimitMonthly(web3.utils.toWei('5000001', 'ether'));
        await truffleAssert.eventEmitted(settingsLimits30Days, 'WithdrawLimitMonthlyChanged');
        let currentMonthlyLimit = await morpherBridge.withdrawalLimitMonthly();
        assert.equal(currentMonthlyLimit.toString(), web3.utils.toWei('5000001', 'ether'));
        let currentYearlyLimit = new BN(await morpherBridge.withdrawalLimitYearly());

        leaves.push(web3.utils.soliditySha3(addr6, currentYearlyLimit.add(new BN(1)))); //packaging more than yearly limit MPH into a leaf
        leaves.push(web3.utils.soliditySha3(addr7, web3.utils.toWei("20", "ether"))); //packaging 20 MPH into a leaf

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

        const addrBalanceBeforeClaim = await morpherToken.balanceOf(addr6);
        assert.equal(addrBalanceBeforeClaim.toString(), "0");

        const proofForAddr6 = merkleTree.getHexProof(web3.utils.soliditySha3(addr6, currentYearlyLimit.add(new BN(1))));

        let result = await morpherBridge.trustlessTransferFromLinkedChain(currentYearlyLimit, currentYearlyLimit.add(new BN(1)), proofForAddr6, { from: addr6 }); //transfer the limit
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");


        //we transferred the maximum limit for 365 days, another token would trigger an exception
        await truffleAssert.fails(
            morpherBridge.trustlessTransferFromLinkedChain("1", currentYearlyLimit.add(new BN(1)), proofForAddr6, { from: addr6 }),
            truffleAssert.ErrorType.REVERT,
            "MorpherBridge: Withdrawal Amount exceeds yearly limit"
        );

        const addrBalanceAfterClaim = await morpherToken.balanceOf(addr6);

        assert.equal(addrBalanceAfterClaim.toString(), currentYearlyLimit.toString());

        //another user still can transfer
        const proofForAddr7 = merkleTree.getHexProof(web3.utils.soliditySha3(addr7, web3.utils.toWei('20', 'ether')));
        result = await morpherBridge.trustlessTransferFromLinkedChain("1", web3.utils.toWei('20', 'ether'), proofForAddr7, { from: addr7 }); //transfer the limit
        await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");

    });


});