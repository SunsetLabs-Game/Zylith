// CLMM Tests - Comprehensive test suite for Concentrated Liquidity Market Maker

use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, get_caller_address, get_contract_address};
use core::array::ArrayTrait;

use zylith::interfaces::izylith::IZylithDispatcher;
use zylith::interfaces::izylith::IZylithDispatcherTrait;

fn deploy_zylith() -> IZylithDispatcher {
    let contract = declare("Zylith").unwrap().contract_class();
    let owner: ContractAddress = get_caller_address();
    let (contract_address, _) = contract.deploy(@array![owner.into()]).unwrap();
    IZylithDispatcher { contract_address }
}

#[test]
fn test_initialize_pool() {
    let dispatcher = deploy_zylith();
    
    let token0: ContractAddress = 0x1.into();
    let token1: ContractAddress = 0x2.into();
    let fee: u128 = 3000; // 0.3% fee
    let tick_spacing: i32 = 60;
    let sqrt_price_x96: u128 = 79228162514264337593543950336; // Q96 format, price = 1
    
    dispatcher.initialize(token0, token1, fee, tick_spacing, sqrt_price_x96);
    
    // Verify pool is initialized
    let root = dispatcher.get_merkle_root();
    // Root should be 0 for empty tree
    assert(root == 0, 'Root should be 0 for empty tree');
}

#[test]
fn test_mint_liquidity() {
    let dispatcher = deploy_zylith();
    
    // Initialize pool first
    let token0: ContractAddress = 0x1.into();
    let token1: ContractAddress = 0x2.into();
    let fee: u128 = 3000;
    let tick_spacing: i32 = 60;
    let sqrt_price_x96: u128 = 79228162514264337593543950336;
    dispatcher.initialize(token0, token1, fee, tick_spacing, sqrt_price_x96);
    
    // Mint liquidity
    let tick_lower: i32 = -60;
    let tick_upper: i32 = 60;
    let amount: u128 = 1000000;
    
    let (amount0, amount1) = dispatcher.mint(tick_lower, tick_upper, amount);
    
    // Verify amounts are calculated
    assert(amount0 > 0 || amount1 > 0, 'Amounts should be positive');
}

#[test]
fn test_swap_basic() {
    let dispatcher = deploy_zylith();
    
    // Initialize pool
    let token0: ContractAddress = 0x1.into();
    let token1: ContractAddress = 0x2.into();
    let fee: u128 = 3000;
    let tick_spacing: i32 = 60;
    let sqrt_price_x96: u128 = 79228162514264337593543950336;
    dispatcher.initialize(token0, token1, fee, tick_spacing, sqrt_price_x96);
    
    // Add liquidity first
    let tick_lower: i32 = -600;
    let tick_upper: i32 = 600;
    let amount: u128 = 1000000000;
    dispatcher.mint(tick_lower, tick_upper, amount);
    
    // Execute swap
    let zero_for_one = true; // Swap token0 for token1
    let amount_specified: u128 = 100000;
    let sqrt_price_limit_x96: u128 = 1; // Very low limit
    
    let (amount0, amount1) = dispatcher.swap(zero_for_one, amount_specified, sqrt_price_limit_x96);
    
    // Verify swap executed
    assert(amount0 < 0, 'Amount0 should be negative (input)');
    assert(amount1 > 0, 'Amount1 should be positive (output)');
}

#[test]
fn test_burn_liquidity() {
    let dispatcher = deploy_zylith();
    
    // Initialize and mint
    let token0: ContractAddress = 0x1.into();
    let token1: ContractAddress = 0x2.into();
    let fee: u128 = 3000;
    let tick_spacing: i32 = 60;
    let sqrt_price_x96: u128 = 79228162514264337593543950336;
    dispatcher.initialize(token0, token1, fee, tick_spacing, sqrt_price_x96);
    
    let tick_lower: i32 = -60;
    let tick_upper: i32 = 60;
    let mint_amount: u128 = 1000000;
    dispatcher.mint(tick_lower, tick_upper, mint_amount);
    
    // Burn liquidity
    let burn_amount: u128 = 500000;
    let (amount0, amount1) = dispatcher.burn(tick_lower, tick_upper, burn_amount);
    
    // Verify burn returns amounts
    assert(amount0 >= 0, 'Amount0 should be non-negative');
    assert(amount1 >= 0, 'Amount1 should be non-negative');
}

#[test]
fn test_collect_fees() {
    let dispatcher = deploy_zylith();
    
    // Initialize, mint, and swap to generate fees
    let token0: ContractAddress = 0x1.into();
    let token1: ContractAddress = 0x2.into();
    let fee: u128 = 3000;
    let tick_spacing: i32 = 60;
    let sqrt_price_x96: u128 = 79228162514264337593543950336;
    dispatcher.initialize(token0, token1, fee, tick_spacing, sqrt_price_x96);
    
    let tick_lower: i32 = -600;
    let tick_upper: i32 = 600;
    dispatcher.mint(tick_lower, tick_upper, 1000000000);
    
    // Execute swap to generate fees
    dispatcher.swap(true, 100000, 1);
    
    // Collect fees
    let (fees0, fees1) = dispatcher.collect(tick_lower, tick_upper);
    
    // Fees should be non-negative
    assert(fees0 >= 0, 'Fees0 should be non-negative');
    assert(fees1 >= 0, 'Fees1 should be non-negative');
}

