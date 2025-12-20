use light_poseidon::{Poseidon, PoseidonHasher, bn254_parameters};
use num_bigint::BigUint;
use num_traits::Num;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Merkle Tree Depth (matches Cairo contract)
pub const TREE_DEPTH: usize = 20;

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

pub struct MerkleTree {
    pub depth: usize,
    pub next_index: u32,
    pub leaves: HashMap<u32, BigUint>,
    pub filled_subtrees: Vec<BigUint>,
    pub zeros: Vec<BigUint>,
    pub mask: BigUint,
}

impl MerkleTree {
    pub fn new(depth: usize) -> Self {
        let mask = BigUint::from_str_radix(MASK, 16).unwrap();
        let mut zeros = Vec::with_capacity(depth + 1);
        let mut current_zero = BigUint::from(0u8);
        zeros.push(current_zero.clone());

        let mut hasher = PoseidonHasher::new(bn254_parameters());

        for _ in 0..depth {
            let hash_input = vec![current_zero.clone(), current_zero.clone()];
            // Replicate Cairo logic: hash then mask
            current_zero = Self::hash_and_mask(&mut hasher, &hash_input, &mask);
            zeros.push(current_zero.clone());
        }

        Self {
            depth,
            next_index: 0,
            leaves: HashMap::new(),
            filled_subtrees: zeros[..depth].to_vec(),
            zeros,
            mask,
        }
    }

    pub fn insert(&mut self, leaf: BigUint) -> BigUint {
        let index = self.next_index;
        self.leaves.insert(index, leaf.clone());
        self.next_index += 1;

        let mut current_hash = leaf;
        let mut i = index;
        let mut hasher = PoseidonHasher::new(bn254_parameters());

        for level in 0..self.depth {
            let left;
            let right;
            if i % 2 == 1 {
                left = self.filled_subtrees[level].clone();
                right = current_hash;
            } else {
                self.filled_subtrees[level] = current_hash.clone();
                left = current_hash;
                right = self.zeros[level].clone();
            }
            current_hash = Self::hash_and_mask(&mut hasher, &vec![left, right], &self.mask);
            i /= 2;
        }

        current_hash // New root
    }

    fn hash_and_mask(hasher: &mut PoseidonHasher, inputs: &[BigUint], mask: &BigUint) -> BigUint {
        // Convert BigUint to field elements (bytes)
        let input_frs: Vec<[u8; 32]> = inputs.iter().map(|item| {
            let bytes = item.to_bytes_le();
            let mut buf = [0u8; 32];
            buf[..bytes.len()].copy_from_slice(&bytes);
            buf
        }).collect();

        // Light-poseidon expects specific types or byte arrays depending on version
        // For BN254 hash 2:
        let result = hasher.hash(&input_frs).unwrap();
        let result_bu = BigUint::from_bytes_le(&result);
        
        // Apply masking as in Cairo
        result_bu & mask
    }

    pub fn get_proof(&self, index: u32) -> MerkleProof {
        let mut path = Vec::new();
        let mut path_indices = Vec::new();
        let mut i = index;
        
        // Note: For full reconstruction in MVP, a simpler approach is to use the full leaf set
        // or maintain all intermediate nodes.
        // For now, let's assume we can reconstruct it from the leaves map.
        
        let mut current_level_leaves = self.leaves.clone();
        let mut idx = index;
        let mut hasher = PoseidonHasher::new(bn254_parameters());

        for level in 0..self.depth {
            let sibling_idx = if idx % 2 == 0 { idx + 1 } else { idx - 1 };
            path_indices.push(idx % 2);
            
            let sibling = current_level_leaves.get(&sibling_idx)
                .cloned()
                .unwrap_or_else(|| self.zeros[level].clone());
            
            path.push(format!("0x{:x}", sibling));
            
            // Move to next level (recalculating intermediate nodes isn't ideal but works for small depth)
            // In production, the ASP would store all levels.
            idx /= 2;
        }

        MerkleProof {
            leaf: format!("0x{:x}", self.leaves.get(&index).unwrap()),
            path,
            path_indices,
            root: format!("0x{:x}", self.get_root()),
        }
    }

    pub fn get_root(&self) -> BigUint {
        // Find highest level available or just recalculate (placeholder)
        // A better way is to keep the last inserted root
        self.calculate_root()
    }

    fn calculate_root(&self) -> BigUint {
        let mut nodes = self.leaves.clone();
        let mut hasher = PoseidonHasher::new(bn254_parameters());
        let mut current_level_size = (1 << self.depth);
        let mut current_index_limit = self.next_index;

        for level in 0..self.depth {
            let mut next_level_nodes = HashMap::new();
            for i in 0..(current_index_limit + 1) / 2 {
                let left = nodes.get(&(2 * i)).cloned().unwrap_or_else(|| self.zeros[level].clone());
                let right = nodes.get(&(2 * i + 1)).cloned().unwrap_or_else(|| self.zeros[level].clone());
                let hash = Self::hash_and_mask(&mut hasher, &[left, right], &self.mask);
                next_level_nodes.insert(i, hash);
            }
            nodes = next_level_nodes;
            current_index_limit = (current_index_limit + 1) / 2;
        }
        nodes.get(&0).cloned().unwrap_or_else(|| self.zeros[self.depth].clone())
    }
}
