# Zylith Protocol - API Reference

**Version**: 1.0
**Last Updated**: December 2025
**Contract Version**: MVP 1.0

---

## Table of Contents

1. [Overview](#overview)
2. [Core Interfaces](#core-interfaces)
3. [CLMM API](#clmm-api)
4. [Privacy API](#privacy-api)
5. [Integration API](#integration-api)
6. [Events](#events)
7. [Data Structures](#data-structures)
8. [Error Codes](#error-codes)
9. [ASP REST API](#asp-rest-api)

---

## Overview

This document provides a comprehensive reference for all public interfaces, functions, and data structures in the Zylith Protocol.

### API Categories

| Category | Purpose | Primary Users |
|----------|---------|---------------|
| **CLMM API** | Concentrated liquidity operations | Liquidity providers, traders |
| **Privacy API** | Commitment and ZK operations | Privacy-conscious users |
| **Integration API** | Private swaps and withdrawals | All users |
| **ASP REST API** | Off-chain Merkle path queries | Client applications |

### Contract Addresses

| Network | Contract | Address |
|---------|----------|---------|
| **Starknet Mainnet** | Zylith Main Contract | TBD |
| **Starknet Sepolia** | Zylith Main Contract | See CONTRACT_ADDRESS.md |
| **Local Devnet** | Zylith Main Contract | Deployed locally |

---

## Core Interfaces

### IZylith - Main Contract Interface

```cairo
#[starknet::interface]
trait IZylith<TContractState> {
    // Pool Management
    fn initialize_pool(
        ref self: TContractState,
        token0: ContractAddress,
        token1: ContractAddress,
        fee: u128,
        tick_spacing: i32,
        sqrt_price_x96: u128
    );

    fn get_pool_state(self: @TContractState) -> PoolState;

    // CLMM Operations
    fn swap(
        ref self: TContractState,
        zero_for_one: bool,
        amount_specified: i128,
        sqrt_price_limit_x96: u128
    ) -> (i128, i128);

    fn mint(
        ref self: TContractState,
        tick_lower: i32,
        tick_upper: i32,
        amount: u128
    ) -> (u128, u128, u128);

    fn burn(
        ref self: TContractState,
        tick_lower: i32,
        tick_upper: i32,
        amount: u128
    ) -> (u128, u128);

    fn collect(
        ref self: TContractState,
        tick_lower: i32,
        tick_upper: i32
    ) -> (u128, u128);

    // Privacy Operations
    fn deposit(
        ref self: TContractState,
        amount: u128,
        commitment: felt252
    );

    fn private_swap(
        ref self: TContractState,
        proof: Array<felt252>,
        public_inputs: Array<felt252>,
        zero_for_one: bool
    ) -> felt252;

    fn private_withdraw(
        ref self: TContractState,
        proof: Array<felt252>,
        public_inputs: Array<felt252>,
        recipient: ContractAddress,
        amount: u128
    );

    // Merkle Tree
    fn get_merkle_root(self: @TContractState) -> felt252;
    fn is_nullifier_spent(self: @TContractState, nullifier: felt252) -> bool;
}
```

---

## CLMM API

### Pool Initialization

#### initialize_pool

Initializes a new liquidity pool with specified parameters.

**Function Signature**:
```cairo
fn initialize_pool(
    ref self: TContractState,
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
    tick_spacing: i32,
    sqrt_price_x96: u128
)
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `token0` | `ContractAddress` | First token address | Must be valid ERC20 |
| `token1` | `ContractAddress` | Second token address | Must be valid ERC20, token0 < token1 |
| `fee` | `u128` | Fee in basis points | Typical: 3000 (0.3%) |
| `tick_spacing` | `i32` | Minimum tick spacing | Default: 60 |
| `sqrt_price_x96` | `u128` | Initial sqrt price | Q96 fixed-point format |

**Returns**: None

**Events**: `PoolInitialized`

**Access Control**: Admin only (one-time operation)

**Example**:
```cairo
// Initialize pool with 0.3% fee
zylith.initialize_pool(
    token0: token_a_address,
    token1: token_b_address,
    fee: 3000,
    tick_spacing: 60,
    sqrt_price_x96: 79228162514264337593543950336  // 1:1 price ratio
);
```

---

### Swap Operations

#### swap

Executes a token swap within the pool.

**Function Signature**:
```cairo
fn swap(
    ref self: TContractState,
    zero_for_one: bool,
    amount_specified: i128,
    sqrt_price_limit_x96: u128
) -> (i128, i128)
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `zero_for_one` | `bool` | Direction (token0→token1 if true) | - |
| `amount_specified` | `i128` | Amount to swap (negative for exact output) | Non-zero |
| `sqrt_price_limit_x96` | `u128` | Price limit for slippage protection | Must respect direction |

**Returns**:

| Return Value | Type | Description |
|-------------|------|-------------|
| `amount0` | `i128` | Token0 delta (negative = outflow) |
| `amount1` | `i128` | Token1 delta (negative = outflow) |

**Events**: `Swap`

**Access Control**: Public

**Example**:
```cairo
// Swap 100 token0 for token1, with 1% slippage limit
let (amount0, amount1) = zylith.swap(
    zero_for_one: true,
    amount_specified: 100_000000,  // 100 tokens (6 decimals)
    sqrt_price_limit_x96: sqrt_price_limit
);
```

---

### Liquidity Operations

#### mint

Adds liquidity to a specified tick range.

**Function Signature**:
```cairo
fn mint(
    ref self: TContractState,
    tick_lower: i32,
    tick_upper: i32,
    amount: u128
) -> (u128, u128, u128)
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `tick_lower` | `i32` | Lower tick bound | Must be divisible by tick_spacing |
| `tick_upper` | `i32` | Upper tick bound | Must be > tick_lower, divisible by tick_spacing |
| `amount` | `u128` | Liquidity amount | Q64.96 fixed-point |

**Returns**:

| Return Value | Type | Description |
|-------------|------|-------------|
| `amount0` | `u128` | Token0 required |
| `amount1` | `u128` | Token1 required |
| `liquidity` | `u128` | Actual liquidity minted |

**Events**: `Mint`

**Access Control**: Public

---

#### burn

Removes liquidity from a specified tick range.

**Function Signature**:
```cairo
fn burn(
    ref self: TContractState,
    tick_lower: i32,
    tick_upper: i32,
    amount: u128
) -> (u128, u128)
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `tick_lower` | `i32` | Lower tick bound | Must match existing position |
| `tick_upper` | `i32` | Upper tick bound | Must match existing position |
| `amount` | `u128` | Liquidity to remove | ≤ position liquidity |

**Returns**:

| Return Value | Type | Description |
|-------------|------|-------------|
| `amount0` | `u128` | Token0 returned |
| `amount1` | `u128` | Token1 returned |

**Events**: `Burn`

**Access Control**: Position owner

---

#### collect

Collects accrued fees for a position.

**Function Signature**:
```cairo
fn collect(
    ref self: TContractState,
    tick_lower: i32,
    tick_upper: i32
) -> (u128, u128)
```

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `tick_lower` | `i32` | Lower tick bound |
| `tick_upper` | `i32` | Upper tick bound |

**Returns**:

| Return Value | Type | Description |
|-------------|------|-------------|
| `collect0` | `u128` | Token0 fees collected |
| `collect1` | `u128` | Token1 fees collected |

**Events**: `Collect`

**Access Control**: Position owner

---

## Privacy API

### Deposit Operations

#### deposit

Deposits tokens and receives a commitment for private balance.

**Function Signature**:
```cairo
fn deposit(
    ref self: TContractState,
    amount: u128,
    commitment: felt252
)
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `amount` | `u128` | Token amount to deposit | User must have approval |
| `commitment` | `felt252` | Poseidon hash commitment | Must be unique, format: Hash(Hash(secret, nullifier), amount) |

**Returns**: None

**Events**: `Deposit(commitment, index, amount_hash)`

**Access Control**: Public

**Commitment Structure**:
```typescript
commitment = Poseidon(Poseidon(secret, nullifier), amount)
```

**Example**:
```cairo
// Client-side: generate commitment
let secret = generate_random_felt252();
let nullifier = generate_random_felt252();
let commitment = poseidon(poseidon(secret, nullifier), amount);

// On-chain: deposit
zylith.deposit(amount: 1000_000000, commitment: commitment);
```

---

### Merkle Tree Operations

#### get_merkle_root

Returns the current Merkle tree root.

**Function Signature**:
```cairo
fn get_merkle_root(self: @TContractState) -> felt252
```

**Returns**: `felt252` - Current Merkle root

**Access Control**: Public (read-only)

---

#### is_nullifier_spent

Checks if a nullifier has been used.

**Function Signature**:
```cairo
fn is_nullifier_spent(self: @TContractState, nullifier: felt252) -> bool
```

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `nullifier` | `felt252` | Nullifier hash to check |

**Returns**: `bool` - True if spent, false otherwise

**Access Control**: Public (read-only)

---

## Integration API

### Private Swap

#### private_swap

Executes a private swap using zero-knowledge proof.

**Function Signature**:
```cairo
fn private_swap(
    ref self: TContractState,
    proof: Array<felt252>,
    public_inputs: Array<felt252>,
    zero_for_one: bool
) -> felt252
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `proof` | `Array<felt252>` | Groth16 ZK proof | Generated off-chain via Circom |
| `public_inputs` | `Array<felt252>` | Public proof inputs | [commitment_in, commitment_out, root, amount_out] |
| `zero_for_one` | `bool` | Swap direction | - |

**Public Inputs Format**:
```
[0]: commitment_in      // Input commitment being spent
[1]: commitment_out     // Output commitment being created
[2]: merkle_root       // Merkle tree root
[3]: amount_out        // Output amount (public for MVP)
```

**Returns**: `felt252` - New commitment for output tokens

**Events**: `PrivateSwap`

**Access Control**: Valid proof required

**Example Flow**:
```
1. Client retrieves Merkle path from ASP
2. Client generates ZK proof off-chain (Circom + snarkjs)
3. Client submits proof + public inputs to contract
4. Contract verifies proof via Garaga
5. Contract executes CLMM swap
6. Contract inserts new output commitment
```

---

### Private Withdrawal

#### private_withdraw

Withdraws tokens privately using zero-knowledge proof.

**Function Signature**:
```cairo
fn private_withdraw(
    ref self: TContractState,
    proof: Array<felt252>,
    public_inputs: Array<felt252>,
    recipient: ContractAddress,
    amount: u128
)
```

**Parameters**:

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `proof` | `Array<felt252>` | Groth16 ZK proof | Generated off-chain |
| `public_inputs` | `Array<felt252>` | Public proof inputs | [commitment, nullifier_hash, root, amount] |
| `recipient` | `ContractAddress` | Withdrawal recipient | Any valid address |
| `amount` | `u128` | Amount to withdraw | Must match commitment |

**Public Inputs Format**:
```
[0]: commitment        // Commitment being spent
[1]: nullifier_hash    // Hash of nullifier (for privacy)
[2]: merkle_root      // Merkle tree root
[3]: amount           // Amount to withdraw
```

**Returns**: None

**Events**: `PrivateWithdraw`

**Access Control**: Valid proof required, nullifier not previously spent

---

## Events

### Pool Events

#### PoolInitialized

Emitted when a pool is initialized.

```cairo
#[derive(Drop, starknet::Event)]
struct PoolInitialized {
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
    tick_spacing: i32,
    sqrt_price_x96: u128
}
```

---

#### Swap

Emitted on every swap.

```cairo
#[derive(Drop, starknet::Event)]
struct Swap {
    sender: ContractAddress,
    recipient: ContractAddress,
    amount0: i128,
    amount1: i128,
    sqrt_price_x96: u128,
    liquidity: u128,
    tick: i32
}
```

---

### Privacy Events

#### Deposit

Emitted when tokens are deposited.

```cairo
#[derive(Drop, starknet::Event)]
struct Deposit {
    commitment: felt252,
    leaf_index: u32,
    timestamp: u64
}
```

---

#### PrivateSwap

Emitted on private swaps.

```cairo
#[derive(Drop, starknet::Event)]
struct PrivateSwap {
    commitment_out: felt252,
    leaf_index: u32,
    timestamp: u64
}
```

---

#### PrivateWithdraw

Emitted on private withdrawals.

```cairo
#[derive(Drop, starknet::Event)]
struct PrivateWithdraw {
    nullifier_hash: felt252,
    recipient: ContractAddress,
    timestamp: u64
}
```

---

## Data Structures

### PoolState

```cairo
struct PoolState {
    sqrt_price_x96: u128,
    tick: i32,
    liquidity: u128,
    fee_growth_global0_x128: u256,
    fee_growth_global1_x128: u256
}
```

| Field | Type | Description |
|-------|------|-------------|
| `sqrt_price_x96` | `u128` | Current sqrt price (Q96) |
| `tick` | `i32` | Current tick |
| `liquidity` | `u128` | Active liquidity (Q64.96) |
| `fee_growth_global0_x128` | `u256` | Token0 fee growth (Q128) |
| `fee_growth_global1_x128` | `u256` | Token1 fee growth (Q128) |

---

### TickInfo

```cairo
struct TickInfo {
    initialized: bool,
    liquidity_gross: u128,
    liquidity_net: i128,
    fee_growth_outside0_x128: u256,
    fee_growth_outside1_x128: u256
}
```

---

### PositionInfo

```cairo
struct PositionInfo {
    liquidity: u128,
    fee_growth_inside0_last_x128: u256,
    fee_growth_inside1_last_x128: u256,
    tokens_owed0: u128,
    tokens_owed1: u128
}
```

---

## Error Codes

### CLMM Errors

| Error Code | Message | Description | Solution |
|------------|---------|-------------|----------|
| `'Invalid tick'` | Tick not divisible by spacing | Tick must align with tick_spacing | Use valid tick values |
| `'Price limit exceeded'` | Slippage limit reached | Swap exceeded price limit | Increase slippage tolerance |
| `'Insufficient liquidity'` | Not enough liquidity | Pool lacks liquidity for swap | Reduce swap size or add liquidity |
| `'Invalid tick range'` | tick_lower >= tick_upper | Invalid position bounds | Ensure tick_lower < tick_upper |

### Privacy Errors

| Error Code | Message | Description | Solution |
|------------|---------|-------------|----------|
| `'Invalid proof'` | ZK proof verification failed | Proof is malformed or invalid | Regenerate proof with correct inputs |
| `'Nullifier spent'` | Nullifier already used | Double-spend attempt detected | Use a different commitment |
| `'Invalid root'` | Merkle root mismatch | Root doesn't match current tree | Update Merkle path from ASP |
| `'Commitment exists'` | Duplicate commitment | Commitment already in tree | Generate new commitment |

---

## ASP REST API

### Base URL

```
http://localhost:8080/api/v1
```

### Endpoints

#### GET /health

Health check endpoint.

**Response**:
```json
{
  "status": "ok",
  "sync_block": 12345,
  "latest_block": 12346,
  "merkle_root": "0x1234..."
}
```

---

#### GET /merkle/root

Get current Merkle tree root.

**Response**:
```json
{
  "root": "0x1234...",
  "block_number": 12345
}
```

---

#### GET /merkle/path/:commitment

Get Merkle path for a commitment.

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `commitment` | `hex string` | Commitment hash |

**Response**:
```json
{
  "commitment": "0x1234...",
  "leaf_index": 42,
  "path": ["0xabc...", "0xdef...", ...],
  "path_indices": [0, 1, 0, ...],
  "root": "0x5678..."
}
```

**Error Codes**:
- `404`: Commitment not found
- `500`: Internal server error

---

#### GET /merkle/verify/:commitment

Verify a commitment exists in the tree.

**Response**:
```json
{
  "exists": true,
  "leaf_index": 42
}
```

---

## Code Examples

### Complete Swap Example

```cairo
// 1. Approve tokens
token0.approve(zylith_address, 100_000000);

// 2. Execute swap
let sqrt_price_limit = calculate_price_limit(0.01); // 1% slippage
let (amount0, amount1) = zylith.swap(
    zero_for_one: true,
    amount_specified: 100_000000,
    sqrt_price_limit_x96: sqrt_price_limit
);

// 3. Check outputs
assert(amount0 == -100_000000); // Exact input
assert(amount1 > 0); // Received output
```

### Complete Private Deposit-Swap-Withdraw Flow

```typescript
// 1. Generate commitment
const secret = randomFelt252();
const nullifier = randomFelt252();
const amount = 1000_000000;
const commitment = poseidon([poseidon([secret, nullifier]), amount]);

// 2. Deposit
await zylith.deposit(amount, commitment);

// 3. Wait for ASP sync, get Merkle path
const path = await asp.getMerklePath(commitment);

// 4. Generate swap proof
const swapProof = await generateSwapProof({
  secret, nullifier, amount,
  merklePath: path.path,
  merkleIndices: path.path_indices
});

// 5. Execute private swap
const newCommitment = await zylith.private_swap(
  swapProof.proof,
  swapProof.publicInputs,
  true // zero_for_one
);

// 6. Generate withdrawal proof
const withdrawProof = await generateWithdrawProof({
  secret, nullifier, amount,
  merklePath: path.path,
  merkleIndices: path.path_indices
});

// 7. Withdraw to recipient
await zylith.private_withdraw(
  withdrawProof.proof,
  withdrawProof.publicInputs,
  recipientAddress,
  amount
);
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | December 2025 | Initial API documentation |

---

**Maintained By**: Zylith Protocol Team
**For Support**: Open a GitHub issue or contact the development team
**API Stability**: MVP - Breaking changes possible before v1.0 stable
