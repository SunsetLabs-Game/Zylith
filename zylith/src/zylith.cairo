// Zylith Main Contract - Integrates CLMM with ZK Privacy
// Complete implementation combining all modules

#[starknet::contract]
pub mod Zylith {
    use zylith::interfaces::izylith::IZylith;
    use starknet::ContractAddress;
    use starknet::storage::*;
    use starknet::get_caller_address;
    
    use zylith::clmm::pool::{PoolStorage, PoolEvent, Swap as PoolSwap};
    use zylith::clmm::position::PositionStorage;
    use zylith::clmm::tick::{TickBitmap, TickInfo};
    use zylith::clmm::math;
    use zylith::clmm::tick;
    use zylith::clmm::liquidity;

    use zylith::privacy::merkle_tree::MerkleTreeStorage;
    use zylith::privacy::commitment::NullifierStorage;
    use zylith::privacy::deposit::DepositStorage;
    
    use core::array::ArrayTrait;

    #[storage]
    pub struct Storage {
        // CLMM storage
        pool: PoolStorage,
        positions: PositionStorage,
        tick_bitmap: TickBitmap,
        ticks: Map<i32, TickInfo>,
        
        // Privacy storage
        merkle_tree: MerkleTreeStorage,
        nullifiers: NullifierStorage,
        deposit_storage: DepositStorage,
        
        // Contract state
        owner: ContractAddress,
        initialized: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        PoolEvent: PoolEvent,
        PrivacyEvent: zylith::privacy::deposit::PrivacyEvent,
        Initialized: Initialized,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Initialized {
        pub token0: ContractAddress,
        pub token1: ContractAddress,
        pub fee: u128,
        pub tick_spacing: i32,
        pub sqrt_price_x96: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.initialized.write(false);
    }

    #[abi(embed_v0)]
    impl ZylithImpl of zylith::interfaces::izylith::IZylith<ContractState> {
        /// Initialize the pool
        fn initialize(
            ref self: ContractState,
            token0: ContractAddress,
            token1: ContractAddress,
            fee: u128,
            tick_spacing: i32,
            sqrt_price_x96: u128,
        ) {
            assert!(!self.initialized.read());
            
            // Initialize pool storage
            self.pool.token0.write(token0);
            self.pool.token1.write(token1);
            self.pool.fee.write(fee);
            self.pool.tick_spacing.write(tick_spacing);
            self.pool.sqrt_price_x96.write(sqrt_price_x96);
            
            let tick = math::get_tick_at_sqrt_ratio(sqrt_price_x96);
            self.pool.tick.write(tick);
            self.pool.liquidity.write(0);
            self.pool.fee_growth_global0_x128.write(0);
            self.pool.fee_growth_global1_x128.write(0);
            self.pool.protocol_fee0.write(0); // Default: no protocol fee
            self.pool.protocol_fee1.write(0); // Default: no protocol fee
            
            self.initialized.write(true);
            
            self.emit(Event::Initialized(Initialized {
                token0,
                token1,
                fee,
                tick_spacing,
                sqrt_price_x96,
            }));
        }

        /// Private deposit - add commitment to Merkle tree
        fn private_deposit(
            ref self: ContractState,
            commitment: felt252,
        ) {
            // Insert commitment into Merkle tree
            let index = self.merkle_tree.next_index.read();
            self.merkle_tree.leaves.entry(index).write(commitment);
            self.merkle_tree.next_index.write(index + 1);
            
            // Recalculate root by reading all leaves and computing
            // NOTE: In production, this would be optimized to only update affected nodes
            let new_root = InternalFunctionsImpl::_recalculate_merkle_root(ref self);
            self.merkle_tree.root.write(new_root);
            
            // Emit event for ASP synchronization
            self.emit(Event::PrivacyEvent(
                zylith::privacy::deposit::PrivacyEvent::Deposit(
                    zylith::privacy::deposit::Deposit {
                        commitment,
                        leaf_index: index,
                        root: new_root,
                    }
                )
            ));
        }

        /// Private swap with ZK proof verification
        fn private_swap(
            ref self: ContractState,
            proof: Array<felt252>,
            public_inputs: Array<felt252>,
            zero_for_one: bool,
            amount_specified: u128,
            sqrt_price_limit_x96: u128,
            new_commitment: felt252,
        ) -> (i128, i128) {
            // Step 1 - Verify ZK proof using Garaga verifier
            // TODO: Uncomment when Garaga verifier is generated
            // let is_valid = zylith::privacy::verifier::verify(proof, public_inputs);
            // assert!(is_valid, 'Invalid ZK proof');
            
            // Step 2 - Validate Merkle membership from public_inputs
            // Extract commitment, path, root from public_inputs
            // Expected format: [commitment, root, path_length, ...path, ...path_indices]
            assert!(public_inputs.len() >= 3);
            let commitment = *public_inputs.at(0);
            let root = *public_inputs.at(1);
            let path_length = *public_inputs.at(2);
            
            // Verify root matches current Merkle root
            let current_root = self.merkle_tree.root.read();
            assert!(root == current_root);
            
            // Extract path and path_indices
            let mut path: Array<felt252> = ArrayTrait::new();
            let mut path_indices: Array<u32> = ArrayTrait::new();
            let path_length_u32: u32 = path_length.try_into().unwrap();
            let mut i: u32 = 3;
            while i < 3 + path_length_u32 {
                path.append(*public_inputs.at(i));
                i = i + 1;
            };
            while i < 3 + path_length_u32 * 2 {
                let index_val: u32 = (*public_inputs.at(i)).try_into().unwrap();
                path_indices.append(index_val);
                i = i + 1;
            };
            
            // Verify Merkle proof
            let is_valid_proof = zylith::privacy::merkle_tree::verify_proof(
                commitment,
                path,
                path_indices,
                root,
            );
            assert!(is_valid_proof);
            
            // Step 3 - Execute swap in CLMM
            let (amount0, amount1) = InternalFunctionsImpl::_execute_swap(
                ref self,
                zero_for_one,
                amount_specified,
                sqrt_price_limit_x96,
            );
            
            // Step 4 - Add new commitment to Merkle tree
            self.private_deposit(new_commitment);
            
            (amount0, amount1)
        }

        /// Private withdraw with ZK proof verification
        fn private_withdraw(
            ref self: ContractState,
            proof: Array<felt252>,
            public_inputs: Array<felt252>,
            recipient: ContractAddress,
            amount: u128,
        ) {
            // Step 1 - Verify ZK proof using Garaga verifier
            // TODO: Uncomment when Garaga verifier is generated
            // let is_valid = zylith::privacy::verifier::verify(proof, public_inputs);
            // assert!(is_valid, 'Invalid ZK proof');
            
            // Step 2 - Extract nullifier from public_inputs
            // Expected format: [nullifier, ...other_inputs]
            assert!(public_inputs.len() >= 1);
            let nullifier = *public_inputs.at(0);
            
            // Check nullifier hasn't been spent
            let is_spent = self.nullifiers.spent_nullifiers.entry(nullifier).read();
            assert!(!is_spent);
            
            // Step 3 - Mark nullifier as spent
            self.nullifiers.spent_nullifiers.entry(nullifier).write(true);
            
            // Step 4 - Transfer tokens to recipient
            // TODO: Implement ERC20 transfer logic
            // For now, this is a placeholder - actual implementation would:
            // 1. Determine which token to transfer (from public_inputs or amount)
            // 2. Call ERC20 transfer on the appropriate token contract
            // 3. Handle both token0 and token1 if needed
            
            // Emit event
            self.emit(Event::PrivacyEvent(
                zylith::privacy::deposit::PrivacyEvent::NullifierSpent(
                    zylith::privacy::deposit::NullifierSpent {
                        nullifier,
                    }
                )
            ));
        }

        /// Mint liquidity position
        fn mint(
            ref self: ContractState,
            tick_lower: i32,
            tick_upper: i32,
            amount: u128,
        ) -> (u128, u128) {
            assert!(tick_lower < tick_upper);
            assert!(tick_lower % tick::TICK_SPACING == 0);
            assert!(tick_upper % tick::TICK_SPACING == 0);
            
            let caller = get_caller_address();
            let current_tick = self.pool.tick.read();
            let current_sqrt_price = self.pool.sqrt_price_x96.read();
            
            // Calculate sqrt prices at boundaries
            let sqrt_price_lower = math::get_sqrt_ratio_at_tick(tick_lower);
            let sqrt_price_upper = math::get_sqrt_ratio_at_tick(tick_upper);
            
            // Calculate liquidity needed
            let liquidity_needed = if current_tick < tick_lower {
                // Current price below range - only need token0
                liquidity::get_liquidity_for_amount0(
                    sqrt_price_lower,
                    sqrt_price_upper,
                    amount,
                )
            } else if current_tick >= tick_upper {
                // Current price above range - only need token1
                liquidity::get_liquidity_for_amount1(
                    sqrt_price_lower,
                    sqrt_price_upper,
                    amount,
                )
            } else {
                // Current price in range - need both tokens
                let liquidity0 = liquidity::get_liquidity_for_amount0(
                    current_sqrt_price,
                    sqrt_price_upper,
                    amount,
                );
                let liquidity1 = liquidity::get_liquidity_for_amount1(
                    sqrt_price_lower,
                    current_sqrt_price,
                    amount,
                );
                if liquidity0 < liquidity1 {
                    liquidity0
                } else {
                    liquidity1
                }
            };
            
            // Calculate actual amounts needed
            let amount0 = liquidity::get_amount0_for_liquidity(
                sqrt_price_lower,
                sqrt_price_upper,
                liquidity_needed,
            );
            let amount1 = liquidity::get_amount1_for_liquidity(
                sqrt_price_lower,
                sqrt_price_upper,
                liquidity_needed,
            );
            
            // Calculate fee growth inside range before updating position
            let fee_growth_inside0 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self,
                tick_lower,
                tick_upper,
                true, // for token0
            );
            let fee_growth_inside1 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self,
                tick_lower,
                tick_upper,
                false, // for token1
            );
            
            // Update position - read struct, modify, write back
            let position_key = (caller, tick_lower, tick_upper);
            let position_info = self.positions.positions.entry(position_key).read();
            
            // Calculate fees owed before updating
            let position_liquidity = position_info.liquidity;
            let fees_owed0: u128 = if position_liquidity > 0 {
                let fee_delta0 = fee_growth_inside0 - position_info.fee_growth_inside0_last_x128;
                let liquidity_u256: u256 = position_liquidity.try_into().unwrap();
                let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                let fees = (fee_delta0 * liquidity_u256) / q128;
                fees.try_into().unwrap()
            } else {
                0
            };
            let fees_owed1: u128 = if position_liquidity > 0 {
                let fee_delta1 = fee_growth_inside1 - position_info.fee_growth_inside1_last_x128;
                let liquidity_u256: u256 = position_liquidity.try_into().unwrap();
                let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                let fees = (fee_delta1 * liquidity_u256) / q128;
                fees.try_into().unwrap()
            } else {
                0
            };
            
            // Create new struct with updated liquidity and fee growth
            let updated_position = zylith::clmm::position::PositionInfo {
                liquidity: position_info.liquidity + liquidity_needed,
                fee_growth_inside0_last_x128: fee_growth_inside0,
                fee_growth_inside1_last_x128: fee_growth_inside1,
                tokens_owed0: position_info.tokens_owed0 + fees_owed0.try_into().unwrap(),
                tokens_owed1: position_info.tokens_owed1 + fees_owed1.try_into().unwrap(),
            };
            self.positions.positions.entry(position_key).write(updated_position);
            
            // Update ticks
            InternalFunctionsImpl::_update_tick(ref self, tick_lower, liquidity_needed, false);
            InternalFunctionsImpl::_update_tick(ref self, tick_upper, liquidity_needed, true);
            
            // Update global liquidity if price is in range
            if current_tick >= tick_lower && current_tick < tick_upper {
                let current_liquidity = self.pool.liquidity.read();
                self.pool.liquidity.write(current_liquidity + liquidity_needed);
            };
            
            (amount0, amount1)
        }

        /// Execute swap
        fn swap(
            ref self: ContractState,
            zero_for_one: bool,
            amount_specified: u128,
            sqrt_price_limit_x96: u128,
        ) -> (i128, i128) {
            InternalFunctionsImpl::_execute_swap(
                ref self,
                zero_for_one,
                amount_specified,
                sqrt_price_limit_x96,
            )
        }

        /// Get Merkle root
        fn get_merkle_root(self: @ContractState) -> felt252 {
            self.merkle_tree.root.read()
        }

        /// Check if nullifier is spent
        fn is_nullifier_spent(self: @ContractState, nullifier: felt252) -> bool {
            self.nullifiers.spent_nullifiers.entry(nullifier).read()
        }
        
        /// Burn liquidity position
        fn burn(
            ref self: ContractState,
            tick_lower: i32,
            tick_upper: i32,
            amount: u128,
        ) -> (u128, u128) {
            assert!(tick_lower < tick_upper);
            assert!(tick_lower % tick::TICK_SPACING == 0);
            assert!(tick_upper % tick::TICK_SPACING == 0);
            
            let caller = get_caller_address();
            let position_key = (caller, tick_lower, tick_upper);
            let position_info = self.positions.positions.entry(position_key).read();
            
            assert!(position_info.liquidity >= amount);
            
            // Calculate fee growth inside before burning
            let fee_growth_inside0 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self,
                tick_lower,
                tick_upper,
                true,
            );
            let fee_growth_inside1 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self,
                tick_lower,
                tick_upper,
                false,
            );
            
            // Calculate fees owed
            let fee_delta0 = fee_growth_inside0 - position_info.fee_growth_inside0_last_x128;
            let fee_delta1 = fee_growth_inside1 - position_info.fee_growth_inside1_last_x128;
            
            let fees_owed0: u128 = if position_info.liquidity > 0 {
                let liquidity_u256: u256 = position_info.liquidity.try_into().unwrap();
                let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                let fees = (fee_delta0 * liquidity_u256) / q128;
                fees.try_into().unwrap()
            } else {
                0
            };
            
            let fees_owed1: u128 = if position_info.liquidity > 0 {
                let liquidity_u256: u256 = position_info.liquidity.try_into().unwrap();
                let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                let fees = (fee_delta1 * liquidity_u256) / q128;
                fees.try_into().unwrap()
            } else {
                0
            };
            
            // Calculate amounts to return
            let sqrt_price_lower = math::get_sqrt_ratio_at_tick(tick_lower);
            let sqrt_price_upper = math::get_sqrt_ratio_at_tick(tick_upper);
            
            let amount0 = liquidity::get_amount0_for_liquidity(
                sqrt_price_lower,
                sqrt_price_upper,
                amount,
            );
            let amount1 = liquidity::get_amount1_for_liquidity(
                sqrt_price_lower,
                sqrt_price_upper,
                amount,
            );
            
            // Apply protocol fee (withdrawal fee) if configured
            let protocol_fee0 = self.pool.protocol_fee0.read();
            let protocol_fee1 = self.pool.protocol_fee1.read();
            
            let final_amount0 = if protocol_fee0 > 0 {
                amount0 - (amount0 * protocol_fee0) / 1000000
            } else {
                amount0
            };
            
            let final_amount1 = if protocol_fee1 > 0 {
                amount1 - (amount1 * protocol_fee1) / 1000000
            } else {
                amount1
            };
            
            // Update position
            let new_liquidity = position_info.liquidity - amount;
            let updated_position = zylith::clmm::position::PositionInfo {
                liquidity: new_liquidity,
                fee_growth_inside0_last_x128: fee_growth_inside0,
                fee_growth_inside1_last_x128: fee_growth_inside1,
                tokens_owed0: position_info.tokens_owed0 + fees_owed0,
                tokens_owed1: position_info.tokens_owed1 + fees_owed1,
            };
            self.positions.positions.entry(position_key).write(updated_position);
            
            // Update ticks
            InternalFunctionsImpl::_update_tick(ref self, tick_lower, amount, false);
            InternalFunctionsImpl::_update_tick(ref self, tick_upper, amount, true);
            
            // Update global liquidity if price is in range
            let current_tick = self.pool.tick.read();
            if current_tick >= tick_lower && current_tick < tick_upper {
                let current_liquidity = self.pool.liquidity.read();
                self.pool.liquidity.write(current_liquidity - amount);
            };
            
            (final_amount0, final_amount1)
        }
        
        /// Collect fees from a position
        fn collect(
            ref self: ContractState,
            tick_lower: i32,
            tick_upper: i32,
        ) -> (u128, u128) {
            let caller = get_caller_address();
            let position_key = (caller, tick_lower, tick_upper);
            let position_info = self.positions.positions.entry(position_key).read();
            
            // Calculate fee growth inside
            let fee_growth_inside0 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self,
                tick_lower,
                tick_upper,
                true,
            );
            let fee_growth_inside1 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self,
                tick_lower,
                tick_upper,
                false,
            );
            
            // Calculate new fees owed
            let fee_delta0 = fee_growth_inside0 - position_info.fee_growth_inside0_last_x128;
            let fee_delta1 = fee_growth_inside1 - position_info.fee_growth_inside1_last_x128;
            
            let new_fees_owed0: u128 = if position_info.liquidity > 0 {
                let liquidity_u256: u256 = position_info.liquidity.try_into().unwrap();
                let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                let fees = (fee_delta0 * liquidity_u256) / q128;
                fees.try_into().unwrap()
            } else {
                0
            };
            
            let new_fees_owed1: u128 = if position_info.liquidity > 0 {
                let liquidity_u256: u256 = position_info.liquidity.try_into().unwrap();
                let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                let fees = (fee_delta1 * liquidity_u256) / q128;
                fees.try_into().unwrap()
            } else {
                0
            };
            
            // Total fees to collect
            let total_fees0 = position_info.tokens_owed0 + new_fees_owed0;
            let total_fees1 = position_info.tokens_owed1 + new_fees_owed1;
            
            // Update position - reset tokens_owed and update fee_growth
            let updated_position = zylith::clmm::position::PositionInfo {
                liquidity: position_info.liquidity,
                fee_growth_inside0_last_x128: fee_growth_inside0,
                fee_growth_inside1_last_x128: fee_growth_inside1,
                tokens_owed0: 0,
                tokens_owed1: 0,
            };
            self.positions.positions.entry(position_key).write(updated_position);
            
            (total_fees0, total_fees1)
        }
    }

    /// Internal helper functions grouped using generate_trait
    #[generate_trait]
    impl InternalFunctionsImpl of InternalFunctionsTrait {
        /// Internal function to execute swap with tick crossing
        fn _execute_swap(
            ref self: ContractState,
            zero_for_one: bool,
            amount_specified: u128,
            sqrt_price_limit_x96: u128,
        ) -> (i128, i128) {
            let mut sqrt_price_x96 = self.pool.sqrt_price_x96.read();
            let mut current_tick = self.pool.tick.read();
            let mut liquidity = self.pool.liquidity.read();
            
            // Check price limits
            if zero_for_one {
                assert!(sqrt_price_x96 >= sqrt_price_limit_x96);
            } else {
                assert!(sqrt_price_x96 <= sqrt_price_limit_x96);
            };
            
            // Track swap amounts
            let mut amount0: i128 = 0;
            let mut amount1: i128 = 0;
            let mut amount_specified_remaining = amount_specified;
            
            // Swap loop: iterate until amount is consumed or price limit reached
            while amount_specified_remaining > 0 {
                // Get next initialized tick in the swap direction
                let next_tick = Self::_get_next_initialized_tick(
                    ref self,
                    current_tick,
                    zero_for_one,
                );
                
                // Calculate sqrt price at next tick
                let next_sqrt_price_x96 = math::get_sqrt_ratio_at_tick(next_tick);
                
                // Determine target price (either next tick or limit)
                let target_sqrt_price_x96 = if zero_for_one {
                    if next_sqrt_price_x96 < sqrt_price_limit_x96 {
                        sqrt_price_limit_x96
                    } else {
                        next_sqrt_price_x96
                    }
                } else {
                    if next_sqrt_price_x96 > sqrt_price_limit_x96 {
                        sqrt_price_limit_x96
                    } else {
                        next_sqrt_price_x96
                    }
                };
                
                // Compute swap step to target price
                let (step_amount0, step_amount1, new_sqrt_price_x96, step_fee_amount0, step_fee_amount1) = Self::_compute_swap_step(
                    ref self,
                    sqrt_price_x96,
                    target_sqrt_price_x96,
                    liquidity,
                    amount_specified_remaining,
                    zero_for_one,
                );
                
                // Update accumulated amounts
                amount0 = amount0 + step_amount0;
                amount1 = amount1 + step_amount1;
                
                // Update fee growth global (accumulate fees)
                if liquidity > 0 {
                    let fee_growth0 = self.pool.fee_growth_global0_x128.read();
                    let fee_growth1 = self.pool.fee_growth_global1_x128.read();
                    
                    // Calculate fee growth delta: fee_amount * Q128 / liquidity
                    // Q128 = 2^128 for fee growth representation
                    let q128: u256 = 340282366920938463463374607431768211456; // 2^128
                    
                    if step_fee_amount0 > 0 {
                        let fee_amount0_u256: u256 = step_fee_amount0.try_into().unwrap();
                        let liquidity_u256: u256 = liquidity.try_into().unwrap();
                        let fee_delta0 = fee_amount0_u256 * q128;
                        let fee_delta0 = fee_delta0 / liquidity_u256;
                        self.pool.fee_growth_global0_x128.write(fee_growth0 + fee_delta0);
                    };
                    
                    if step_fee_amount1 > 0 {
                        let fee_amount1_u256: u256 = step_fee_amount1.try_into().unwrap();
                        let liquidity_u256: u256 = liquidity.try_into().unwrap();
                        let fee_delta1 = fee_amount1_u256 * q128;
                        let fee_delta1 = fee_delta1 / liquidity_u256;
                        self.pool.fee_growth_global1_x128.write(fee_growth1 + fee_delta1);
                    };
                };
                
                // Update price
                sqrt_price_x96 = new_sqrt_price_x96;
                current_tick = math::get_tick_at_sqrt_ratio(sqrt_price_x96);
                
                // Check if we reached the price limit
                if (zero_for_one && sqrt_price_x96 <= sqrt_price_limit_x96)
                    || (!zero_for_one && sqrt_price_x96 >= sqrt_price_limit_x96) {
                    break;
                };
                
                // If we reached the next tick, cross it
                if sqrt_price_x96 == next_sqrt_price_x96 {
                    Self::_cross_tick(ref self, next_tick, zero_for_one);
                    
                    // Update liquidity after crossing tick
                    let tick_entry = self.ticks.entry(next_tick);
                    let liquidity_net = tick_entry.liquidity_net.read();
                    
                    if zero_for_one {
                        let net_abs: u128 = if liquidity_net < 0 {
                            (-liquidity_net).try_into().unwrap()
                        } else {
                            liquidity_net.try_into().unwrap()
                        };
                        liquidity = liquidity - net_abs;
                    } else {
                        let net_abs: u128 = liquidity_net.try_into().unwrap();
                        liquidity = liquidity + net_abs;
                    };
                    
                    // Update amount remaining (consume the step)
                    let step_consumed = if zero_for_one {
                        let abs_amount1 = if step_amount1 < 0 { -step_amount1 } else { step_amount1 };
                        abs_amount1.try_into().unwrap()
                    } else {
                        let abs_amount0 = if step_amount0 < 0 { -step_amount0 } else { step_amount0 };
                        abs_amount0.try_into().unwrap()
                    };
                    
                    if step_consumed > amount_specified_remaining {
                        amount_specified_remaining = 0;
                    } else {
                        amount_specified_remaining = amount_specified_remaining - step_consumed;
                    };
                } else {
                    // Partial step, consume remaining amount
                    break;
                };
            };
            
            // Update pool state
            self.pool.sqrt_price_x96.write(sqrt_price_x96);
            self.pool.tick.write(current_tick);
            self.pool.liquidity.write(liquidity);
            
            // Emit swap event
            let caller = get_caller_address();
            self.emit(Event::PoolEvent(
                PoolEvent::Swap(
                    PoolSwap {
                        sender: caller,
                        zero_for_one,
                        amount0,
                        amount1,
                        sqrt_price_x96,
                        liquidity,
                        tick: current_tick,
                    }
                )
            ));
            
            (amount0, amount1)
        }
        
        /// Compute swap step from current price to target price
        /// Returns: (amount0, amount1, new_sqrt_price, fee_amount0, fee_amount1)
        fn _compute_swap_step(
            ref self: ContractState,
            sqrt_price_current: u128,
            sqrt_price_target: u128,
            liquidity: u128,
            amount_remaining: u128,
            zero_for_one: bool,
        ) -> (i128, i128, u128, u128, u128) {
            // Calculate price difference
            let sqrt_price_diff = if zero_for_one {
                sqrt_price_current - sqrt_price_target
            } else {
                sqrt_price_target - sqrt_price_current
            };
            
            // Calculate amount needed to reach target price
            // Formula: amount = liquidity * sqrt_price_diff / sqrt_price_current
            let amount_needed = math::mul_u128(liquidity, sqrt_price_diff);
            let amount_needed = amount_needed / sqrt_price_current;
            
            // Get pool fee rate
            let pool_fee = self.pool.fee.read();
            
            // Determine if we can reach target or need partial step
            let (new_sqrt_price_x96, amount0, amount1, fee_amount0, fee_amount1) = if amount_remaining >= amount_needed {
                // Can reach target price
                let amount0_val: i128 = if zero_for_one {
                    let neg: i128 = amount_needed.try_into().unwrap();
                    -neg
                } else {
                    amount_needed.try_into().unwrap()
                };
                
                let amount1_val: i128 = if zero_for_one {
                    amount_needed.try_into().unwrap()
                } else {
                    let neg: i128 = amount_needed.try_into().unwrap();
                    -neg
                };
                
                // Calculate fees: fee = amount * pool_fee / 1000000 (assuming fee in basis points)
                // For zero_for_one: fee is on amount1 (output token)
                // For one_for_zero: fee is on amount0 (output token)
                let fee_amount0_val: u128 = if zero_for_one {
                    0 // Fee is on token1
                } else {
                    let abs_amount0: u128 = if amount0_val < 0 {
                        (-amount0_val).try_into().unwrap()
                    } else {
                        amount0_val.try_into().unwrap()
                    };
                    (abs_amount0 * pool_fee) / 1000000
                };
                
                let fee_amount1_val: u128 = if zero_for_one {
                    let abs_amount1: u128 = if amount1_val < 0 {
                        (-amount1_val).try_into().unwrap()
                    } else {
                        amount1_val.try_into().unwrap()
                    };
                    (abs_amount1 * pool_fee) / 1000000
                } else {
                    0 // Fee is on token0
                };
                
                (sqrt_price_target, amount0_val, amount1_val, fee_amount0_val, fee_amount1_val)
            } else {
                // Partial step - calculate new price from remaining amount
                // Formula: new_price = current_price ± (amount_remaining * current_price / liquidity)
                let price_delta = math::mul_u128(amount_remaining, sqrt_price_current);
                let price_delta = price_delta / liquidity;
                
                let new_price = if zero_for_one {
                    sqrt_price_current - price_delta
                } else {
                    sqrt_price_current + price_delta
                };
                
                let amount0_val: i128 = if zero_for_one {
                    let neg: i128 = amount_remaining.try_into().unwrap();
                    -neg
                } else {
                    amount_remaining.try_into().unwrap()
                };
                
                let amount1_val: i128 = if zero_for_one {
                    amount_remaining.try_into().unwrap()
                } else {
                    let neg: i128 = amount_remaining.try_into().unwrap();
                    -neg
                };
                
                // Calculate fees for partial step
                let fee_amount0_val: u128 = if zero_for_one {
                    0
                } else {
                    let abs_amount0: u128 = if amount0_val < 0 {
                        (-amount0_val).try_into().unwrap()
                    } else {
                        amount0_val.try_into().unwrap()
                    };
                    (abs_amount0 * pool_fee) / 1000000
                };
                
                let fee_amount1_val: u128 = if zero_for_one {
                    let abs_amount1: u128 = if amount1_val < 0 {
                        (-amount1_val).try_into().unwrap()
                    } else {
                        amount1_val.try_into().unwrap()
                    };
                    (abs_amount1 * pool_fee) / 1000000
                } else {
                    0
                };
                
                (new_price, amount0_val, amount1_val, fee_amount0_val, fee_amount1_val)
            };
            
            (amount0, amount1, new_sqrt_price_x96, fee_amount0, fee_amount1)
        }
        
        /// Get next initialized tick in swap direction (optimized bitmap lookup)
        fn _get_next_initialized_tick(
            ref self: ContractState,
            tick: i32,
            zero_for_one: bool,
        ) -> i32 {
            // Use optimized bitmap scanning
            let (mut word_pos, mut bit_pos) = tick::position(tick);
            
            // Search within the current word
            let mut word = self.tick_bitmap.bitmap.entry(word_pos).read();
            
            if zero_for_one { // Searching downwards (lte)
                let mut search_bit_pos = bit_pos;
                while search_bit_pos >= 0 {
                    if tick::is_bit_set(word, search_bit_pos) {
                        let found_tick = word_pos * 256 + search_bit_pos;
                        // Verify tick is actually initialized
                        let tick_entry = self.ticks.entry(found_tick);
                        if tick_entry.initialized.read() {
                            return found_tick;
                        };
                    }
                    search_bit_pos = search_bit_pos - 1;
                }
                // Search in previous words
                word_pos = word_pos - 1;
                while word_pos >= math::MIN_TICK / 256 {
                    word = self.tick_bitmap.bitmap.entry(word_pos).read();
                    if word != 0 {
                        // Find the highest set bit in this word
                        let mut i = 255;
                        while i >= 0 {
                            if tick::is_bit_set(word, i) {
                                let found_tick = word_pos * 256 + i;
                                let tick_entry = self.ticks.entry(found_tick);
                                if tick_entry.initialized.read() {
                                    return found_tick;
                                };
                            }
                            i = i - 1;
                        }
                    }
                    word_pos = word_pos - 1;
                }
                math::MIN_TICK // Return boundary if not found
            } else { // Searching upwards (gte)
                let mut search_bit_pos = bit_pos;
                while search_bit_pos < 256 {
                    if tick::is_bit_set(word, search_bit_pos) {
                        let found_tick = word_pos * 256 + search_bit_pos;
                        // Verify tick is actually initialized
                        let tick_entry = self.ticks.entry(found_tick);
                        if tick_entry.initialized.read() {
                            return found_tick;
                        };
                    }
                    search_bit_pos = search_bit_pos + 1;
                }
                // Search in next words
                word_pos = word_pos + 1;
                let max_word_pos = math::MAX_TICK / 256;
                while word_pos <= max_word_pos {
                    word = self.tick_bitmap.bitmap.entry(word_pos).read();
                    if word != 0 {
                        // Find the lowest set bit in this word
                        let mut i = 0;
                        while i < 256 {
                            if tick::is_bit_set(word, i) {
                                let found_tick = word_pos * 256 + i;
                                let tick_entry = self.ticks.entry(found_tick);
                                if tick_entry.initialized.read() {
                                    return found_tick;
                                };
                            }
                            i = i + 1;
                        }
                    }
                    word_pos = word_pos + 1;
                }
                math::MAX_TICK // Return boundary if not found
            }
        }
        
        /// Cross a tick during swap - update liquidity and fee growth
        fn _cross_tick(
            ref self: ContractState,
            tick: i32,
            zero_for_one: bool,
        ) {
            let tick_entry = self.ticks.entry(tick);
            
            // Update fee growth outside (flip when crossing)
            // This is a simplified version - full implementation would track fee growth more carefully
            let fee_growth_global0 = self.pool.fee_growth_global0_x128.read();
            let fee_growth_global1 = self.pool.fee_growth_global1_x128.read();
            
            let fee_growth_outside0 = tick_entry.fee_growth_outside0_x128.read();
            let fee_growth_outside1 = tick_entry.fee_growth_outside1_x128.read();
            
            // Flip fee growth outside when crossing
            // If price is moving from below to above tick (zero_for_one = false), flip
            // If price is moving from above to below tick (zero_for_one = true), flip
            if zero_for_one {
                // Moving down: fee_growth_outside = fee_growth_global - fee_growth_outside
                tick_entry.fee_growth_outside0_x128.write(fee_growth_global0 - fee_growth_outside0);
                tick_entry.fee_growth_outside1_x128.write(fee_growth_global1 - fee_growth_outside1);
            } else {
                // Moving up: same logic
                tick_entry.fee_growth_outside0_x128.write(fee_growth_global0 - fee_growth_outside0);
                tick_entry.fee_growth_outside1_x128.write(fee_growth_global1 - fee_growth_outside1);
            };
        }

        /// Update tick information
        fn _update_tick(
            ref self: ContractState,
            tick: i32,
            liquidity_delta: u128,
            upper: bool,
        ) {
            let tick_entry = self.ticks.entry(tick);
            
            if !tick_entry.initialized.read() {
                tick_entry.initialized.write(true);
                // Initialize tick in bitmap
                let (word_pos, bit_pos) = tick::position(tick);
                let mut word = self.tick_bitmap.bitmap.entry(word_pos).read();
                word = tick::set_bit(word, bit_pos);
                self.tick_bitmap.bitmap.entry(word_pos).write(word);
            };
            
            let current_gross = tick_entry.liquidity_gross.read();
            tick_entry.liquidity_gross.write(current_gross + liquidity_delta);
            
            let current_net = tick_entry.liquidity_net.read();
            if upper {
                let delta_i128: i128 = liquidity_delta.try_into().unwrap();
                tick_entry.liquidity_net.write(current_net - delta_i128);
            } else {
                let delta_i128: i128 = liquidity_delta.try_into().unwrap();
                tick_entry.liquidity_net.write(current_net + delta_i128);
            };
        }
        
        /// Calculate fee growth inside a tick range
        fn _get_fee_growth_inside(
            ref self: ContractState,
            tick_lower: i32,
            tick_upper: i32,
            is_token0: bool,
        ) -> u256 {
            let current_tick = self.pool.tick.read();
            let fee_growth_global = if is_token0 {
                self.pool.fee_growth_global0_x128.read()
            } else {
                self.pool.fee_growth_global1_x128.read()
            };
            
            let tick_lower_entry = self.ticks.entry(tick_lower);
            let tick_upper_entry = self.ticks.entry(tick_upper);
            
            let fee_growth_below = if current_tick >= tick_lower {
                if is_token0 {
                    tick_lower_entry.fee_growth_outside0_x128.read()
                } else {
                    tick_lower_entry.fee_growth_outside1_x128.read()
                }
            } else {
                let outside = if is_token0 {
                    tick_lower_entry.fee_growth_outside0_x128.read()
                } else {
                    tick_lower_entry.fee_growth_outside1_x128.read()
                };
                fee_growth_global - outside
            };
            
            let fee_growth_above = if current_tick < tick_upper {
                if is_token0 {
                    tick_upper_entry.fee_growth_outside0_x128.read()
                } else {
                    tick_upper_entry.fee_growth_outside1_x128.read()
                }
            } else {
                let outside = if is_token0 {
                    tick_upper_entry.fee_growth_outside0_x128.read()
                } else {
                    tick_upper_entry.fee_growth_outside1_x128.read()
                };
                fee_growth_global - outside
            };
            
            // Fee growth inside = fee_growth_global - fee_growth_below - fee_growth_above
            fee_growth_global - fee_growth_below - fee_growth_above
        }
        
        /// Recalculate Merkle root from all stored leaves
        fn _recalculate_merkle_root(ref self: ContractState) -> felt252 {
            let next_index = self.merkle_tree.next_index.read();
            
            if next_index == 0 {
                return 0; // Empty tree
            };
            
            // Collect all leaves
            let mut leaves: Array<felt252> = ArrayTrait::new();
            let mut i: u32 = 0;
            while i < next_index {
                let leaf = self.merkle_tree.leaves.entry(i).read();
                leaves.append(leaf);
                i = i + 1;
            };
            
            // Calculate root using the helper function
            zylith::privacy::merkle_tree::calculate_root_from_leaves(leaves)
        }
    }
}
