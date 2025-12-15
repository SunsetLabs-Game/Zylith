// Private Deposit Logic

use starknet::storage::*;

use super::merkle_tree;
use super::commitment;

#[starknet::storage_node]
pub struct DepositStorage {
    pub merkle_tree: merkle_tree::MerkleTreeStorage,
    pub nullifiers: commitment::NullifierStorage,
}

#[event]
#[derive(Drop, starknet::Event)]
pub enum PrivacyEvent {
    Deposit: Deposit,
    NullifierSpent: NullifierSpent,
}

#[derive(Drop, starknet::Event)]
pub struct Deposit {
    pub commitment: felt252,
    pub leaf_index: u32,
    pub root: felt252,
}

#[derive(Drop, starknet::Event)]
pub struct NullifierSpent {
    pub nullifier: felt252,
}

// Deposit storage node definition
// Functions using this storage will be implemented in the main Zylith contract
// Storage nodes can only be accessed from within a #[starknet::contract] module

