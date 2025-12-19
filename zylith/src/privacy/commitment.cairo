// Commitment System - Hash(Hash(secret, nullifier), amount)
use core::integer::u128;
use garaga::definitions::u384;
use garaga::hashes::poseidon_hash_2_bn254;
use starknet::storage::*;

/// Generate a commitment from secret, nullifier, and amount
/// Formula: Hash(Hash(secret, nullifier), amount)
/// NOTE: For full BN254 compatibility, this should use Garaga's Poseidon BN254
/// For now, using Cairo's native Poseidon as placeholder - MUST be replaced with Garaga
pub fn generate_commitment(secret: felt252, nullifier: felt252, amount: u128) -> u384 {
    let state1 = poseidon_hash_2_bn254(secret.into(), nullifier.into());
    poseidon_hash_2_bn254(state1, amount.into())
}

/// Verify a commitment matches the expected values
pub fn verify_commitment(
    commitment: felt252, secret: felt252, nullifier: felt252, amount: u128,
) -> bool {
    let computed = generate_commitment(secret, nullifier, amount);
    commitment.into() == computed
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
pub fn mark_nullifier_spent(_nullifier: felt252) { // TODO: Implement in main contract
}

