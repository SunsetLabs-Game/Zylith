// Commitment System - Hash(Hash(secret, nullifier), amount)

use starknet::storage::*;
use core::poseidon::PoseidonTrait;
use core::hash::HashStateTrait;
use core::integer::u128;

/// Generate a commitment from secret, nullifier, and amount
/// Formula: Hash(Hash(secret, nullifier), amount)
/// NOTE: For full BN254 compatibility, this should use Garaga's Poseidon BN254
/// For now, using Cairo's native Poseidon as placeholder - MUST be replaced with Garaga
pub fn generate_commitment(secret: felt252, nullifier: felt252, amount: u128) -> felt252 {
    // Step 1: Hash(secret, nullifier)
    let mut state1 = PoseidonTrait::new();
    state1 = state1.update(secret);
    state1 = state1.update(nullifier);
    let intermediate = state1.finalize();
    
    // Step 2: Hash(result, amount)
    // Convert amount (u128) to felt252 for hashing
    let amount_felt: felt252 = amount.try_into().unwrap();
    let mut state2 = PoseidonTrait::new();
    state2 = state2.update(intermediate);
    state2 = state2.update(amount_felt);
    state2.finalize()
}

/// Verify a commitment matches the expected values
pub fn verify_commitment(
    commitment: felt252,
    secret: felt252,
    nullifier: felt252,
    amount: u128,
) -> bool {
    let computed = generate_commitment(secret, nullifier, amount);
    commitment == computed
}

#[starknet::storage_node]
pub struct NullifierStorage {
    // Track spent nullifiers to prevent double spending
    pub spent_nullifiers: Map<felt252, bool>,
}

// Nullifier storage node definition
// Functions using this storage will be implemented in the main Zylith contract
// Storage nodes can only be accessed from within a #[starknet::contract] module

/// Check if a nullifier has been spent (pure function, no storage access)
/// NOTE: Actual implementation will be in the main contract
pub fn is_nullifier_spent(_nullifier: felt252) -> bool {
    // TODO: Implement in main contract
    false
}

/// Mark a nullifier as spent (pure function, no storage access)
/// NOTE: Actual implementation will be in the main contract
pub fn mark_nullifier_spent(_nullifier: felt252) {
    // TODO: Implement in main contract
}

