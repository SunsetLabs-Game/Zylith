// Privacy Tests - Merkle tree, commitments, and nullifiers

use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, get_caller_address};
use core::array::ArrayTrait;
use core::integer::u128;

use zylith::interfaces::izylith::IZylithDispatcher;
use zylith::interfaces::izylith::IZylithDispatcherTrait;
use zylith::privacy::commitment;

fn deploy_zylith() -> IZylithDispatcher {
    let contract = declare("Zylith").unwrap().contract_class();
    let owner: ContractAddress = get_caller_address();
    let (contract_address, _) = contract.deploy(@array![owner.into()]).unwrap();
    IZylithDispatcher { contract_address }
}

#[test]
fn test_private_deposit() {
    let dispatcher = deploy_zylith();
    
    // Generate commitment
    let secret: felt252 = 12345;
    let nullifier: felt252 = 67890;
    let amount: u128 = 1000000;
    let commitment = commitment::generate_commitment(secret, nullifier, amount);
    
    // Deposit commitment
    dispatcher.private_deposit(commitment);
    
    // Verify root is updated
    let root = dispatcher.get_merkle_root();
    assert(root != 0, 'Root should be non-zero after deposit');
}

#[test]
fn test_commitment_generation() {
    // Test commitment generation
    let secret: felt252 = 111;
    let nullifier: felt252 = 222;
    let amount: u128 = 1000;
    
    let commitment1 = commitment::generate_commitment(secret, nullifier, amount);
    let commitment2 = commitment::generate_commitment(secret, nullifier, amount);
    
    // Same inputs should produce same commitment
    assert(commitment1 == commitment2, 'Commitments should match');
    
    // Different inputs should produce different commitments
    let commitment3 = commitment::generate_commitment(secret + 1, nullifier, amount);
    assert(commitment1 != commitment3, 'Different secrets should produce different commitments');
}

#[test]
fn test_commitment_verification() {
    let secret: felt252 = 555;
    let nullifier: felt252 = 666;
    let amount: u128 = 5000;
    
    let commitment = commitment::generate_commitment(secret, nullifier, amount);
    let is_valid = commitment::verify_commitment(commitment, secret, nullifier, amount);
    
    assert(is_valid, 'Commitment verification should pass');
    
    // Wrong secret should fail
    let is_invalid = commitment::verify_commitment(commitment, secret + 1, nullifier, amount);
    assert(!is_invalid, 'Commitment verification should fail with wrong secret');
}

#[test]
fn test_nullifier_tracking() {
    let dispatcher = deploy_zylith();
    
    let nullifier: felt252 = 99999;
    
    // Initially nullifier should not be spent
    let is_spent = dispatcher.is_nullifier_spent(nullifier);
    assert(!is_spent, 'Nullifier should not be spent initially');
    
    // Note: Actual nullifier spending happens in private_withdraw
    // This test verifies the tracking mechanism exists
}

#[test]
fn test_multiple_deposits() {
    let dispatcher = deploy_zylith();
    
    // Make multiple deposits
    let commitment1 = commitment::generate_commitment(1, 1, 1000);
    let commitment2 = commitment::generate_commitment(2, 2, 2000);
    let commitment3 = commitment::generate_commitment(3, 3, 3000);
    
    dispatcher.private_deposit(commitment1);
    let root1 = dispatcher.get_merkle_root();
    
    dispatcher.private_deposit(commitment2);
    let root2 = dispatcher.get_merkle_root();
    
    dispatcher.private_deposit(commitment3);
    let root3 = dispatcher.get_merkle_root();
    
    // Each deposit should change the root
    assert(root1 != root2, 'Root should change after second deposit');
    assert(root2 != root3, 'Root should change after third deposit');
    assert(root1 != root3, 'Root should be different after multiple deposits');
}

