// Privacy Interface

#[starknet::interface]
pub trait IPrivacy<TContractState> {
    fn deposit(ref self: TContractState, commitment: felt252);
    fn get_root(self: @TContractState) -> felt252;
    fn is_nullifier_spent(self: @TContractState, nullifier: felt252) -> bool;
}

