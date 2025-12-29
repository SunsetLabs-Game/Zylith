use ark_bn254::Fr;
use ark_ff::{BigInteger, PrimeField};
use light_poseidon::{Poseidon, PoseidonHasher};
use num_bigint::BigUint;
use num_traits::Num;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Merkle Tree Depth (matches Cairo contract)
/// Contract uses depth 25
pub const TREE_DEPTH: usize = 25;

/// Mask used in Cairo contract to ensure BN254 hash fits in felt252
/// 0x3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff (250 bits)
const MASK: &str = "3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct MerkleProof {
    pub leaf: String,
    pub path: Vec<String>,
    pub path_indices: Vec<u32>,
    pub root: String,
}

/// Merkle Tree with proper intermediate node storage for correct proof generation
pub struct MerkleTree {
    pub depth: usize,
    pub next_index: u32,
    /// Store all nodes at all levels: nodes[(level, index)] = hash
    /// Level 0 = leaves, Level depth = root
    pub nodes: HashMap<(usize, u32), BigUint>,
    /// Pre-computed zeros for each level (used for empty siblings)
    pub zeros: Vec<BigUint>,
    /// Current root (updated on each insert)
    pub current_root: BigUint,
    /// Mask for BN254 -> felt252 conversion
    pub mask: BigUint,
}

impl MerkleTree {
    pub fn new(depth: usize) -> Self {
        let mask = BigUint::from_str_radix(MASK, 16).unwrap();
        
        // CRITICAL: Cairo contract uses 0 for empty nodes, not recursive hash
        // Initialize zeros as all 0s (matching Cairo contract behavior)
        let zeros = vec![BigUint::from(0u8); depth + 1];

        // Initial root is 0 (matching Cairo contract: initial_root = 0)
        let initial_root = BigUint::from(0u8);

        Self {
            depth,
            next_index: 0,
            nodes: HashMap::new(),
            zeros,
            current_root: initial_root,
            mask,
        }
    }

    /// Insert a leaf at the next available index and update the tree, returning the new root
    pub fn insert(&mut self, leaf: BigUint) -> BigUint {
        let index = self.next_index;
        self.next_index += 1;
        self.insert_at_index(index, leaf)
    }

    /// Insert a leaf at a specific index and update the tree, returning the new root
    /// This is used when syncing events that may have gaps
    pub fn insert_at_index(&mut self, index: u32, leaf: BigUint) -> BigUint {
        // Update next_index if we're inserting beyond it
        if index >= self.next_index {
            self.next_index = index + 1;
        }

        // Store leaf at level 0
        self.nodes.insert((0, index), leaf.clone());

        // Update path from leaf to root
        let mut current_hash = leaf;
        let mut current_idx = index;

        for level in 0..self.depth {
            // Determine left and right children for current position
            let (left, right) = if current_idx % 2 == 0 {
                // Current node is left child
                let right_idx = current_idx + 1;
                // CRITICAL: Use 0 for missing siblings (matching Cairo contract)
                let right = self
                    .nodes
                    .get(&(level, right_idx))
                    .cloned()
                    .unwrap_or_else(|| BigUint::from(0u8)); // Use 0, not zeros[level]
                (current_hash.clone(), right)
            } else {
                // Current node is right child
                let left_idx = current_idx - 1;
                // CRITICAL: Use 0 for missing siblings (matching Cairo contract)
                let left = self
                    .nodes
                    .get(&(level, left_idx))
                    .cloned()
                    .unwrap_or_else(|| BigUint::from(0u8)); // Use 0, not zeros[level]
                (left, current_hash.clone())
            };

            // Compute parent hash
            current_hash = Self::hash_and_mask(&[left, right], &self.mask);

            // Move to parent level
            let parent_idx = current_idx / 2;
            self.nodes.insert((level + 1, parent_idx), current_hash.clone());
            current_idx = parent_idx;
        }

        self.current_root = current_hash.clone();
        current_hash
    }

    /// Generate a Merkle proof for a leaf at the given index
    pub fn get_proof(&self, index: u32) -> Option<MerkleProof> {
        // Check if leaf exists
        let leaf = self.nodes.get(&(0, index))?;

        let mut path = Vec::with_capacity(self.depth);
        let mut path_indices = Vec::with_capacity(self.depth);
        let mut current_idx = index;

        for level in 0..self.depth {
            // Determine sibling index
            let sibling_idx = if current_idx % 2 == 0 {
                current_idx + 1
            } else {
                current_idx - 1
            };

            // Path index: 0 if current is left (sibling on right), 1 if current is right (sibling on left)
            path_indices.push((current_idx % 2) as u32);
            
            // Get sibling (use 0 if not present - matching Cairo contract)
            // CRITICAL: Cairo contract uses 0 for missing siblings, not recursive hash
            let sibling = self
                .nodes
                .get(&(level, sibling_idx))
                .cloned()
                .unwrap_or_else(|| BigUint::from(0u8)); // Use 0, not zeros[level]
            
            path.push(format!("0x{:x}", sibling));
            
            // Move to parent
            current_idx /= 2;
        }

        Some(MerkleProof {
            leaf: format!("0x{:x}", leaf),
            path,
            path_indices,
            root: format!("0x{:x}", self.current_root),
        })
    }

    /// Get the current root
    pub fn get_root(&self) -> BigUint {
        self.current_root.clone()
    }

    /// Get number of leaves inserted
    pub fn get_leaf_count(&self) -> u32 {
        self.next_index
    }

    /// Find the index of a commitment in the tree
    /// Returns None if the commitment is not found
    pub fn find_commitment_index(&self, commitment: &BigUint) -> Option<u32> {
        // Search through all leaves (level 0)
        for index in 0..self.next_index {
            if let Some(leaf) = self.nodes.get(&(0, index)) {
                if leaf == commitment {
                    return Some(index);
                }
            }
        }
        None
    }

    /// Hash two nodes using Poseidon BN254 and mask to felt252
    fn hash_and_mask(inputs: &[BigUint], mask: &BigUint) -> BigUint {
        // Convert BigUint to Fr field elements
        let input_frs: Vec<Fr> = inputs
            .iter()
            .map(|item| {
                let bytes = item.to_bytes_be();
                let mut buf = [0u8; 32];
                let len = bytes.len().min(32);
                buf[32 - len..].copy_from_slice(&bytes[bytes.len() - len..]);
                Fr::from_be_bytes_mod_order(&buf)
            })
            .collect();

        // Create Poseidon hasher for 2 inputs
        let mut poseidon = Poseidon::<Fr>::new_circom(2).unwrap();

        // Hash the inputs
        let result = poseidon.hash(&input_frs).unwrap();

        // Convert result back to BigUint
        let result_bytes = result.into_bigint().to_bytes_be();
        let result_bu = BigUint::from_bytes_be(&result_bytes);

        // Apply masking as in Cairo
        result_bu & mask
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_tree() {
        let tree = MerkleTree::new(TREE_DEPTH);
        assert_eq!(tree.get_leaf_count(), 0);
        // Empty tree root should be 0 (matching Cairo contract)
        assert_eq!(tree.get_root(), BigUint::from(0u8));
    }

    #[test]
    fn test_insert_and_proof() {
        let mut tree = MerkleTree::new(TREE_DEPTH);

        // Insert some leaves
        let leaf1 = BigUint::from(12345u64);
        let leaf2 = BigUint::from(67890u64);

        let root1 = tree.insert(leaf1.clone());
        assert_eq!(tree.get_leaf_count(), 1);

        let root2 = tree.insert(leaf2.clone());
        assert_eq!(tree.get_leaf_count(), 2);
        assert_ne!(root1, root2);

        // Get proof for first leaf
        let proof = tree.get_proof(0).expect("Proof should exist");
        assert_eq!(proof.leaf, format!("0x{:x}", leaf1));
        assert_eq!(proof.path.len(), TREE_DEPTH);
        assert_eq!(proof.path_indices.len(), TREE_DEPTH);
    }

    #[test]
    fn test_proof_verification() {
        let mut tree = MerkleTree::new(4); // Smaller tree for testing
        let mask = BigUint::from_str_radix(MASK, 16).unwrap();

        let leaf = BigUint::from(12345u64);
        let _root = tree.insert(leaf.clone());

        let proof = tree.get_proof(0).expect("Proof should exist");

        // Manually verify the proof
        let mut current_hash = leaf;
        for (i, sibling_str) in proof.path.iter().enumerate() {
            let sibling = BigUint::from_str_radix(&sibling_str[2..], 16).unwrap();
            let (left, right) = if proof.path_indices[i] == 0 {
                (current_hash.clone(), sibling)
            } else {
                (sibling, current_hash.clone())
            };
            current_hash = MerkleTree::hash_and_mask(&[left, right], &mask);
        }

        assert_eq!(format!("0x{:x}", current_hash), proof.root);
    }
}
