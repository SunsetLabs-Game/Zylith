# Zylith Usage Guide

## Overview

Zylith is a shielded Concentrated Liquidity Market Maker (CLMM) for Starknet. This guide explains how to interact with the protocol for both public and private operations.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Building and Testing](#building-and-testing)
3. [Public Operations](#public-operations)
4. [Private Operations](#private-operations)
5. [Generating ZK Proofs](#generating-zk-proofs)
6. [Using the ASP](#using-the-asp)
7. [Complete Flow Examples](#complete-flow-examples)

## Prerequisites

- Scarb (Cairo package manager)
- Starknet Foundry (snforge, sncast)
- Node.js 18+ (for proof generation)
- Rust (for ASP server)

```bash
# Install Scarb
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
```

## Building and Testing

### Build Contracts

```bash
cd zylith
scarb build
```

### Run Tests

```bash
# Run all tests
snforge test

# Run specific test file
snforge test test_integration

# Run with verbose output
snforge test -v
```

## Public Operations

### Initialize a Pool

```cairo
// Initialize a pool with token0/token1
dispatcher.initialize(
    token0_address,     // First token
    token1_address,     // Second token
    fee,                // Fee tier (e.g., 3000 = 0.3%)
    tick_spacing,       // Tick spacing (e.g., 60)
    sqrt_price_x128     // Initial price as sqrt(price) * 2^128
);
```

### Add Liquidity (Public)

```cairo
// Mint liquidity in a tick range
let (amount0, amount1) = dispatcher.mint(
    tick_lower,     // Lower bound tick
    tick_upper,     // Upper bound tick
    liquidity       // Liquidity amount
);
// Note: Caller must have approved token0/token1 transfers
```

### Swap Tokens (Public)

```cairo
// Execute a swap
let (delta0, delta1) = dispatcher.swap(
    zero_for_one,           // true = sell token0, false = sell token1
    amount_specified,       // Input amount
    sqrt_price_limit_x128   // Price limit (MIN_SQRT_RATIO or MAX_SQRT_RATIO)
);
```

## Private Operations

### Private Deposit

Deposit tokens into the shielded pool and receive a commitment.

```cairo
// Deposit tokens privately
dispatcher.private_deposit(
    token_address,  // Token to deposit
    amount,         // Amount (u256)
    commitment      // Your commitment = Hash(Hash(secret, nullifier), amount)
);
```

### Private Withdraw

Withdraw tokens by proving ownership of a commitment.

```cairo
dispatcher.private_withdraw(
    proof,          // Groth16 proof from snarkjs
    public_inputs,  // [nullifier, root, recipient, amount]
    token,          // Token to withdraw
    recipient,      // Recipient address
    amount          // Amount to withdraw
);
```

### Private Swap

Swap tokens privately using ZK proofs.

```cairo
let (delta0, delta1) = dispatcher.private_swap(
    proof,                  // Groth16 proof
    public_inputs,          // [nullifier, root, new_commitment, ...]
    zero_for_one,           // Swap direction
    amount_specified,       // Swap amount
    sqrt_price_limit_x128,  // Price limit
    new_commitment          // Output note commitment
);
```

### Private LP Operations

```cairo
// Private mint liquidity
let (amount0, amount1) = dispatcher.private_mint(
    proof,
    public_inputs,
    tick_lower,
    tick_upper,
    liquidity,
    new_commitment
);

// Private burn liquidity
let (amount0, amount1) = dispatcher.private_burn(
    proof,
    public_inputs,
    tick_lower,
    tick_upper,
    liquidity,
    new_commitment
);
```

## Generating ZK Proofs

### Setup

```bash
cd circuits
npm install
```

### Generate a Proof

1. Create an input file (e.g., `input_membership.json`):

```json
{
    "root": "12345...",
    "commitment": "67890...",
    "secret": "111",
    "nullifier": "222",
    "amount": "1000000",
    "pathElements": ["...", "..."],
    "pathIndices": [0, 1, 0, ...]
}
```

2. Generate the proof:

```bash
node scripts/generate_proof.js membership input_membership.json
```

3. The proof will be saved to `proofs/` directory.

### Circuit Types

| Circuit | Purpose | Public Inputs |
|---------|---------|---------------|
| `membership` | Prove commitment exists in tree | root, commitment |
| `withdraw` | Prove ownership for withdrawal | nullifier, root, recipient, amount |
| `swap` | Prove valid private swap | nullifier, root, new_commitment, amount_specified, ... |
| `lp` | Prove valid LP operation | nullifier, root, tick_lower, tick_upper, liquidity, ... |

## Using the ASP

The Association Set Provider (ASP) maintains off-chain Merkle trees and provides proofs.

### Start the ASP

```bash
cd asp
cargo run --release
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/deposit/proof/:index` | GET | Get Merkle proof for deposit at index |
| `/deposit/root` | GET | Get current deposit tree root |
| `/associated/proof/:index` | GET | Get associated set proof |
| `/health` | GET | Health check |

### Example: Get a Merkle Proof

```bash
curl http://localhost:3000/deposit/proof/0
```

Response:
```json
{
    "leaf_index": 0,
    "path_elements": ["0x123...", "0x456...", ...],
    "path_indices": [0, 1, 0, ...],
    "root": "0x789..."
}
```

## Complete Flow Examples

### Example 1: Private Deposit and Withdraw

```javascript
// 1. Generate commitment off-chain
const secret = randomField();
const nullifier = randomField();
const amount = 1000000n;
const commitment = poseidon(poseidon(secret, nullifier), amount);

// 2. Deposit on-chain
await zylith.private_deposit(token, amount, commitment);

// 3. Wait for ASP to sync
await sleep(10000);

// 4. Get Merkle proof from ASP
const { pathElements, pathIndices, root } = await asp.getProof(leafIndex);

// 5. Generate withdraw proof
const proof = await generateWithdrawProof({
    nullifier,
    root,
    recipient: myAddress,
    amount,
    secret,
    pathElements,
    pathIndices
});

// 6. Withdraw on-chain
await zylith.private_withdraw(
    proof.proofArray,
    proof.publicInputs,
    token,
    myAddress,
    amount
);
```

### Example 2: Private Swap

```javascript
// 1. Have an existing commitment in the tree
// 2. Get Merkle proof from ASP
const { pathElements, pathIndices, root } = await asp.getProof(myLeafIndex);

// 3. Calculate new commitment for output note
const newSecret = randomField();
const newNullifier = randomField();
const outputAmount = inputAmount - swapAmount + expectedOutput;
const newCommitment = poseidon(poseidon(newSecret, newNullifier), outputAmount);

// 4. Generate swap proof
const proof = await generateSwapProof({
    nullifier: myNullifier,
    root,
    new_commitment: newCommitment,
    amount_specified: swapAmount,
    // ... other inputs
});

// 5. Execute private swap
await zylith.private_swap(
    proof.proofArray,
    proof.publicInputs,
    zeroForOne,
    swapAmount,
    priceLimit,
    newCommitment
);
```

## Troubleshooting

### "INVALID_MERKLE_ROOT"
- The root in your proof doesn't match any known root
- Ensure ASP is synced and you're using a valid historical root

### "Nullifier already spent"
- The nullifier has been used before
- Each commitment can only be spent once

### "Proof verification failed"
- Ensure proof was generated with correct inputs
- Check that public inputs match contract expectations

## Security Considerations

1. **Keep secrets safe**: Never share your `secret` or `nullifier`
2. **Use fresh randomness**: Generate new secrets for each note
3. **Verify ASP data**: Cross-check Merkle roots with on-chain state
4. **Historical roots**: Proofs can be generated against any known root

