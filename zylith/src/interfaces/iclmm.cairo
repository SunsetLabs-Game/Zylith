// CLMM Interface
use starknet::ContractAddress;

#[starknet::interface]
pub trait ICLMM<TContractState> {
    fn initialize(
        ref self: TContractState,
        token0: ContractAddress,
        token1: ContractAddress,
        fee: u128,
        tick_spacing: i32,
        sqrt_price_x96: u128,
    );
    
    fn mint(
        ref self: TContractState,
        tick_lower: i32,
        tick_upper: i32,
        amount: u128,
    ) -> (u128, u128);
    
    fn burn(
        ref self: TContractState,
        tick_lower: i32,
        tick_upper: i32,
        amount: u128,
    ) -> (u128, u128);
    
    fn swap(
        ref self: TContractState,
        zero_for_one: bool,
        amount_specified: u128,
        sqrt_price_limit_x96: u128,
    ) -> (i128, i128);
    
    fn collect(
        ref self: TContractState,
        tick_lower: i32,
        tick_upper: i32,
    ) -> (u128, u128);
    
    fn get_sqrt_price_x96(self: @TContractState) -> u128;
    fn get_tick(self: @TContractState) -> i32;
    fn get_liquidity(self: @TContractState) -> u128;
}

