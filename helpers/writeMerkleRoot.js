
const MorpherBridge = artifacts.require("MorpherBridge");

const { MerkleTree } = require('merkletreejs')

const { keccak256 } = require('ethereumjs-util');
        
module.exports = async function (callback) {
    const addrBeneficiary = "0x3Afb232f1E6B8349a4411595b8eEDeB5958e3448";
    const addrDummy1 = "0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762";
    const addrDummy2 = "0xB59b29423e5Aa1E0E2cB8966DC14e553E580314D";
    const morpherBridge = await MorpherBridge.deployed();

    //setup a merkle tree to test withdrawal

    const leaves = [];
    leaves.push(web3.utils.soliditySha3(addrDummy1, web3.utils.toWei("0", "ether"), 137)); //packaging 10 Million MPH into a leaf
    leaves.push(web3.utils.soliditySha3(addrDummy2, web3.utils.toWei("0", "ether"), 137)); //packaging 10 Million MPH into a leaf
    leaves.push(web3.utils.soliditySha3(addrBeneficiary, web3.utils.toWei("10000000", "ether"), 137)); //packaging 10 Million MPH into a leaf

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
    //const morpherAccessControl = await MorpherAccessControl.deployed();
    //await morpherAccessControl.grantRole(await morpherBridge.SIDECHAINOPERATOR_ROLE(), accounts[0]);

    //setup a merkle tree to test withdrawal
    //Ja, per User: daily 200k / monthly 1m / yearly 5m
    //Global: daily 3m / monthly 10m / yearly 50m
    // await morpherBridge.updateWithdrawLimitPerUserDaily(web3.utils.toWei("10000000", "ether"));
    // await morpherBridge.updateWithdrawLimitPerUserMonthly(web3.utils.toWei("10000000", "ether"));
    // await morpherBridge.updateWithdrawLimitPerUserYearly(web3.utils.toWei("10000000", "ether"));
    // await morpherBridge.updateWithdrawLimitGlobalDaily(web3.utils.toWei("10000000", "ether"));
    // await morpherBridge.updateWithdrawLimitGlobalMonthly(web3.utils.toWei("10000000", "ether"));
    // await morpherBridge.updateWithdrawLimitGlobalYearly(web3.utils.toWei("10000000", "ether"));
    //await morpherBridge.updateSideChainMerkleRoot(newMerkleTreeRoot);

    const proofForAddr1 = merkleTree.getHexProof(web3.utils.soliditySha3(addrBeneficiary, web3.utils.toWei("10000000", "ether"), 137));

    
    console.log(proofForAddr1, web3.utils.toWei("10000000", "ether"));
    let result = await morpherBridge.claimStagedTokens(web3.utils.toWei("10000000", "ether"), web3.utils.toWei("10000000", "ether"), proofForAddr1, { from: addrBeneficiary });
    //await truffleAssert.eventEmitted(result, "TrustlessWithdrawFromSideChain");

    //const addr1BalanceAfterClaim = await morpherToken.balanceOf(addr1);

    //assert.equal(addr1BalanceAfterClaim.toString(), web3.utils.toWei('20', 'ether'));
    callback()
  };