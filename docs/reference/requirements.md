## Description

**Zylith** is a shielded Concentrated Liquidity Market Maker (CLMM) being designed for Starknet/Ztarknet. The goal is to build a fully shielded AMM where all user actions and balances are private, including position ownership, swap amounts, routing, and liquidity distribution. The MVP will provide the minimal architecture required to demonstrate viability.

## System Architecture Summary

- A fully functional CLMM engine implemented in Cairo, closely matching the behavior and precision of Ekubo’s core swap engine, tick management, position bookkeeping, and fee flows.

- A shielded pool that manages commitments, nullifiers, a Merkle tree, and verification of membership proofs.

- A private swap framework where the user proves, in zero knowledge, that they own a note with a sufficient balance and that the CLMM price transition is calculated correctly.

- A private LP interaction layer for minting and burning liquidity positions using commitments instead of addresses. Tick ranges remain public in the MVP (bounds privacy deferred).

- An Association Set Provider (ASP) server similar to Privacy Pools, reconstructing Merkle paths for note proofs.

- A verifier built on Garaga + Circom for membership proofs and minimal swap/LP proofs required for MVP.

## MVP ScopeCLMM functionality included in MVP:

The CLMM layer is mostly a simplified Ekubo core. The following components will be implemented closely following Ekubo:

- **Core pool mechanics**

   - Pool storage state: sqrt price, tick, active liquidity, fee growth, protocol fees.

   - Tick structures: liquidity net/delta, fee growth outside, and initialized tick bitmap.

   - Tick bitmap lookup like Ekubo for efficient tick navigation.

   - Ekubo-like 128.128 sqrt price math and u128 liquidity/fee arithmetic.

- **Swap engine**

   - swap_step and swap loop matching Ekubo semantics.

   - Tick crossing logic with liquidity additions and removals.

   - Protocol fee accounting matching Ekubo (withdrawal-fee charged on liquidity burns, per-token protocol fees).

   - Exact integer arithmetic matching Ekubo behavior as closely as possible.

- **Liquidity management**

   - Add/remove liquidity across tick ranges.

   - Position bookkeeping keyed by cryptographic commitments rather than addresses.

   - Fee growth inside range, rewards, and accounting.


## CLMM contracts not included in the MVP

- TWAMM extension

- Limit order extension

- Oracle extension


## Privacy Features Included in the MVP

The shielded layer for the MVP includes the minimum required to support private deposits, withdrawals, private swaps, and private LP positions.

- **Shielded notes**

   - Users deposit assets into a pool and receive a commitment representing a private balance. The commitment structure follows Privacy Pools: Poseidon(Poseidon(secret, nullifier), amount). These commitments form the private balance source for swaps and LP actions.

- **Merkle tree and nullifiers**

   - All commitments are inserted into a Merkle tree whose root is used for zk membership proofs. Nullifiers prevent double spends. Historical root tracking allows proof flexibility.

- **Private swap verification**

   - A Circom circuit verifies that:

      - The user owns a note with amount_in (membership + nullifier uniqueness).

      - The CLMM swap math for a single-step or simplified multi-step path is computed correctly (new constraints beyond Privacy Pools).

      - The resulting price and output commitment match expected public outputs.

- **Private LP operations**

   - Liquidity positions are bound to commitments instead of addresses. LP minting and burning verify the user’s available balance in a private note via membership proof and nullifier checks. The actual amounts remain hidden, bounds/tick ranges remain public in MVP.


## Privacy Features Not Included in MVP (but part of final vision)

The full private AMM will eventually add deeper and broader privacy layers such as:

- Private multi-hop routing

- Private concentrated liquidity range selection

- Private limit orders

- Private oracle integration

- Zero-knowledge proof of exact swap path inside CLMM

- Private fee collection

- Private pool initialization

- Private TWAMM for long-range orders

- Private batching and proof aggregation


## Rust Association Set Provider (ASP)

The MVP includes a Rust server that reconstructs Merkle paths by consuming deposit events and maintaining Merkle tree replicas off-chain (height aligned to on-chain tree: height 25 -> 2^24 leaves, proofs with 24 path elements). This follows the Privacy Pools design and is needed for the Circom prover to generate membership proofs. It will track both the deposit tree and an associated set tree, and serve paths for each.ZK Verifier Contract

Garaga will be used to verify Groth16 proofs for membership checks and simplified swap/LP circuits. The MVP focuses only on essential circuits required for:

- Membership

- Nullifier check

- Correct private swap transition (new VK/constants vs Privacy Pools)

- Correct liquidity mint/burn (new VK/constants vs Privacy Pools)


## Contracts Included in the MVP

The MVP will include the following Cairo contracts:

1. **CLMM contracts**

- Math lib for 128.128 sqrt price and u128 liquidity/fee arithmetic

- Tick math

- Tick bitmap

- Pool state

- Swap

- Liquidity

- Fees

- ZylithPool main contract integrating everything

2. **Privacy contracts**

- ShieldedNote for commitments

- MerkleTree component

- Verifier integration with Garaga

- Nullifier registry

3. **Interfaces**

- ZylithPool external CLI-like interface

- IVerifier interface

- ERC20 abstraction

## Implementation Timeline Estimate

- **Weeks 1–2**: Core math, tick math, pool structures, swap engine, liquidity, fees, main pool contract integration

- **Weeks 3–5**: Shielded layer (Merkle tree, notes, deposit/withdraw), Circom circuits, verifier integration, ASP server

- **Week 6**: Tests, minimal frontend, docs
