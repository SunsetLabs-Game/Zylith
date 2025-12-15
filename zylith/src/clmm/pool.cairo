// Pool Contract - Main CLMM pool implementation

use starknet::ContractAddress;
use starknet::storage::*;

#[starknet::storage_node]
pub struct PoolStorage {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub protocol_fee0: u128, // Protocol fee for token0 (in basis points, e.g., 500 = 5%)
    pub protocol_fee1: u128, // Protocol fee for token1 (in basis points)
    pub tick_spacing: i32,
    pub sqrt_price_x96: u128,
    pub tick: i32,
    pub liquidity: u128,
    pub fee_growth_global0_x128: u256,
    pub fee_growth_global1_x128: u256,
}

#[event]
#[derive(Drop, starknet::Event)]
pub enum PoolEvent {
    Initialize: Initialize,
    Swap: Swap,
    Mint: Mint,
    Burn: Burn,
    Collect: Collect,
}

#[derive(Drop, starknet::Event)]
pub struct Initialize {
    pub sqrt_price_x96: u128,
    pub tick: i32,
}

#[derive(Drop, starknet::Event)]
pub struct Swap {
    pub sender: ContractAddress,
    pub zero_for_one: bool,
    pub amount0: i128,
    pub amount1: i128,
    pub sqrt_price_x96: u128,
    pub liquidity: u128,
    pub tick: i32,
}

#[derive(Drop, starknet::Event)]
pub struct Mint {
    pub sender: ContractAddress,
    pub owner: ContractAddress,
    pub tick_lower: i32,
    pub tick_upper: i32,
    pub amount: u128,
    pub amount0: u128,
    pub amount1: u128,
}

#[derive(Drop, starknet::Event)]
pub struct Burn {
    pub owner: ContractAddress,
    pub tick_lower: i32,
    pub tick_upper: i32,
    pub amount: u128,
    pub amount0: u128,
    pub amount1: u128,
}

#[derive(Drop, starknet::Event)]
pub struct Collect {
    pub owner: ContractAddress,
    pub tick_lower: i32,
    pub tick_upper: i32,
    pub amount0: u128,
    pub amount1: u128,
}

// Pool storage node definition
// Functions using this storage will be implemented in the main Zylith contract
// Storage nodes can only be accessed from within a #[starknet::contract] module

