const MorpherBridge = artifacts.require('MorpherBridge')


const { MerkleTree } = require('merkletreejs')

const { keccak256 } = require('ethereumjs-util');
const { BN } = require("bn.js")


module.exports = async function (callback) {
  console.log("Switch metamask to Account that withdraws the money");
  await keypress();
  console.log(await web3.eth.getAccounts());
  
  const [account1] = await web3.eth.getAccounts();
  const targetChain = 5; //on this chain
  const sourceAccount = account1; //we withdraw from this account
  const targetAccount = "0x5351D8DFA6d75Af133930dB4DFF40D853757A865"; //directly to this account
  const withdrawMph = web3.utils.toWei("1000","ether");

  const signatureConfirmation = await web3.eth.personal.sign(web3.utils.soliditySha3(withdrawMph,targetAccount,targetChain),account1);

  /**
   * At this point the user would need to call stageTokensForTransfer(1000e18, 5, targetAccount, signatureConfirmation)
   *  -> this will output an event that we need to catch
   *  -> and trigger the following procedure below...
   */
  console.log("Trying to withdraw for the user")


  const morpherBridge = await MorpherBridge.deployed();
  
  console.log("Switch metamask to Account that is sidechain Op");
  await keypress();
  console.log(await web3.eth.getAccounts());
  
  const [sidechainOperator] = await web3.eth.getAccounts();
  console.log("Trying to withdraw 1000MPH via MerkleTrees on Morpher Bridge " + morpherBridge.address);

  const leaves = [];
  leaves.push(web3.utils.soliditySha3(sourceAccount, withdrawMph, targetChain)); //packaging 1000 MPH into a leaf

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

  const conversionFee = web3.utils.toWei("100","ether"); //100MPH conversion Fee
  const claimLimit = withdrawMph; //make this previous claimed tokens + withdrawal. Here claimLimit for simplicity.
  const proofForAddr1 = await merkleTree.getHexProof(web3.utils.soliditySha3(sourceAccount, withdrawMph, targetChain));

  console.log("Trying to claim with proof " + proofForAddr1)
  await morpherBridge.claimStagedTokensConvertAndSendForUser(sourceAccount, withdrawMph, conversionFee, sidechainOperator, claimLimit, proofForAddr1, targetAccount, newMerkleTreeRoot, signatureConfirmation)
 
  callback()
}

const keypress = async () => {
  process.stdin.setRawMode(true)
  return new Promise(resolve => process.stdin.once('data', () => {
    process.stdin.setRawMode(false)
    resolve()
  }))
}
