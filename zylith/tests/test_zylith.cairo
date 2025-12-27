use core::array::ArrayTrait;
use core::integer::u128;
use core::num::traits::Zero;
use core::traits::TryInto;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, SyscallResultTrait};
use zylith::clmm::math;
use zylith::interfaces::izylith::{IZylithDispatcher, IZylithDispatcherTrait};
use zylith::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

// Test constants
const INITIAL_BALANCE: u256 = 1000000000000000000000000; // 1M tokens
const LARGE_APPROVAL: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
const TEST_FEE: u128 = 3000; // 0.3% fee
const TICK_SPACING: i32 = 60;
const sqrt_price: u256 = 79228162514264337593543950336; // Price 1:1

fn caller() -> ContractAddress {
    0x123.try_into().unwrap()
}

fn user2() -> ContractAddress {
    0x456.try_into().unwrap()
}

//  this is mock
fn deploy_mock_erc20(name: felt252, symbol: felt252) -> IMockERC20Dispatcher {
    let contract = declare("MockERC20").unwrap_syscall().contract_class();
    let mut constructor_args = array![];
    constructor_args.append(name);
    constructor_args.append(symbol);
    constructor_args.append(18);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    IMockERC20Dispatcher { contract_address }
}

fn deploy_zylith() -> IZylithDispatcher {
    let contract = declare("Zylith").unwrap_syscall().contract_class();
    let owner: ContractAddress = 1.try_into().unwrap();

    let mock_verifier_class = declare("MockVerifier").unwrap_syscall().contract_class();
    let (membership_verifier, _) = mock_verifier_class.deploy(@array![]).unwrap_syscall();
    let (swap_verifier, _) = mock_verifier_class.deploy(@array![]).unwrap_syscall();
    let (withdraw_verifier, _) = mock_verifier_class.deploy(@array![]).unwrap_syscall();
    let (lp_verifier, _) = mock_verifier_class.deploy(@array![]).unwrap_syscall();

    let mut constructor_args = array![];
    constructor_args.append(owner.into());
    constructor_args.append(membership_verifier.into());
    constructor_args.append(swap_verifier.into());
    constructor_args.append(withdraw_verifier.into());
    constructor_args.append(lp_verifier.into());

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    IZylithDispatcher { contract_address }
}

#[derive(Drop)]
struct TestSetup {
    zylith: IZylithDispatcher,
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
}

fn setup_with_erc20() -> TestSetup {
    let token0 = deploy_mock_erc20('Token0', 'TK0');
    let token1 = deploy_mock_erc20('Token1', 'TK1');
    let zylith = deploy_zylith();

    // Mint to multiple users
    token0.mint(caller(), INITIAL_BALANCE);
    token1.mint(caller(), INITIAL_BALANCE);
    token0.mint(user2(), INITIAL_BALANCE);
    token1.mint(user2(), INITIAL_BALANCE);

    // Approve for caller
    start_cheat_caller_address(token0.contract_address, caller());
    token0.approve(zylith.contract_address, LARGE_APPROVAL);
    stop_cheat_caller_address(token0.contract_address);

    start_cheat_caller_address(token1.contract_address, caller());
    token1.approve(zylith.contract_address, LARGE_APPROVAL);
    stop_cheat_caller_address(token1.contract_address);

    // Approve for user2
    start_cheat_caller_address(token0.contract_address, user2());
    token0.approve(zylith.contract_address, LARGE_APPROVAL);
    stop_cheat_caller_address(token0.contract_address);

    start_cheat_caller_address(token1.contract_address, user2());
    token1.approve(zylith.contract_address, LARGE_APPROVAL);
    stop_cheat_caller_address(token1.contract_address);

    TestSetup { zylith, token0, token1 }
}

fn initialize_pool(setup: @TestSetup) {
    let setup = setup_with_erc20();

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);
}

// ============================================================================
//  Constructor & Initialization
// ============================================================================

#[test]
fn test_constructor_stores_verifier_addresses() {
    let zylith = deploy_zylith();
    assert!(zylith.contract_address.is_non_zero(), "Contract not deployed");
}

#[test]
fn test_initialize_pool_success() {
    let setup = setup_with_erc20();

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    let root = setup.zylith.get_merkle_root();
    assert!(root == 0, "Initial root should be 0");
    assert!(setup.zylith.is_root_known(0), "Root 0 should be known");
}

#[test]
#[should_panic]
fn test_initialize_twice_fails() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );

    stop_cheat_caller_address(setup.zylith.contract_address);
}


// ============================================================================
//  Private Deposite
// ============================================================================

#[test]
fn test_private_deposit_transfers_tokens_and_adds_commitment() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    let deposit_amount: u256 = 1000000000000000000; // 1 token
    let commitment: felt252 = 0x123456789abcdef; // Mock commitment

    let balance_before = setup.token0.balance_of(caller());

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(setup.token0.contract_address, deposit_amount, commitment);
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Check token transfer
    let balance_after = setup.token0.balance_of(caller());
    assert!(balance_before - balance_after == deposit_amount, "Tokens not transferred");

    // Check commitment added to Merkle tree
    let root = setup.zylith.get_merkle_root();
    assert!(root != 0, "Root should be updated");
    assert!(setup.zylith.is_root_known(root), "New root should be known");
}

#[test]
#[should_panic(expected: ('INVALID_TOKEN',))]
fn test_private_deposit_invalid_token_fails() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    let invalid_token = deploy_mock_erc20('Invalid', 'INV');
    let deposit_amount: u256 = 1000000000000000000;
    let commitment: felt252 = 0x123;

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(invalid_token.contract_address, deposit_amount, commitment);
}

#[test]
fn test_private_deposit_updates_merkle_tree() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    let commitment1: felt252 = 0x111;
    let commitment2: felt252 = 0x222;
    let amount: u256 = 1000000000000000000;

    start_cheat_caller_address(setup.zylith.contract_address, caller());

    setup.zylith.private_deposit(setup.token0.contract_address, amount, commitment1);
    let root1 = setup.zylith.get_merkle_root();

    setup.zylith.private_deposit(setup.token0.contract_address, amount, commitment2);
    let root2 = setup.zylith.get_merkle_root();

    stop_cheat_caller_address(setup.zylith.contract_address);

    assert!(root1 != root2, "Root should change after second deposit");
    assert!(setup.zylith.is_root_known(root1), "Previous root should still be known");
    assert!(setup.zylith.is_root_known(root2), "New root should be known");
    assert!(
        setup.zylith.get_known_roots_count() == 3, "Should have 3 known roots",
    ); // 0, root1, root2
}

// ============================================================================
//  Private Swap
// // ============================================================================
// #[test]
// fn test_private_swap_with_valid_proof() {
//     let setup = setup_with_erc20();
//     initialize_pool(@setup);

//     start_cheat_caller_address(setup.zylith.contract_address, caller());
//     setup.zylith.initialize(
//         setup.token0.contract_address,
//         setup.token1.contract_address,
//         TEST_FEE,
//         TICK_SPACING,
//         sqrt_price,
//     );
//     stop_cheat_caller_address(setup.zylith.contract_address);

//     let deposit_amount: u256 = 1_000_000_000_000_000_000; // 1 token
//     let deposit_commitment: felt252 = 0x123456;

//     start_cheat_caller_address(setup.zylith.contract_address, caller());
//     setup.zylith.private_deposit(setup.token0.contract_address, deposit_amount,
//     deposit_commitment);
//     setup.zylith.private_deposit(setup.token1.contract_address, deposit_amount,
//     deposit_commitment);
//     stop_cheat_caller_address(setup.zylith.contract_address);

//     let root_before_swap = setup.zylith.get_merkle_root();

//     let nullifier: felt252 = 0x01;
//     let new_commitment: felt252 = 0x999;
//     let amount_specified: u128 = 1000;
//     let zero_for_one: bool = true;

//     let sqrt_price_limit = if zero_for_one {
//         math::MIN_SQRT_RATIO + 1
//     } else {
//         math::MAX_SQRT_RATIO - 1
//     };

//     let expected_amount0_delta: felt252 = 100;
//     let expected_amount1_delta: felt252 = 200;
//     let expected_new_tick: i32 = 0;

//     let proof = array![
//         nullifier,
//         root_before_swap,
//         new_commitment,
//         amount_specified.into(),
//         if zero_for_one { 1 } else { 0 },
//         expected_amount0_delta,
//         expected_amount1_delta,
//         sqrt_price_limit.try_into().unwrap(),
//         expected_new_tick.into(),
//     ];

//     let public_inputs = array![
//         nullifier,
//         root_before_swap,
//         new_commitment,
//         amount_specified.into(),
//         if zero_for_one { 1 } else { 0 },
//         expected_amount0_delta.try_into().unwrap(),
//         expected_amount1_delta.try_into().unwrap(),
//         sqrt_price_limit.try_into().unwrap(),
//         expected_new_tick.into(),
//     ];

//     start_cheat_caller_address(setup.zylith.contract_address, caller());
//     let (amount0, amount1) = setup.zylith.private_swap(
//         proof,
//         public_inputs,
//         zero_for_one,
//         amount_specified,
//         sqrt_price_limit,
//         new_commitment,
//     );
//     stop_cheat_caller_address(setup.zylith.contract_address);

//     assert!(amount0 != 0 || amount1 != 0, "Swap should return non-zero amounts");
//     assert!(
//         setup.zylith.is_nullifier_spent(nullifier),
//         "Swap nullifier must be spent"
//     );

//     let root_after_swap = setup.zylith.get_merkle_root();
//     assert!(
//         root_after_swap != root_before_swap,
//         "Merkle root should update after swap"
//     );
// }

// ============================================================================
//  Private Withdraw
// ============================================================================

#[test]
fn test_private_withdraw_with_valid_proof() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    // Initialize pool

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    // private  Deposit first

    let commitment: felt252 = 0x111;
    let amount: u256 = 1000;
    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(setup.token0.contract_address, amount, commitment);
    let current_root = setup.zylith.get_merkle_root();
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Prepare withdraw
    let recipient = user2();

    let mut proof = array![0x999, current_root, recipient.into(), 500, 0x5, 0x6, 0x7, 0x8];
    let nullifier: felt252 = 0x999;

    let withdraw_amount: u128 = 500; // 0.5 token

    let mut public_inputs = array![
        nullifier, current_root, recipient.into(), withdraw_amount.into(),
    ];
    //  record old balance of token0

    let balance_before = setup.token0.balance_of(recipient);

    // Now withdraw token0

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .private_withdraw(
            proof, public_inputs, setup.token0.contract_address, recipient, withdraw_amount,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Checking Token0 balance after withdraw

    let balance_after = setup.token0.balance_of(recipient);
    assert!(
        balance_after - balance_before == withdraw_amount.into(), "Recipient should receive tokens",
    );
    assert!(setup.zylith.is_nullifier_spent(nullifier), "Nullifier should be spent");
}

#[test]
#[should_panic(expected: ('INVALID_TOKEN',))]
fn test_private_withdraw_invalid_token_fails() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    // Initialize pool

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    // private  Deposit first

    let commitment: felt252 = 0x111;
    let amount: u256 = 1000;
    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(setup.token0.contract_address, amount, commitment);
    let current_root = setup.zylith.get_merkle_root();
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Prepare withdraw
    let recipient = user2();

    let mut proof = array![0x999, current_root, recipient.into(), 500, 0x5, 0x6, 0x7, 0x8];
    let nullifier: felt252 = 0x999;

    let withdraw_amount: u128 = 500; // 0.5 token

    let mut public_inputs = array![
        nullifier, current_root, recipient.into(), withdraw_amount.into(),
    ];

    //  Fake TOken address

    let token_fake = deploy_mock_erc20('Tokenfake', 'TK');

    // Now withdraw token0

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .private_withdraw(
            proof, public_inputs, token_fake.contract_address, recipient, withdraw_amount,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);
}

#[test]
#[should_panic(expected: ('AMOUNT_MISMATCH',))]
fn test_private_withdraw_amount_mismatch_fails() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    // Initialize pool

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    // private  Deposit first

    let commitment: felt252 = 0x111;
    let amount: u256 = 1000;
    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(setup.token0.contract_address, amount, commitment);
    let current_root = setup.zylith.get_merkle_root();
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Prepare withdraw with  invalid amount
    let recipient = user2();

    let mut proof = array![0x999, current_root, recipient.into(), 50, 0x5, 0x6, 0x7, 0x8];
    let nullifier: felt252 = 0x999;

    let withdraw_amount: u128 = 500;

    let mut public_inputs = array![
        nullifier, current_root, recipient.into(), withdraw_amount.into(),
    ];

    // Now withdraw token0

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .private_withdraw(
            proof, public_inputs, setup.token0.contract_address, recipient, withdraw_amount,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);
}

// ============================================================================
//  Private Mint & Burn Liquidity
// ============================================================================

#[test]
fn test_private_mint_liquidity_with_valid_proof() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Deposit tokens first
    let commitment: felt252 = 0x111;
    let amount: u256 = 1000000000000000000;
    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(setup.token0.contract_address, amount, commitment);
    setup.zylith.private_deposit(setup.token1.contract_address, amount, commitment);
    let current_root = setup.zylith.get_merkle_root();
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Prepare mint
    let mut proof = array![0x1, current_root, 120, 240, 1000000, 0x222, 0x7, 0x8];
    let nullifier: felt252 = 0x1;
    let new_commitment: felt252 = 0x222;
    let position_commitment: felt252 = 0x333;
    let tick_lower: i32 = 120;
    let tick_upper: i32 = 240;
    let liquidity: u128 = 1000000;

    let mut public_inputs = array![
        nullifier, current_root, tick_lower.into(), tick_upper.into(), liquidity.into(),
        new_commitment, position_commitment,
    ];

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    let (amount0, amount1) = setup
        .zylith
        .private_mint_liquidity(
            proof, public_inputs, tick_lower.into(), tick_upper, liquidity, new_commitment,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    assert!(amount0 > 0 || amount1 > 0, "Should mint some liquidity");
    assert!(setup.zylith.is_nullifier_spent(nullifier), "Nullifier should be spent");
}

#[test]
fn test_private_burn_liquidity_with_valid_proof() {
    let setup = setup_with_erc20();
    initialize_pool(@setup);

    // Initialize pool

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .initialize(
            setup.token0.contract_address,
            setup.token1.contract_address,
            TEST_FEE,
            TICK_SPACING,
            sqrt_price,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    // Private deposit

    let deposit_commitment: felt252 = 0x111;
    let deposit_amount: u256 = 10_000_000_000_000_000_000; // 10 tokens

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup.zylith.private_deposit(setup.token0.contract_address, deposit_amount, deposit_commitment);
    setup.zylith.private_deposit(setup.token1.contract_address, deposit_amount, deposit_commitment);
    stop_cheat_caller_address(setup.zylith.contract_address);

    let root_before_mint = setup.zylith.get_merkle_root();

    // Private mint liquidity

    let tick_lower: i32 = 120;
    let tick_upper: i32 = 240;
    let minted_liquidity: u128 = 2_000_000;

    let mint_nullifier: felt252 = 0x01;
    let new_commitment_after_mint: felt252 = 0x222;
    let position_commitment: felt252 = 0x333;

    let mint_proof = array![
        mint_nullifier, root_before_mint, tick_lower.into(), tick_upper.into(),
        minted_liquidity.into(), new_commitment_after_mint, position_commitment,
    ];

    let mint_public_inputs = array![
        mint_nullifier, root_before_mint, tick_lower.into(), tick_upper.into(),
        minted_liquidity.into(), new_commitment_after_mint, position_commitment,
    ];

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    setup
        .zylith
        .private_mint_liquidity(
            mint_proof,
            mint_public_inputs,
            tick_lower,
            tick_upper,
            minted_liquidity,
            new_commitment_after_mint,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    let root_after_mint = setup.zylith.get_merkle_root();

    // Private burn liquidity

    let burn_liquidity: u128 = 1_000_000; // <= minted_liquidity
    let burn_nullifier: felt252 = 0x999;
    let new_commitment_after_burn: felt252 = 0x555;

    let burn_proof = array![
        burn_nullifier, root_after_mint, tick_lower.into(), tick_upper.into(),
        burn_liquidity.into(), new_commitment_after_burn, position_commitment,
    ];

    let burn_public_inputs = array![
        burn_nullifier, root_after_mint, tick_lower.into(), tick_upper.into(),
        burn_liquidity.into(), new_commitment_after_burn, position_commitment,
    ];

    start_cheat_caller_address(setup.zylith.contract_address, caller());
    let (amount0, amount1) = setup
        .zylith
        .private_burn_liquidity(
            burn_proof,
            burn_public_inputs,
            tick_lower,
            tick_upper,
            burn_liquidity,
            new_commitment_after_burn,
        );
    stop_cheat_caller_address(setup.zylith.contract_address);

    assert!(amount0 > 0 || amount1 > 0, "Burn should return tokens");
    assert!(setup.zylith.is_nullifier_spent(burn_nullifier), "Burn nullifier must be spent");
}
