/**
 * Zylith Circuit Utilities
 * Poseidon hashing and commitment generation matching Cairo contracts
 */

const { buildPoseidon } = require("circomlibjs");

let poseidon = null;
let F = null;

/**
 * Initialize Poseidon hasher
 */
async function initPoseidon() {
    if (!poseidon) {
        poseidon = await buildPoseidon();
        F = poseidon.F;
    }
    return { poseidon, F };
}

/**
 * Compute Poseidon hash of two field elements
 * @param {BigInt} a - First input
 * @param {BigInt} b - Second input
 * @returns {BigInt} Hash output
 */
async function poseidonHash(a, b) {
    const { poseidon, F } = await initPoseidon();
    const hash = poseidon([a, b]);
    return F.toObject(hash);
}

/**
 * Mask a field element to 250 bits (matches Cairo Mask250)
 * @param {BigInt} value - Value to mask
 * @returns {BigInt} Masked value
 */
function mask250(value) {
    const MASK_250 = (1n << 250n) - 1n;
    return BigInt(value) & MASK_250;
}

/**
 * Generate commitment: Mask(Hash(Mask(Hash(secret, nullifier)), amount))
 * Matches the commitment scheme used in circuits and Cairo
 * @param {BigInt} secret - User secret
 * @param {BigInt} nullifier - Nullifier value
 * @param {BigInt} amount - Amount in the note
 * @returns {BigInt} Commitment
 */
async function generateCommitment(secret, nullifier, amount) {
    // Step 1: hash1 = Hash(secret, nullifier)
    const hash1 = await poseidonHash(BigInt(secret), BigInt(nullifier));
    
    // Step 2: masked1 = Mask250(hash1)
    const masked1 = mask250(hash1);
    
    // Step 3: hash2 = Hash(masked1, amount)
    const hash2 = await poseidonHash(masked1, BigInt(amount));
    
    // Step 4: commitment = Mask250(hash2)
    const commitment = mask250(hash2);
    
    return commitment;
}

/**
 * Generate a simple Merkle tree and get proof for a leaf
 * @param {BigInt[]} leaves - Array of leaf values
 * @param {number} depth - Tree depth (25 for Zylith)
 * @returns {object} { root, tree }
 */
async function buildMerkleTree(leaves, depth = 25) {
    const { poseidon, F } = await initPoseidon();
    
    // Initialize with leaves padded to 2^depth
    const numLeaves = 2 ** depth;
    const paddedLeaves = [...leaves];
    
    // Pad with zeros
    while (paddedLeaves.length < numLeaves) {
        paddedLeaves.push(0n);
    }
    
    // Build tree bottom-up
    let currentLevel = paddedLeaves.map(l => BigInt(l));
    const tree = [currentLevel];
    
    for (let level = 0; level < depth; level++) {
        const nextLevel = [];
        for (let i = 0; i < currentLevel.length; i += 2) {
            const left = currentLevel[i];
            const right = currentLevel[i + 1] || 0n;
            const hash = poseidon([left, right]);
            nextLevel.push(F.toObject(hash));
        }
        tree.push(nextLevel);
        currentLevel = nextLevel;
    }
    
    const root = currentLevel[0];
    return { root, tree };
}

/**
 * Get Merkle proof for a leaf at given index
 * @param {object} tree - Tree from buildMerkleTree
 * @param {number} leafIndex - Index of the leaf
 * @param {number} depth - Tree depth
 * @returns {object} { pathElements, pathIndices }
 */
function getMerkleProof(tree, leafIndex, depth = 25) {
    const pathElements = [];
    const pathIndices = [];
    
    let idx = leafIndex;
    for (let level = 0; level < depth; level++) {
        const siblingIdx = idx % 2 === 0 ? idx + 1 : idx - 1;
        const sibling = tree[level][siblingIdx] || 0n;
        
        pathElements.push(sibling.toString());
        pathIndices.push(idx % 2);
        
        idx = Math.floor(idx / 2);
    }
    
    return { pathElements, pathIndices };
}

/**
 * Compute empty tree root (all zeros)
 * @param {number} depth - Tree depth
 * @returns {BigInt} Root of empty tree
 */
async function computeEmptyRoot(depth = 25) {
    const { poseidon, F } = await initPoseidon();
    
    let current = 0n;
    for (let i = 0; i < depth; i++) {
        const hash = poseidon([current, current]);
        current = F.toObject(hash);
    }
    
    return current;
}

/**
 * Generate position commitment for LP operations
 * position_commitment = Mask(Hash(secret, tick_lower + tick_upper))
 * @param {BigInt} secret - User secret
 * @param {number} tickLower - Lower tick
 * @param {number} tickUpper - Upper tick
 * @returns {BigInt} Position commitment
 */
async function generatePositionCommitment(secret, tickLower, tickUpper) {
    const tickSum = BigInt(tickLower) + BigInt(tickUpper);
    const hash = await poseidonHash(BigInt(secret), tickSum);
    return mask250(hash);
}

module.exports = {
    initPoseidon,
    poseidonHash,
    mask250,
    generateCommitment,
    buildMerkleTree,
    getMerkleProof,
    computeEmptyRoot,
    generatePositionCommitment
};

