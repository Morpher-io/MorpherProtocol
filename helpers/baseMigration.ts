import { 
  createWalletClient, 
  createPublicClient, 
  http, 
  parseEther, 
  encodeFunctionData, 
  hashMessage, 
  recoverAddress, 
  toBytes 
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { base } from 'viem/chains';
import { MerkleTree } from 'merkletreejs';
import { keccak256 } from 'ethereumjs-util';
import { Position } from '../database/models';
import { Op } from 'sequelize';
import { Logger } from './winston';
import { PublishCommand } from '@aws-sdk/client-sns';
import { SNS } from './aws';

// Import ABIs
import { morpherSidechainToBaseMigrationAbi } from './blockchain/abis';

// Configuration (to be set from environment variables)
const MIGRATION_CONTRACT_ADDRESS = process.env.MORPHER_MIGRATION_CONTRACT_BASE || '';
const RPC_URL = process.env.BASE_HTTPS_ENDPOINT || 'https://mainnet.base.org';
const CHAIN_ID = Number(process.env.BASE_CHAIN_ID || 8453);
const SIDECHAIN_ID = Number(process.env.SIDECHAIN_ID || 1001);
const BATCH_SIZE = 10; // Maximum positions to migrate in a single transaction

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
 * Fetch user positions from the database
 * @param ethAddress The user's Ethereum address
 * @param chainId The chain ID to filter positions
 */
export async function fetchUserPositions(ethAddress: string, chainId: number = SIDECHAIN_ID) {
  Logger.info({
    source: 'baseMigration.fetchUserPositions',
    message: `Fetching positions for user ${ethAddress} on chain ${chainId}`
  });
  
  try {
    // Fetch positions from database
    const userPositions = await Position.findAll({
      raw: true,
      attributes: [
        'eth_address', 
        'hash', 
        'market_id', 
        'timestamp', 
        'long_shares', 
        'short_shares', 
        'mean_entry_price', 
        'mean_entry_spread', 
        'mean_entry_leverage', 
        'liquidation_price'
      ],
      where: {
        eth_address: ethAddress,
        hash: { [Op.ne]: null },
        chain_id: chainId,
        // Only include positions with non-zero shares
        [Op.or]: [
          { long_shares: { [Op.gt]: 0 } },
          { short_shares: { [Op.gt]: 0 } }
        ]
      }
    });
    
    Logger.info({
      source: 'baseMigration.fetchUserPositions',
      message: `Found ${userPositions.length} positions for user ${ethAddress}`
    });
    
    return userPositions;
  } catch (error) {
    Logger.error({
      source: 'baseMigration.fetchUserPositions',
      message: `Error fetching positions for user ${ethAddress}: ${error}`
    });
    throw error;
  }
}

/**
 * Generate Merkle tree and proofs for user positions
 * @param positions Array of user positions
 */
export function generatePositionMerkleTree(positions: any[]) {
  // Extract position hashes
  const leaves = positions.map(position => position.hash).filter(hash => hash !== null);
  
  if (leaves.length === 0) {
    return { merkleTree: null, merkleRoot: null };
  }
  
  // Sort leaves alphabetically for deterministic tree
  leaves.sort();
  
  // Create Merkle tree
  const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const merkleRoot = '0x' + merkleTree.getRoot().toString('hex');
  
  Logger.info({
    source: 'baseMigration.generatePositionMerkleTree',
    message: `Generated Merkle root: ${merkleRoot} for ${leaves.length} positions`
  });
  
  return { merkleTree, merkleRoot };
}

/**
 * Generate proof for a specific position hash in the Merkle tree
 * @param merkleTree The Merkle tree
 * @param positionHash The position hash to generate proof for
 */
export function generatePositionProof(merkleTree: any, positionHash: string): `0x${string}`[] {
  if (!merkleTree) return [];
  const proof = merkleTree.getHexProof(positionHash);
  return proof as `0x${string}`[];
}

/**
 * Prepare position data for migration
 * @param positions User positions from database
 * @param merkleTree Merkle tree for generating proofs
 */
export function preparePositionMigrationData(positions: any[], merkleTree: any): PositionMigrationData[] {
  return positions.map(position => {
    // Generate proof for this position
    const proof = generatePositionProof(merkleTree, position.hash);
    
    // Convert values to appropriate formats for the contract
    return {
      marketId: position.market_id as `0x${string}`,
      timeStamp: BigInt(position.timestamp),
      longShares: BigInt(position.long_shares),
      shortShares: BigInt(position.short_shares),
      meanEntryPrice: BigInt(position.mean_entry_price),
      meanEntrySpread: BigInt(position.mean_entry_spread),
      meanEntryLeverage: BigInt(position.mean_entry_leverage),
      liquidationPrice: BigInt(position.liquidation_price),
      proof: proof
    };
  });
}

/**
 * Migrate user positions in batches
 * @param ethAddress User's Ethereum address
 * @param userSignature User's signature authorizing migration
 */
export async function migrateUserPositions(ethAddress: string, userSignature: string) {
  try {
    Logger.info({
      source: 'baseMigration.migrateUserPositions',
      message: `Starting position migration for user ${ethAddress}`
    });
    
    // 1. Fetch user positions
    const positions = await fetchUserPositions(ethAddress);
    
    if (positions.length === 0) {
      Logger.info({
        source: 'baseMigration.migrateUserPositions',
        message: `No positions found for user ${ethAddress}`
      });
      return { success: true, message: 'No positions to migrate', txHashes: [] };
    }
    
    // 2. Generate Merkle tree and root
    const { merkleTree, merkleRoot } = generatePositionMerkleTree(positions);
    
    if (!merkleTree || !merkleRoot) {
      Logger.error({
        source: 'baseMigration.migrateUserPositions',
        message: `Failed to generate Merkle tree for user ${ethAddress}`
      });
      return { success: false, message: 'Failed to generate Merkle tree', txHashes: [] };
    }
    
    // 3. Prepare position data for migration
    const positionData = preparePositionMigrationData(positions, merkleTree);
    
    // 4. Split positions into batches of BATCH_SIZE
    const batches: PositionMigrationData[][] = [];
    for (let i = 0; i < positionData.length; i += BATCH_SIZE) {
      batches.push(positionData.slice(i, i + BATCH_SIZE));
    }
    
    Logger.info({
      source: 'baseMigration.migrateUserPositions',
      message: `Migrating ${positionData.length} positions in ${batches.length} batches for user ${ethAddress}`
    });
    
    // 5. Migrate each batch
    const txHashes: string[] = [];
    for (let i = 0; i < batches.length; i++) {
      const batch = batches[i];
      const txHash = await sendMigrationTransaction(ethAddress, userSignature, merkleRoot as `0x${string}`, batch);
      txHashes.push(txHash);
      
      Logger.info({
        source: 'baseMigration.migrateUserPositions',
        message: `Batch ${i+1}/${batches.length} migration transaction sent: ${txHash}`
      });
      
      // Wait a bit between batches to avoid nonce issues
      if (i < batches.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    }
    
    return { 
      success: true, 
      message: `Successfully migrated ${positionData.length} positions in ${batches.length} batches`, 
      txHashes 
    };
    
  } catch (error) {
    Logger.error({
      source: 'baseMigration.migrateUserPositions',
      message: `Error migrating positions for user ${ethAddress}: ${error}`
    });
    
    // Send notification about the error
    const notification = {
      message: error.toString(),
      description: `Position migration failed for user ${ethAddress}`,
      logs: 'https://app.datadoghq.eu/logs'
    };
    
    const params = {
      Subject: `Position Migration Failed ${process.env.ENVIRONMENT}`,
      Message: JSON.stringify(notification),
      TopicArn: process.env.SNS_DEVELOPERS
    };
    
    const command = new PublishCommand(params);
    await SNS.send(command);
    
    return { success: false, message: `Error: ${error.message}`, txHashes: [] };
  }
}

/**
 * Send transaction to migrate a batch of positions using viem
 * @param userAddress User's Ethereum address
 * @param userSignature User's signature authorizing migration
 * @param merkleRoot Merkle root for position verification
 * @param positionBatch Batch of positions to migrate
 */
async function sendMigrationTransaction(
  userAddress: string, 
  userSignature: string, 
  merkleRoot: `0x${string}`, 
  positionBatch: PositionMigrationData[]
): Promise<string> {
  try {
    // Create wallet client with private key from environment
    const account = privateKeyToAccount(`0x${process.env.CALLBACK_ACCOUNT_1_KEY}` as `0x${string}`);
    
    const walletClient = createWalletClient({
      account,
      chain: base,
      transport: http(RPC_URL)
    });
    
    // Prepare function data for the contract call
    const functionData = encodeFunctionData({
      abi: morpherSidechainToBaseMigrationAbi,
      functionName: 'delegateMigratePositionsBatch',
      args: [userAddress, userSignature, merkleRoot, positionBatch]
    });
    
    // Use environment variable for max fee per gas or default to 10 gwei
    const maxGasGwei = process.env.BASE_MAX_GAS || '10';
    const maxFeePerGas = parseEther(maxGasGwei, 'gwei');
    
    // Estimate gas with public client
    let gasLimit;
    try {
      gasLimit = await publicClient.estimateGas({
        account,
        to: MIGRATION_CONTRACT_ADDRESS as `0x${string}`,
        data: functionData,
        value: BigInt(0)
      });
      
      // Add 20% buffer for safety
      gasLimit = (gasLimit * BigInt(120)) / BigInt(100);
    } catch (error) {
      Logger.error({
        source: 'baseMigration.sendMigrationTransaction',
        message: `Gas estimation failed: ${error.message}. Using default gas limit.`
      });
      // Use a high default if estimation fails
      gasLimit = BigInt(5000000);
    }
    
    // Send transaction
    const hash = await walletClient.sendTransaction({
      to: MIGRATION_CONTRACT_ADDRESS as `0x${string}`,
      data: functionData,
      gas: gasLimit,
      maxFeePerGas
    });
    
    Logger.info({
      source: 'baseMigration.sendMigrationTransaction',
      message: `Position migration transaction sent [${hash}]`,
      hash
    });
    
    return hash;
  } catch (error) {
    Logger.error({
      source: 'baseMigration.sendMigrationTransaction',
      message: `Error sending migration transaction: ${error.toString()}`
    });
    throw error;
  }
}

/**
 * Verify if a user's signature is valid for migration authorization
 * @param ethAddress User's Ethereum address
 * @param signature User's signature
 */
export function verifyUserSignature(ethAddress: string, signature: string): boolean {
  try {
    // Recreate the message that was signed - must match exactly how it's done in the contract
    const message = "I authorize migration of all my positions from plasma chain to Base L2";
    
    // In the contract, the message is packed with address and chainId
    // We need to hash it the same way
    const messageHash = hashMessage(message + ethAddress + CHAIN_ID);
    
    // Recover the signer address
    const recoveredAddress = recoverAddress({
      hash: messageHash,
      signature: signature as `0x${string}`
    });
    
    // Check if the recovered address matches the expected user address
    return recoveredAddress.toLowerCase() === ethAddress.toLowerCase();
  } catch (error) {
    Logger.error({
      source: 'baseMigration.verifyUserSignature',
      message: `Error verifying signature: ${error}`
    });
    return false;
  }
}

/**
 * Main function to handle user position migration
 * @param ethAddress User's Ethereum address
 * @param signature User's signature authorizing migration
 */
export async function handleUserPositionMigration(ethAddress: string, signature: string) {
  // 1. Verify the signature
  const isSignatureValid = verifyUserSignature(ethAddress, signature);
  
  if (!isSignatureValid) {
    Logger.error({
      source: 'baseMigration.handleUserPositionMigration',
      message: `Invalid signature for user ${ethAddress}`
    });
    return { 
      success: false, 
      message: 'Invalid signature. Migration authorization failed.' 
    };
  }
  
  // 2. Migrate the user's positions
  const result = await migrateUserPositions(ethAddress, signature);
  
  return result;
}
