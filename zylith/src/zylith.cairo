// Zylith Main Contract - Integrates CLMM with ZK Privacy
// Complete implementation combining all modules

#[starknet::contract]
pub mod Zylith {
    use core::array::ArrayTrait;
    use starknet::storage::*;
    use starknet::{ContractAddress, get_caller_address};
    use zylith::clmm::pool::{PoolEvent, PoolStorage, Swap as PoolSwap};
    use zylith::clmm::position::PositionStorage;
    use zylith::clmm::tick::{TickBitmap, TickInfo};
    use zylith::clmm::{liquidity, math, tick};
    use zylith::interfaces::izylith::IZylith;
    use zylith::privacy::commitment::NullifierStorage;
    use zylith::privacy::deposit::DepositStorage;
    use zylith::privacy::merkle_tree::MerkleTreeStorage;
    use crate::privacy::verifiers::lp::groth16_verifier::{
        IGroth16VerifierBN254Dispatcher as ILPVerifier,
        IGroth16VerifierBN254DispatcherTrait as ILPVerifierTrait,
    };

    // Import the Groth16 verifiers directly
    use crate::privacy::verifiers::membership::groth16_verifier::{
        IGroth16VerifierBN254Dispatcher as IMembershipVerifier,
        IGroth16VerifierBN254DispatcherTrait as IMembershipVerifierTrait,
    };
    use crate::privacy::verifiers::swap::groth16_verifier::{
        IGroth16VerifierBN254Dispatcher as ISwapVerifier,
        IGroth16VerifierBN254DispatcherTrait as ISwapVerifierTrait,
    };
    use crate::privacy::verifiers::withdraw::groth16_verifier::{
        IGroth16VerifierBN254Dispatcher as IWithdrawVerifier,
        IGroth16VerifierBN254DispatcherTrait as IWithdrawVerifierTrait,
    };

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
        //verifier addresses
        membership_verifier: ContractAddress,
        swap_verifier: ContractAddress,
        withdraw_verifier: ContractAddress,
        lp_verifier: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        PoolEvent: PoolEvent,
        PrivacyEvent: zylith::privacy::deposit::PrivacyEvent,
        Initialized: Initialized,
        ProofVerified: ProofVerified,
        ProofRejected: ProofRejected,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Initialized {
        pub token0: ContractAddress,
        pub token1: ContractAddress,
        pub fee: u128,
        pub tick_spacing: i32,
        pub sqrt_price_x128: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProofVerified {
        pub proof_type: felt252,
        pub caller: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProofRejected {
        pub proof_type: felt252,
        pub caller: ContractAddress,
        pub error: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        membership_verifier: ContractAddress,
        swap_verifier: ContractAddress,
        withdraw_verifier: ContractAddress,
        lp_verifier: ContractAddress,
    ) {
        self.owner.write(owner);
        self.membership_verifier.write(membership_verifier);
        self.swap_verifier.write(swap_verifier);
        self.withdraw_verifier.write(withdraw_verifier);
        self.lp_verifier.write(lp_verifier);
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
            sqrt_price_x128: u256,
        ) {
            assert!(!self.initialized.read());

            // Initialize pool storage
            self.pool.token0.write(token0);
            self.pool.token1.write(token1);
            self.pool.fee.write(fee);
            self.pool.tick_spacing.write(tick_spacing);
            self.pool.sqrt_price_x128.write(sqrt_price_x128);

            let tick = math::get_tick_at_sqrt_ratio(sqrt_price_x128);
            self.pool.tick.write(tick);
            self.pool.liquidity.write(0);
            self.pool.fee_growth_global0_x128.write(0);
            self.pool.fee_growth_global1_x128.write(0);
            self.pool.protocol_fee0.write(0); // Default: no protocol fee
            self.pool.protocol_fee1.write(0); // Default: no protocol fee

            self.initialized.write(true);

            self
                .emit(
                    Event::Initialized(
                        Initialized { token0, token1, fee, tick_spacing, sqrt_price_x128 },
                    ),
                );
        }

        /// Private deposit - add commitment to Merkle tree
        fn private_deposit(ref self: ContractState, commitment: felt252) {
            // Insert commitment into Merkle tree
            let index = self.merkle_tree.next_index.read();
            self.merkle_tree.leaves.entry(index).write(commitment);
            self.merkle_tree.next_index.write(index + 1);

            // Update Merkle root incrementally (O(log N)) instead of recalculating (O(N))
            // This significantly reduces gas usage
            let new_root = InternalFunctionsImpl::_update_merkle_root(ref self, index, commitment);
            self.merkle_tree.root.write(new_root);

            // Emit event for ASP synchronization
            self
                .emit(
                    Event::PrivacyEvent(
                        zylith::privacy::deposit::PrivacyEvent::Deposit(
                            zylith::privacy::deposit::Deposit {
                                commitment, leaf_index: index, root: new_root,
                            },
                        ),
                    ),
                );
        }

        /// Private swap with ZK proof verification
        fn private_swap(
            ref self: ContractState,
            proof: Array<felt252>,
            public_inputs: Array<felt252>,
            zero_for_one: bool,
            amount_specified: u128,
            sqrt_price_limit_x128: u256,
            new_commitment: felt252,
        ) -> (i128, i128) {
            // Step 1 - Verify ZK proof using Garaga verifier
            let swap_verifier_addr = self.swap_verifier.read();
            let verifier = ISwapVerifier { contract_address: swap_verifier_addr };
            let _verified_inputs = verifier.verify_groth16_proof_bn254(proof.span()).unwrap();

            // In a production environment, we would validate that verified_inputs
            // match the public_inputs provided. For MVP, we use public_inputs for logic.

            // Step 2 - Use verified values from ZK proof
            // Verified inputs indices (mapping to circuit public outputs):
            // 0: commitment (the one being spent)
            // 1: root
            // 2: new_commitment
            // 3: amount_specified (u128 stored in lower bits of u256)
            // 4: zero_for_one (0 for false, 1 for true)

            assert(_verified_inputs.len() >= 5, 'INVALID_VERIFIED_INPUTS_LEN');

            let verified_root: felt252 = (*_verified_inputs.at(1)).try_into().unwrap();
            let verified_amount: u128 = (*_verified_inputs.at(3)).low;
            let verified_new_commitment: felt252 = (*_verified_inputs.at(2)).try_into().unwrap();

            // CRITICAL: Verify root matches current Merkle root
            let current_root = self.merkle_tree.root.read();
            assert(verified_root == current_root, 'INVALID_MERKLE_ROOT');

            // CRITICAL: Ensure proof matches call arguments
            assert(verified_amount == amount_specified, 'AMOUNT_MISMATCH');
            assert(verified_new_commitment == new_commitment, 'COMMITMENT_MISMATCH');

            // Step 3 - Execute swap in CLMM
            let (amount0, amount1) = InternalFunctionsImpl::_execute_swap(
                ref self, zero_for_one, amount_specified, sqrt_price_limit_x128,
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
            let withdraw_verifier_addr = self.withdraw_verifier.read();
            let verifier = IWithdrawVerifier { contract_address: withdraw_verifier_addr };
            let _verified_inputs = verifier.verify_groth16_proof_bn254(proof.span()).unwrap();

            // Step 2 - Use verified values from ZK proof
            // 0: nullifier
            // 1: root
            // 2: recipient (address)
            // 3: amount
            // 4: fee
            assert(_verified_inputs.len() >= 4, 'INVALID_VERIFIED_INPUTS_LEN');

            let verified_nullifier: felt252 = (*_verified_inputs.at(0)).try_into().unwrap();
            let verified_root: felt252 = (*_verified_inputs.at(1)).try_into().unwrap();
            let verified_amount: u128 = (*_verified_inputs.at(3)).low;
            let verified_recipient_felt: felt252 = (*_verified_inputs.at(2)).try_into().unwrap();
            let verified_recipient: ContractAddress = verified_recipient_felt.try_into().unwrap();

            // CRITICAL: Check root
            let current_root = self.merkle_tree.root.read();
            assert(verified_root == current_root, 'INVALID_MERKLE_ROOT');

            // CRITICAL: Ensure call args match proof
            assert(verified_amount == amount, 'AMOUNT_MISMATCH');
            assert(verified_recipient == recipient, 'RECIPIENT_MISMATCH');

            // Check nullifier hasn't been spent
            let is_spent = self.nullifiers.spent_nullifiers.entry(verified_nullifier).read();
            assert(!is_spent, 'NULLIFIER_ALREADY_SPENT');

            // Step 3 - Mark nullifier as spent
            self.nullifiers.spent_nullifiers.entry(verified_nullifier).write(true);

            // Step 4 - Transfer tokens to recipient
            // TODO: Implement ERC20 transfer logic
            // For now, this is a placeholder - actual implementation would:
            // 1. Determine which token to transfer (from public_inputs or amount)
            // 2. Call ERC20 transfer on the appropriate token contract
            // 3. Handle both token0 and token1 if needed

            // Emit event
            self
                .emit(
                    Event::PrivacyEvent(
                        zylith::privacy::deposit::PrivacyEvent::NullifierSpent(
                            zylith::privacy::deposit::NullifierSpent {
                                nullifier: verified_nullifier,
                            },
                        ),
                    ),
                );
        }

        /// Mint liquidity position
        /// amount: desired amount of token0 (if price below range) or token1 (if price above range)
        /// or minimum of both (if price in range)
        fn mint(
            ref self: ContractState, tick_lower: i32, tick_upper: i32, amount: u128,
        ) -> (u128, u128) {
            assert!(tick_lower < tick_upper);
            assert!(tick_lower % tick::TICK_SPACING == 0);
            assert!(tick_upper % tick::TICK_SPACING == 0);
            assert!(amount > 0);

            let caller = get_caller_address();
            let current_tick = self.pool.tick.read();
            let current_sqrt_price = self.pool.sqrt_price_x128.read();

            // Calculate sqrt prices at boundaries
            let sqrt_price_lower = math::get_sqrt_ratio_at_tick(tick_lower);
            let sqrt_price_upper = math::get_sqrt_ratio_at_tick(tick_upper);

            // Ensure sqrt_price_lower < sqrt_price_upper
            // If they're equal or reversed, adjust to ensure valid range
            let (sqrt_price_lower_final, sqrt_price_upper_final) =
                if sqrt_price_lower < sqrt_price_upper {
                (sqrt_price_lower, sqrt_price_upper)
            } else if sqrt_price_lower > sqrt_price_upper {
                // Swap if reversed
                (sqrt_price_upper, sqrt_price_lower)
            } else {
                // If equal, add a small difference to make it valid
                // This handles edge cases where ticks are too close
                let min_diff = math::Q128 / 1000000; // Very small difference
                (sqrt_price_lower, sqrt_price_upper + min_diff)
            };

            // Calculate liquidity needed based on position relative to current price
            // Ensure we always get positive liquidity when amount > 0
            let liquidity_needed = if current_tick < tick_lower {
                // Current price below range - only need token1 (range is above price)
                liquidity::get_liquidity_for_amount1(
                    sqrt_price_lower_final, sqrt_price_upper_final, amount,
                )
            } else if current_tick >= tick_upper {
                // Current price above range - only need token0 (range is below price)
                liquidity::get_liquidity_for_amount0(
                    sqrt_price_lower_final, sqrt_price_upper_final, amount,
                )
            } else {
                // Current price in range - need both tokens
                // Calculate liquidity for both and take minimum
                let liquidity0 = liquidity::get_liquidity_for_amount0(
                    current_sqrt_price, sqrt_price_upper_final, amount,
                );
                let liquidity1 = liquidity::get_liquidity_for_amount1(
                    sqrt_price_lower_final, current_sqrt_price, amount,
                );
                if liquidity0 < liquidity1 {
                    liquidity0
                } else {
                    liquidity1
                }
            };

            // Ensure minimum liquidity if amount > 0
            // The liquidity should be proportional to the amount
            // Use a more conservative multiplier to avoid overflow
            let liquidity_needed = if liquidity_needed == 0 && amount > 0 {
                // Calculate a reasonable liquidity based on the price range
                // For small ranges, use a larger multiplier
                let tick_diff_i32 = tick_upper - tick_lower;
                let tick_diff: u128 = if tick_diff_i32 > 0 {
                    tick_diff_i32.try_into().unwrap()
                } else {
                    1
                };
                // Scale liquidity based on amount and tick range
                // Use smaller multipliers to prevent overflow
                let multiplier = if tick_diff < 120 {
                    100 // Small range: moderate multiplier
                } else {
                    10 // Larger range: smaller multiplier
                };
                // Use u256 to prevent overflow
                let amount_u256: u256 = amount.try_into().unwrap();
                let multiplier_u256: u256 = multiplier.try_into().unwrap();
                let result_u256 = amount_u256 * multiplier_u256;
                result_u256.try_into().unwrap()
            } else if liquidity_needed > 0 {
                // Ensure liquidity is at least proportional to amount
                let min_liquidity = amount / 10;
                if liquidity_needed < min_liquidity {
                    min_liquidity
                } else {
                    liquidity_needed
                }
            } else {
                liquidity_needed
            };

            // Calculate actual amounts needed based on where current price is
            let (amount0_final, amount1_final) = if current_tick < tick_lower {
                // Current price below range - only need token1
                let amount1 = liquidity::get_amount1_for_liquidity(
                    sqrt_price_lower_final, sqrt_price_upper_final, liquidity_needed,
                );
                (0, amount1)
            } else if current_tick >= tick_upper {
                // Current price above range - only need token0
                let amount0 = liquidity::get_amount0_for_liquidity(
                    sqrt_price_lower_final, sqrt_price_upper_final, liquidity_needed,
                );
                (amount0, 0)
            } else {
                // Current price in range - need both tokens
                let amount0 = liquidity::get_amount0_for_liquidity(
                    current_sqrt_price, sqrt_price_upper_final, liquidity_needed,
                );
                let amount1 = liquidity::get_amount1_for_liquidity(
                    sqrt_price_lower_final, current_sqrt_price, liquidity_needed,
                );
                (amount0, amount1)
            };

            // Calculate fee growth inside range before updating position
            let fee_growth_inside0 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self, tick_lower, tick_upper, true // for token0
            );
            let fee_growth_inside1 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self, tick_lower, tick_upper, false // for token1
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
            }

            (amount0_final, amount1_final)
        }

        /// Execute swap
        fn swap(
            ref self: ContractState,
            zero_for_one: bool,
            amount_specified: u128,
            sqrt_price_limit_x128: u256,
        ) -> (i128, i128) {
            InternalFunctionsImpl::_execute_swap(
                ref self, zero_for_one, amount_specified, sqrt_price_limit_x128,
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
            ref self: ContractState, tick_lower: i32, tick_upper: i32, amount: u128,
        ) -> (u128, u128) {
            assert!(tick_lower < tick_upper);
            assert!(tick_lower % tick::TICK_SPACING == 0);
            assert!(tick_upper % tick::TICK_SPACING == 0);

            let caller = get_caller_address();
            let position_key = (caller, tick_lower, tick_upper);
            let position_info = self.positions.positions.entry(position_key).read();

            // Ensure we don't burn more than available
            let burn_amount: u128 = if position_info.liquidity < amount {
                position_info.liquidity // Burn all available
            } else {
                amount
            };

            assert!(burn_amount > 0);

            // Calculate fee growth inside before burning
            let fee_growth_inside0 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self, tick_lower, tick_upper, true,
            );
            let fee_growth_inside1 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self, tick_lower, tick_upper, false,
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
                sqrt_price_lower, sqrt_price_upper, burn_amount,
            );
            let amount1 = liquidity::get_amount1_for_liquidity(
                sqrt_price_lower, sqrt_price_upper, burn_amount,
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
            let new_liquidity = position_info.liquidity - burn_amount;
            let updated_position = zylith::clmm::position::PositionInfo {
                liquidity: new_liquidity,
                fee_growth_inside0_last_x128: fee_growth_inside0,
                fee_growth_inside1_last_x128: fee_growth_inside1,
                tokens_owed0: position_info.tokens_owed0 + fees_owed0,
                tokens_owed1: position_info.tokens_owed1 + fees_owed1,
            };
            self.positions.positions.entry(position_key).write(updated_position);

            // Update ticks
            InternalFunctionsImpl::_update_tick(ref self, tick_lower, burn_amount, false);
            InternalFunctionsImpl::_update_tick(ref self, tick_upper, burn_amount, true);

            // Update global liquidity if price is in range
            let current_tick = self.pool.tick.read();
            if current_tick >= tick_lower && current_tick < tick_upper {
                let current_liquidity = self.pool.liquidity.read();
                if burn_amount <= current_liquidity {
                    self.pool.liquidity.write(current_liquidity - burn_amount);
                } else {
                    self.pool.liquidity.write(0);
                };
            }

            (final_amount0, final_amount1)
        }

        /// Collect fees from a position
        fn collect(ref self: ContractState, tick_lower: i32, tick_upper: i32) -> (u128, u128) {
            let caller = get_caller_address();
            let position_key = (caller, tick_lower, tick_upper);
            let position_info = self.positions.positions.entry(position_key).read();

            // Calculate fee growth inside
            let fee_growth_inside0 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self, tick_lower, tick_upper, true,
            );
            let fee_growth_inside1 = InternalFunctionsImpl::_get_fee_growth_inside(
                ref self, tick_lower, tick_upper, false,
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
            sqrt_price_limit_x128: u256,
        ) -> (i128, i128) {
            let mut sqrt_price_x128 = self.pool.sqrt_price_x128.read();
            let mut current_tick = self.pool.tick.read();
            let mut liquidity = self.pool.liquidity.read();

            // Check price limits - validate swap direction
            // For zero_for_one: price decreases, limit should be <= current price
            // For one_for_zero: price increases, limit should be >= current price
            let mut adjusted_limit = sqrt_price_limit_x128;
            if adjusted_limit < math::MIN_SQRT_RATIO {
                adjusted_limit = math::MIN_SQRT_RATIO;
            }
            if adjusted_limit > math::MAX_SQRT_RATIO {
                adjusted_limit = math::MAX_SQRT_RATIO;
            }
            if zero_for_one {
                // For zero_for_one, price should decrease, so limit should be lower
                if adjusted_limit >= sqrt_price_x128 {
                    // Invalid limit (can't go up when swapping down)
                    // Adjust limit to be slightly below current price
                    let min_diff = math::Q128 / 1000000;
                    if sqrt_price_x128 > min_diff {
                        adjusted_limit = sqrt_price_x128 - min_diff;
                    } else {
                        adjusted_limit = math::MIN_SQRT_RATIO;
                    };
                };
            } else {
                // For one_for_zero, price should increase, so limit should be higher
                if adjusted_limit <= sqrt_price_x128 {
                    // Invalid limit (can't go down when swapping up)
                    // Adjust limit to be slightly above current price
                    let min_diff = math::Q128 / 1000000;
                    let max_price = math::MAX_SQRT_RATIO;
                    if sqrt_price_x128 < max_price - min_diff {
                        adjusted_limit = sqrt_price_x128 + min_diff;
                    } else {
                        adjusted_limit = max_price;
                    };
                };
            }
            let sqrt_price_limit_x128 = adjusted_limit;

            // Track swap amounts
            let mut amount0: i128 = 0;
            let mut amount1: i128 = 0;
            let mut amount_specified_remaining = amount_specified;

            // Swap loop: iterate until amount is consumed or price limit reached
            let mut step_count: u32 = 0;
            while amount_specified_remaining > 0 && step_count < 100 {
                step_count += 1;
                // Get tick limit from price limit
                let tick_limit = math::get_tick_at_sqrt_ratio(sqrt_price_limit_x128);

                // Get next initialized tick in the swap direction with limit
                let next_tick = Self::_get_next_initialized_tick(
                    ref self, current_tick, tick_limit, zero_for_one,
                );

                if next_tick == current_tick {
                    break;
                }

                // Calculate sqrt price at next tick
                let next_sqrt_price_x128 = math::get_sqrt_ratio_at_tick(next_tick);

                // Determine target price (either next tick or limit)
                let target_sqrt_price_x128 = if zero_for_one {
                    if next_sqrt_price_x128 < sqrt_price_limit_x128 {
                        sqrt_price_limit_x128
                    } else {
                        next_sqrt_price_x128
                    }
                } else {
                    if next_sqrt_price_x128 > sqrt_price_limit_x128 {
                        sqrt_price_limit_x128
                    } else {
                        next_sqrt_price_x128
                    }
                };

                // Compute swap step to target price
                let (
                    step_amount0,
                    step_amount1,
                    new_sqrt_price_x128,
                    step_fee_amount0,
                    step_fee_amount1,
                ) =
                    Self::_compute_swap_step(
                    ref self,
                    sqrt_price_x128,
                    target_sqrt_price_x128,
                    liquidity,
                    amount_specified_remaining,
                    zero_for_one,
                );

                // Update accumulated amounts
                amount0 = amount0 + step_amount0;
                amount1 = amount1 + step_amount1;

                // Calculate amount consumed in this step to decrement remaining
                let step_consumed_amount = if zero_for_one {
                    // For zero_for_one, we're spending token0 (input)
                    let abs_amount0 = if step_amount0 < 0 {
                        -step_amount0
                    } else {
                        step_amount0
                    };
                    let max_safe: i128 = 170141183460469231731687303715884105727;
                    if abs_amount0 <= max_safe && abs_amount0 > 0 {
                        let consumed: u128 = abs_amount0.try_into().unwrap();
                        consumed
                    } else {
                        0
                    }
                } else {
                    // For one_for_zero, we're spending token1 (input)
                    let abs_amount1 = if step_amount1 < 0 {
                        -step_amount1
                    } else {
                        step_amount1
                    };
                    let max_safe: i128 = 170141183460469231731687303715884105727;
                    if abs_amount1 <= max_safe && abs_amount1 > 0 {
                        let consumed: u128 = abs_amount1.try_into().unwrap();
                        consumed
                    } else {
                        0
                    }
                };

                // Safety check: if no progress is being made, break to avoid infinite loop
                if step_consumed_amount == 0 && liquidity == 0 {
                    break;
                }

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
                    }

                    if step_fee_amount1 > 0 {
                        let fee_amount1_u256: u256 = step_fee_amount1.try_into().unwrap();
                        let liquidity_u256: u256 = liquidity.try_into().unwrap();
                        let fee_delta1 = fee_amount1_u256 * q128;
                        let fee_delta1 = fee_delta1 / liquidity_u256;
                        self.pool.fee_growth_global1_x128.write(fee_growth1 + fee_delta1);
                    };
                }

                // Update price
                sqrt_price_x128 = new_sqrt_price_x128;
                current_tick = math::get_tick_at_sqrt_ratio(sqrt_price_x128);

                // Check if we reached the price limit
                if (zero_for_one && sqrt_price_x128 <= sqrt_price_limit_x128)
                    || (!zero_for_one && sqrt_price_x128 >= sqrt_price_limit_x128) {
                    break;
                }

                // If we reached the next tick, cross it
                // Use approximate comparison to handle floating point precision
                let price_diff = if sqrt_price_x128 > next_sqrt_price_x128 {
                    sqrt_price_x128 - next_sqrt_price_x128
                } else {
                    next_sqrt_price_x128 - sqrt_price_x128
                };
                let price_tolerance = math::Q128 / 1000000; // Small tolerance for comparison

                if price_diff <= price_tolerance || sqrt_price_x128 == next_sqrt_price_x128 {
                    Self::_cross_tick(ref self, next_tick, zero_for_one);

                    // Explicitly update current_tick and price to next tick to ensure progress
                    current_tick = next_tick;
                    sqrt_price_x128 = next_sqrt_price_x128;

                    // Update liquidity after crossing tick
                    let tick_entry = self.ticks.entry(next_tick);
                    let liquidity_net = tick_entry.liquidity_net.read();

                    if zero_for_one {
                        let net_abs: u128 = if liquidity_net < 0 {
                            let abs_val = -liquidity_net;
                            // Check if conversion is safe (max i128 is smaller than max u128)
                            let max_safe: i128 =
                                170141183460469231731687303715884105727; // max i128
                            if abs_val <= max_safe {
                                abs_val.try_into().unwrap()
                            } else {
                                liquidity // Use current liquidity as fallback
                            }
                        } else {
                            liquidity_net.try_into().unwrap()
                        };
                        // Prevent underflow
                        if net_abs <= liquidity {
                            liquidity = liquidity - net_abs;
                        } else {
                            liquidity = 0;
                        };
                    } else {
                        let net_abs: u128 = if liquidity_net > 0 {
                            let max_safe: i128 =
                                170141183460469231731687303715884105727; // max i128
                            if liquidity_net <= max_safe {
                                liquidity_net.try_into().unwrap()
                            } else {
                                0 // Prevent overflow
                            }
                        } else {
                            0
                        };
                        // Prevent overflow
                        let max_liquidity: u128 = 340282366920938463463374607431768211455;
                        if liquidity <= max_liquidity - net_abs {
                            liquidity = liquidity + net_abs;
                        } else {
                            liquidity = max_liquidity;
                        };
                    }

                    // Update amount remaining (consume the step)
                    if step_consumed_amount > amount_specified_remaining {
                        amount_specified_remaining = 0;
                    } else {
                        amount_specified_remaining = amount_specified_remaining
                            - step_consumed_amount;
                    };
                } else {
                    // Partial step, we didn't reach the next tick
                    // Consume remaining amount and exit
                    if step_consumed_amount > amount_specified_remaining {
                        amount_specified_remaining = 0;
                    } else {
                        amount_specified_remaining = amount_specified_remaining
                            - step_consumed_amount;
                    }
                    break;
                };
            }

            // Update pool state
            self.pool.sqrt_price_x128.write(sqrt_price_x128);
            self.pool.tick.write(current_tick);
            self.pool.liquidity.write(liquidity);

            // Emit swap event
            let caller = get_caller_address();
            self
                .emit(
                    Event::PoolEvent(
                        PoolEvent::Swap(
                            PoolSwap {
                                sender: caller,
                                zero_for_one,
                                amount0,
                                amount1,
                                sqrt_price_x128,
                                liquidity,
                                tick: current_tick,
                            },
                        ),
                    ),
                );

            (amount0, amount1)
        }

        /// Compute swap step from current price to target price
        /// Returns: (amount0, amount1, new_sqrt_price, fee_amount0, fee_amount1)
        fn _compute_swap_step(
            ref self: ContractState,
            sqrt_price_current: u256,
            sqrt_price_target: u256,
            liquidity: u128,
            amount_remaining: u128,
            zero_for_one: bool,
        ) -> (i128, i128, u256, u128, u128) {
            // Calculate price difference - ensure no underflow
            let sqrt_price_diff = if zero_for_one {
                if sqrt_price_current > sqrt_price_target {
                    sqrt_price_current - sqrt_price_target
                } else {
                    0 // Price already at or below target
                }
            } else {
                if sqrt_price_target > sqrt_price_current {
                    sqrt_price_target - sqrt_price_current
                } else {
                    0 // Price already at or above target
                }
            };

            // Calculate amount needed to reach target price
            // Formula for token1 (price moves): amount = liquidity * sqrt_price_diff / Q96
            // Formula for token0 (price moves): amount = liquidity * sqrt_price_diff / (price0 *
            // price1)
            // Simplified for MVP: amount = liquidity * sqrt_price_diff / Q96
            let amount_needed = if sqrt_price_diff == 0 || liquidity == 0 {
                0
            } else {
                let liquidity_u256: u256 = liquidity.into();
                let sqrt_price_diff_u256: u256 = sqrt_price_diff;
                let q128_u256: u256 = math::Q128;

                let amt_u256 = (liquidity_u256 * sqrt_price_diff_u256) / q128_u256;
                let amt: u128 = amt_u256.try_into().unwrap();
                amt
            };

            // Get pool fee rate
            let pool_fee = self.pool.fee.read();

            // Determine if we can reach target or need partial step
            let (new_sqrt_price_x128, amount0, amount1, fee_amount0, fee_amount1) =
                if amount_remaining >= amount_needed {
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
                // Formula: new_price = current_price ± (amount_remaining * current_price /
                // liquidity)
                let new_price = if liquidity == 0 || sqrt_price_current == 0 {
                    sqrt_price_current // Can't calculate, keep current
                } else {
                    let amount_rem_u256: u256 = amount_remaining.into();
                    let price_delta = math::mul_u256(amount_rem_u256, sqrt_price_current);
                    let price_delta = price_delta / liquidity.into();

                    if zero_for_one {
                        if price_delta < sqrt_price_current {
                            sqrt_price_current - price_delta
                        } else {
                            sqrt_price_target // Use target as fallback
                        }
                    } else {
                        sqrt_price_current + price_delta
                    }
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

            (amount0, amount1, new_sqrt_price_x128, fee_amount0, fee_amount1)
        }

        /// Get next initialized tick in swap direction (optimized bitmap lookup)
        fn _get_next_initialized_tick(
            ref self: ContractState, tick: i32, tick_limit: i32, zero_for_one: bool,
        ) -> i32 {
            let search_tick = if zero_for_one {
                tick
            } else {
                tick + 1
            };
            let (mut word_pos, mut bit_pos) = tick::position(search_tick);
            let mut word = self.tick_bitmap.bitmap.entry(word_pos).read();

            if zero_for_one { // Searching downwards (lt)
                if bit_pos > 0 {
                    let mask = (zylith::clmm::tick::power_of_2_u256(bit_pos) - 1);
                    let mut masked_word = word & mask;

                    if masked_word != 0 {
                        let highest = Self::_find_highest_bit(masked_word);
                        if highest >= 0 {
                            let found_tick = word_pos * 256 + highest;
                            let tick_entry = self.ticks.entry(found_tick);
                            if tick_entry.initialized.read() {
                                return found_tick;
                            }
                        }
                    }
                }

                // Search in previous words up to tick_limit
                word_pos = word_pos - 1;
                let min_word_pos = if tick_limit > math::MIN_TICK {
                    tick_limit / 256
                } else {
                    math::MIN_TICK / 256
                };
                while word_pos >= min_word_pos {
                    word = self.tick_bitmap.bitmap.entry(word_pos).read();
                    if word != 0 {
                        let highest = Self::_find_highest_bit(word);
                        if highest >= 0 {
                            let found_tick = word_pos * 256 + highest;
                            let tick_entry = self.ticks.entry(found_tick);
                            if tick_entry.initialized.read() {
                                return found_tick;
                            }
                        }
                    }
                    word_pos = word_pos - 1;
                }
                tick_limit
            } else { // Searching upwards (gt)
                if bit_pos < 255 {
                    let mask = ~(zylith::clmm::tick::power_of_2_u256(bit_pos + 1) - 1);
                    let mut masked_word = word & mask;

                    if masked_word != 0 {
                        let lowest = Self::_find_lowest_bit(masked_word);
                        if lowest >= 0 {
                            let found_tick = word_pos * 256 + lowest;
                            let tick_entry = self.ticks.entry(found_tick);
                            if tick_entry.initialized.read() {
                                return found_tick;
                            }
                        }
                    }
                }

                // Search in next words up to tick_limit
                word_pos = word_pos + 1;
                let max_word_pos = if tick_limit < math::MAX_TICK {
                    tick_limit / 256
                } else {
                    math::MAX_TICK / 256
                };
                while word_pos <= max_word_pos {
                    word = self.tick_bitmap.bitmap.entry(word_pos).read();
                    if word != 0 {
                        let lowest = Self::_find_lowest_bit(word);
                        if lowest >= 0 {
                            let found_tick = word_pos * 256 + lowest;
                            let tick_entry = self.ticks.entry(found_tick);
                            if tick_entry.initialized.read() {
                                return found_tick;
                            }
                        }
                    }
                    word_pos = word_pos + 1;
                }
                tick_limit
            }
        }

        fn _find_highest_bit(mut word: u256) -> i32 {
            if word == 0 {
                return -1;
            }
            let mut res = 0;
            if word >= 0x100000000000000000000000000000000 {
                word = word / 0x100000000000000000000000000000000;
                res += 128;
            }
            if word >= 0x10000000000000000 {
                word = word / 0x10000000000000000;
                res += 64;
            }
            if word >= 0x100000000 {
                word = word / 0x100000000;
                res += 32;
            }
            if word >= 0x10000 {
                word = word / 0x10000;
                res += 16;
            }
            if word >= 0x100 {
                word = word / 0x100;
                res += 8;
            }
            if word >= 0x10 {
                word = word / 0x10;
                res += 4;
            }
            if word >= 0x4 {
                word = word / 0x4;
                res += 2;
            }
            if word >= 0x2 {
                word = word / 0x2;
                res += 1;
            }
            res
        }

        fn _find_lowest_bit(mut word: u256) -> i32 {
            if word == 0 {
                return -1;
            }
            let mut res = 0;
            if word % 0x100000000000000000000000000000000 == 0 {
                word = word / 0x100000000000000000000000000000000;
                res += 128;
            }
            if word % 0x10000000000000000 == 0 {
                word = word / 0x10000000000000000;
                res += 64;
            }
            if word % 0x100000000 == 0 {
                word = word / 0x100000000;
                res += 32;
            }
            if word % 0x10000 == 0 {
                word = word / 0x10000;
                res += 16;
            }
            if word % 0x100 == 0 {
                word = word / 0x100;
                res += 8;
            }
            if word % 0x10 == 0 {
                word = word / 0x10;
                res += 4;
            }
            if word % 0x4 == 0 {
                word = word / 0x4;
                res += 2;
            }
            if word % 0x2 == 0 {
                word = word / 0x2;
                res += 1;
            }
            res
        }

        /// Cross a tick during swap - update liquidity and fee growth
        fn _cross_tick(ref self: ContractState, tick: i32, zero_for_one: bool) {
            let tick_entry = self.ticks.entry(tick);

            // Update fee growth outside (flip when crossing)
            // This is a simplified version - full implementation would track fee growth more
            // carefully
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
        fn _update_tick(ref self: ContractState, tick: i32, liquidity_delta: u128, upper: bool) {
            let tick_entry = self.ticks.entry(tick);

            if !tick_entry.initialized.read() {
                tick_entry.initialized.write(true);
                // Initialize tick in bitmap
                let (word_pos, bit_pos) = tick::position(tick);
                let mut word = self.tick_bitmap.bitmap.entry(word_pos).read();
                word = tick::set_bit(word, bit_pos);
                self.tick_bitmap.bitmap.entry(word_pos).write(word);
            }

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
            ref self: ContractState, tick_lower: i32, tick_upper: i32, is_token0: bool,
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

        /// Update Merkle root incrementally after adding a new leaf
        fn _update_merkle_root(ref self: ContractState, index: u32, leaf: felt252) -> felt252 {
            let mut current_hash = leaf;
            let mut current_index = index;

            // Height of the tree (TREE_DEPTH = 20)
            let mut level: u32 = 0;
            while level < 20 {
                let sibling_index = if current_index % 2 == 0 {
                    current_index + 1
                } else {
                    current_index - 1
                };

                // Store current node
                self.merkle_tree.nodes.entry((level, current_index)).write(current_hash);

                // Get sibling (if it exists, otherwise use 0 or default empty hash)
                let sibling = self.merkle_tree.nodes.entry((level, sibling_index)).read();

                // Compute next level hash
                if current_index % 2 == 0 {
                    current_hash = zylith::privacy::merkle_tree::hash_nodes(current_hash, sibling);
                } else {
                    current_hash = zylith::privacy::merkle_tree::hash_nodes(sibling, current_hash);
                }

                current_index = current_index / 2;
                level = level + 1;
            }

            current_hash
        }

        fn _recalculate_merkle_root(ref self: ContractState) -> felt252 {
            let next_index = self.merkle_tree.next_index.read();
            if next_index == 0 {
                return 0;
            }
            let mut leaves: Array<felt252> = ArrayTrait::new();
            let mut i: u32 = 0;
            while i < next_index {
                leaves.append(self.merkle_tree.leaves.entry(i).read());
                i = i + 1;
            }
            zylith::privacy::merkle_tree::calculate_root_from_leaves(leaves)
        }

        fn verify_membership_proof(
            ref self: ContractState, full_proof_with_hints: Span<felt252>,
        ) -> bool {
            let verifier_address = self.membership_verifier.read();
            let verifier = IMembershipVerifier { contract_address: verifier_address };

            // calling verifier
            let result = verifier.verify_groth16_proof_bn254(full_proof_with_hints);

            match result {
                Result::Ok(_public_inputs) => {
                    // if proof is valid !!

                    self
                        .emit(
                            ProofVerified {
                                proof_type: 'membership',
                                caller: get_caller_address(),
                                timestamp: starknet::get_block_timestamp(),
                            },
                        );

                    true
                },
                Result::Err(error) => {
                    // if Proof is invalid !
                    self
                        .emit(
                            ProofRejected {
                                proof_type: 'membership',
                                caller: get_caller_address(),
                                error: error,
                            },
                        );
                    false
                },
            }
        }

        fn verify_swap_proof(
            ref self: ContractState, full_proof_with_hints: Span<felt252>,
        ) -> bool {
            let verifier_address = self.swap_verifier.read();
            let verifier = ISwapVerifier { contract_address: verifier_address };

            let result = verifier.verify_groth16_proof_bn254(full_proof_with_hints);

            match result {
                Result::Ok(_public_inputs) => {
                    self
                        .emit(
                            ProofVerified {
                                proof_type: 'swap',
                                caller: get_caller_address(),
                                timestamp: starknet::get_block_timestamp(),
                            },
                        );

                    true
                },
                Result::Err(error) => {
                    self
                        .emit(
                            ProofRejected {
                                proof_type: 'swap', caller: get_caller_address(), error: error,
                            },
                        );

                    false
                },
            }
        }

        fn verify_withdraw_proof(
            ref self: ContractState, full_proof_with_hints: Span<felt252>,
        ) -> bool {
            let verifier_address = self.withdraw_verifier.read();
            let verifier = IWithdrawVerifier { contract_address: verifier_address };

            let result = verifier.verify_groth16_proof_bn254(full_proof_with_hints);

            match result {
                Result::Ok(_public_inputs) => {
                    self
                        .emit(
                            ProofVerified {
                                proof_type: 'withdraw',
                                caller: get_caller_address(),
                                timestamp: starknet::get_block_timestamp(),
                            },
                        );

                    true
                },
                Result::Err(error) => {
                    self
                        .emit(
                            ProofRejected {
                                proof_type: 'withdraw', caller: get_caller_address(), error: error,
                            },
                        );

                    false
                },
            }
        }
    }
}
