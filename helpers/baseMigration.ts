import { createWalletClient, createPublicClient, http, parseEther } from 'viem';
import { base } from 'viem/chains';
import { MerkleTree } from 'merkletreejs';
import { keccak256 } from 'ethereumjs-util';
import { User, Position, Portfolio } from '../database/models';
import { Sequelize, Op } from 'sequelize';
import to from 'await-to-js';
import { Logger } from './winston';
import { PublishCommand } from '@aws-sdk/client-sns';
import { SNS } from './aws';

// Import ABIs
import { morpherSidechainToBaseMigrationAbi } from './blockchain/abis';

// Configuration (to be set from environment variables)
const MIGRATION_CONTRACT_ADDRESS = process.env.MORPHER_MIGRATION_CONTRACT_BASE || '';
const RPC_URL = process.env.BASE_HTTPS_ENDPOINT || 'https://mainnet.base.org';

// Initialize clients
const publicClient = createPublicClient({
  chain: base,
  transport: http(RPC_URL)
});

// Position migration data structure to match contract's PositionMigrationData
interface PositionMigrationData {
  marketId: `0x${string}`;
  timeStamp: bigint;
  longShares: bigint;
  shortShares: bigint;
  meanEntryPrice: bigint;
  meanEntrySpread: bigint;
  meanEntryLeverage: bigint;
  liquidationPrice: bigint;
  proof: `0x${string}`[];
}

/**
 * Calculate Merkle root and proofs for positions and balances
 * @param chainId The chain ID to filter positions and balances
 * @param currentTimestamp Current timestamp for the Merkle tree
 */
export async function calculateBaseMigrationMerkleRoot(chainId: number, currentTimestamp: number) {
  Logger.info({
    source: 'baseMigration.calculateBaseMigrationMerkleRoot',
    message: `Calculating Merkle root for chain ID ${chainId}`
  });
  
  // Initialize arrays for leaves
  const leaves: string[] = [];
  const positionMap = new Map<string, any>(); // Map to store position data by hash
  const balanceMap = new Map<string, any>(); // Map to store balance data by hash
  
  // Get current date for filtering
  const date = new Date();
  date.setMinutes(59, 59, 999);
  const currentDate = date.getTime();
  
  // Fetch positions from database
  const allPositions = await Position.findAll({
    raw: true,
    attributes: ['eth_address', 'hash', 'market_id', 'timestamp', 'long_shares', 'short_shares', 
                'mean_entry_price', 'mean_entry_spread', 'mean_entry_leverage', 'liquidation_price'],
    where: {
      hash: { [Op.ne]: null },
      chain_id: chainId
    }
  });
  
  // Fetch portfolios (for balances) from database
  const allPortfolios = await Portfolio.findAll({
    raw: false,
    attributes: ['eth_address', 'cash_balance', 'cash_balance_hash'],
    where: {
      user_id: { [Op.ne]: null },
      chain_id: chainId,
      cash_balance_hash: { [Op.ne]: null },
      [Op.and]: [
        Sequelize.literal(`exists(
          Select * from "User" 
          where "User".payload->>'merkle' is null 
          and "User".eth_address = "Portfolio".eth_address 
          and "User".eth_address is not null 
          and (withdrawal_unblock_date is null or withdrawal_unblock_date < ${currentDate}) 
          and withdrawal_blocked = false 
          and "User".status = 'confirmed'
        )`)
      ]
    }
  });
  
  // Add position hashes to leaves array and store position data
  if (allPositions && allPositions.length > 0) {
    for (const position of allPositions) {
      if (position.hash !== null) {
        leaves.push(position.hash);
        positionMap.set(position.hash, {
          eth_address: position.eth_address,
          market_id: position.market_id,
          timestamp: position.timestamp,
          long_shares: position.long_shares,
          short_shares: position.short_shares,
          mean_entry_price: position.mean_entry_price,
          mean_entry_spread: position.mean_entry_spread,
          mean_entry_leverage: position.mean_entry_leverage,
          liquidation_price: position.liquidation_price
        });
      }
    }
  }
  
  // Add portfolio balance hashes to leaves array and store balance data
  if (allPortfolios && allPortfolios.length > 0) {
    for (const portfolio of allPortfolios) {
      if (portfolio.cash_balance_hash !== null) {
        leaves.push(portfolio.cash_balance_hash);
        
        // Default to no locking for migration
        balanceMap.set(portfolio.cash_balance_hash, {
          eth_address: portfolio.eth_address,
          balance: portfolio.cash_balance,
          lockedAmount: 0, // Default to no locking
          lockDuration: 0  // Default to no locking
        });
      }
    }
  }
  
  // Sort leaves alphabetically
  leaves.sort();
  
  // Create Merkle tree
  const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const merkleRoot = '0x' + merkleTree.getRoot().toString('hex');
  
  Logger.info({
    source: 'baseMigration.calculateBaseMigrationMerkleRoot',
    message: `Generated Merkle root: ${merkleRoot}`
  });
  
  return {
    merkleRoot,
    merkleTree,
    positionMap,
    balanceMap,
    leaves
  };
}

/**
 * Generate proof for a specific leaf in the Merkle tree
 * @param merkleTree The Merkle tree
 * @param leaf The leaf to generate proof for
 */
export function generateProof(merkleTree: any, leaf: string): `0x${string}`[] {
  const proof = merkleTree.getHexProof(leaf);
  return proof as `0x${string}`[];
}

/**
 * Update the Base migration contract with the new Merkle root
 * @param merkleRoot The new Merkle root to set
 */
export async function updateBaseMigrationMerkleRoot(merkleRoot: string) {
  return new Promise(async (resolve, reject) => {
    try {
      const EthereumTx = require('ethereumjs-tx');
      const privateKey = Buffer.from(process.env.CALLBACK_ACCOUNT_1_KEY, 'hex');
      
      const Web3 = require('web3');
      const web3 = new Web3(process.env.BASE_HTTPS_ENDPOINT);
      
      // Get gas price
      const [error, result] = await to(axios.get('https://api.etherscan.io/api?module=gastracker&action=gasoracle&apikey='+process.env.ETHERSCAN_KEY));
      
      let gasPrice = web3.utils.toWei(process.env.BASE_MAX_GAS || '10', 'gwei');
      let apiGasPrice;
      
      // @ts-ignore
      if (result && !isNaN(result.data.result.ProposeGasPrice)) {
        // @ts-ignore
        apiGasPrice = web3.utils.toWei(String(result.data.result.ProposeGasPrice), 'gwei');
      }
      
      if (apiGasPrice !== undefined && new BN(gasPrice).gte(new BN(apiGasPrice))) {
        gasPrice = apiGasPrice;
      }
      
      // Create contract instance
      const migrationContract = new web3.eth.Contract(
        morpherSidechainToBaseMigrationAbi,
        process.env.MORPHER_MIGRATION_CONTRACT_BASE
      );
      
      // Prepare transaction data
      const data = migrationContract.methods.updatePlasmaStateRoot(merkleRoot);
      
      const nonce = await web3.eth.getTransactionCount(
        process.env.CALLBACK_ACCOUNT_1,
        'pending'
      );
      
      const gasLimit = await data.estimateGas({ 
        nonce, 
        from: process.env.CALLBACK_ACCOUNT_1 
      });
      
      const transactionData = {
        chainId: Number(process.env.BASE_CHAIN_ID || 8453),
        nonce,
        gas: gasLimit * 2,
        gasPrice: web3.utils.numberToHex(gasPrice),
        from: process.env.CALLBACK_ACCOUNT_1,
        to: process.env.MORPHER_MIGRATION_CONTRACT_BASE,
        data: data.encodeABI()
      };
      
      // Sign and send transaction
      const tx = new EthereumTx(transactionData);
      tx.sign(privateKey);
      
      const raw = '0x' + tx.serialize().toString('hex');
      
      web3.eth.sendSignedTransaction(raw)
        .once('transactionHash', (hash) => {
          Logger.info({
            source: 'baseMigration.updateBaseMigrationMerkleRoot',
            message: `Migration contract root update pending [${hash}]`,
            hash
          });
          return resolve(hash);
        })
        .catch(err => {
          Logger.error({
            source: 'baseMigration.updateBaseMigrationMerkleRoot',
            data: {},
            message: `Error updating migration contract: ${err.toString()}`
          });
          
          let notification = {
            message: err.toString(),
            description: 'SNS Notification Base migration update failed',
            logs: 'https://app.datadoghq.eu/logs'
          };
          
          const params = {
            Subject: `Base Migration Update Failed ${process.env.ENVIRONMENT}`,
            Message: JSON.stringify(notification),
            TopicArn: process.env.SNS_DEVELOPERS
          };
          
          const command = new PublishCommand(params);
          SNS.send(command);
          
          return reject(err);
        });
      
      Logger.info({
        source: 'baseMigration.updateBaseMigrationMerkleRoot',
        message: 'Migration contract root update sent to chain.'
      });
    } catch (err) {
      Logger.error({
        source: 'baseMigration.updateBaseMigrationMerkleRoot',
        data: {},
        message: `Error updating migration contract: ${err.toString()}`
      });
      
      let notification = {
        message: err.toString(),
        description: 'SNS Notification Base migration update failed',
        logs: 'https://app.datadoghq.eu/logs'
      };
      
      const params = {
        Subject: `Base Migration Update Failed ${process.env.ENVIRONMENT}`,
        Message: JSON.stringify(notification),
        TopicArn: process.env.SNS_DEVELOPERS
      };
      
      const command = new PublishCommand(params);
      await SNS.send(command);
      
      reject(err);
    }
  });
}

/**
 * Calculate and update the Merkle root for Base migration
 * @param force Force update even if recently updated
 */
export async function calculateAndUpdateBaseMigrationRoot(force = false) {
  try {
    const { redis, redisGet, redisSet } = require('../helpers/functions/ioredis');
    
    const migration_root_updating = await redisGet('base', 'migration_root_updating');
    
    if (migration_root_updating !== true) {
      await redisSet('base', 'migration_root_updating', true);
      
      const last_update = await redisGet('base', 'migration_root_last_update');
      const one_day_ago = Date.now() - (1000 * 60 * 60 * 24);
      
      if (!last_update || last_update <= one_day_ago || force) {
        const currentTimestamp = Date.now();
        const chainId = Number(process.env.SIDECHAIN_ID || 1001);
        
        const result = await calculateBaseMigrationMerkleRoot(chainId, currentTimestamp);
        
        if (result.leaves.length > 0) {
          await updateBaseMigrationMerkleRoot(result.merkleRoot);
          
          await redisSet('base', 'migration_root_last_update', Date.now());
          Logger.info({
            source: 'baseMigration.calculateAndUpdateBaseMigrationRoot',
            message: 'Base migration Merkle root updated.'
          });
        } else {
          Logger.info({
            source: 'baseMigration.calculateAndUpdateBaseMigrationRoot',
            message: 'No leaves found for Merkle tree, skipping update.'
          });
        }
      } else {
        Logger.info({
          source: 'baseMigration.calculateAndUpdateBaseMigrationRoot',
          message: 'Base migration Merkle root update skipped - new root already exists.'
        });
      }
      
      await redisSet('base', 'migration_root_updating', false);
    } else {
      Logger.info({
        source: 'baseMigration.calculateAndUpdateBaseMigrationRoot',
        message: 'Base migration Merkle root update skipped - already updating.'
      });
    }
  } catch (err) {
    const { redisSet } = require('../helpers/functions/ioredis');
    await redisSet('base', 'migration_root_updating', false);
    
    Logger.error({
      source: 'baseMigration.calculateAndUpdateBaseMigrationRoot',
      data: {},
      message: `Error updating Base migration Merkle root: ${err.toString()}`
    });
    
    let notification = {
      message: err.toString(),
      description: 'SNS Notification Base migration update failed',
      logs: 'https://app.datadoghq.eu/logs'
    };
    
    const params = {
      Subject: `Base Migration Update Failed ${process.env.ENVIRONMENT}`,
      Message: JSON.stringify(notification),
      TopicArn: process.env.SNS_DEVELOPERS
    };
    
    const command = new PublishCommand(params);
    SNS.send(command);
  }
}
