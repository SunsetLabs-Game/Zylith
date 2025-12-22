# Zylith Protocol - Technical Architecture

**Version**: 1.0
**Last Updated**: December 2025
**Status**: Production

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Component Specifications](#component-specifications)
4. [Data Models](#data-models)
5. [Integration Patterns](#integration-patterns)
6. [Security Architecture](#security-architecture)
7. [Performance Considerations](#performance-considerations)

---

## Overview

Zylith is a privacy-preserving Concentrated Liquidity Market Maker (CLMM) protocol built on Starknet. The architecture combines three core layers: a CLMM engine for efficient liquidity management, a privacy layer using zero-knowledge proofs, and an integration layer that seamlessly connects both systems.

### Design Principles

| Principle | Description | Implementation |
|-----------|-------------|----------------|
| **Modularity** | Clear separation of concerns between layers | Independent CLMM, Privacy, and Integration modules |
| **Precision** | Exact arithmetic matching Ekubo specifications | Q96 fixed-point for prices, Q128 for fee growth |
| **Privacy** | Zero information leakage beyond public parameters | Commitment-based ownership, ZK membership proofs |
| **Efficiency** | Optimized gas costs and storage patterns | Bitmap-based tick management, sparse storage |
| **Security** | Multiple layers of validation and overflow protection | u256 arithmetic, bounds checking, proof verification |

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Wallet     │  │    Proof     │  │    Commitment        │  │
│  │ Integration  │  │  Generator   │  │     Manager          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────┘
                              │ ZK Proofs + Public Inputs
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Starknet Blockchain                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  Zylith Smart Contract                    │  │
│  │                                                           │  │
│  │  ┌──────────────────────────────────────────────────┐   │  │
│  │  │              CLMM Layer                          │   │  │
│  │  │  ┌───────────┐ ┌──────────┐ ┌────────────────┐ │   │  │
│  │  │  │   Math    │ │   Tick   │ │   Liquidity    │ │   │  │
│  │  │  │  Library  │ │  Manager │ │     Engine     │ │   │  │
│  │  │  └───────────┘ └──────────┘ └────────────────┘ │   │  │
│  │  │  ┌───────────┐ ┌──────────┐ ┌────────────────┐ │   │  │
│  │  │  │   Pool    │ │   Swap   │ │    Position    │ │   │  │
│  │  │  │   State   │ │  Engine  │ │    Manager     │ │   │  │
│  │  │  └───────────┘ └──────────┘ └────────────────┘ │   │  │
│  │  └──────────────────────────────────────────────────┘   │  │
│  │                                                           │  │
│  │  ┌──────────────────────────────────────────────────┐   │  │
│  │  │            Privacy Layer                         │   │  │
│  │  │  ┌───────────┐ ┌──────────┐ ┌────────────────┐ │   │  │
│  │  │  │  Merkle   │ │  Commit  │ │   Nullifier    │ │   │  │
│  │  │  │   Tree    │ │   ment   │ │    Registry    │ │   │  │
│  │  │  └───────────┘ └──────────┘ └────────────────┘ │   │  │
│  │  │  ┌───────────┐ ┌──────────┐ ┌────────────────┐ │   │  │
│  │  │  │  Verifier │ │  Deposit │ │   Withdraw     │ │   │  │
│  │  │  │ (Garaga)  │ │  Handler │ │    Handler     │ │   │  │
│  │  │  └───────────┘ └──────────┘ └────────────────┘ │   │  │
│  │  └──────────────────────────────────────────────────┘   │  │
│  │                                                           │  │
│  │  ┌──────────────────────────────────────────────────┐   │  │
│  │  │          Integration Layer                       │   │  │
│  │  │  ┌───────────┐ ┌──────────┐ ┌────────────────┐ │   │  │
│  │  │  │  Private  │ │  Private │ │   Private LP   │ │   │  │
│  │  │  │   Swap    │ │   With-  │ │   Operations   │ │   │  │
│  │  │  │  Handler  │ │   draw   │ │                │ │   │  │
│  │  │  └───────────┘ └──────────┘ └────────────────┘ │   │  │
│  │  └──────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Event Stream: Deposits, Swaps, Withdrawals, Nullifiers         │
└─────────────────────────────┬───────────────────────────────────┘
                              │ Event Indexing
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│          Association Set Provider (ASP) - Off-Chain              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │    Event     │  │    Merkle    │  │   Associated Set     │  │
│  │   Indexer    │  │     Tree     │  │      Manager         │  │
│  │              │  │   Replica    │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│  ┌──────────────┐                                               │
│  │  REST API    │  GET /merkle/path/:commitment                 │
│  │  Server      │  GET /merkle/root                             │
│  └──────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Specifications

### CLMM Layer Components

| Component | Module | Responsibility | Key Functions |
|-----------|--------|----------------|---------------|
| **Math Library** | `clmm/math.cairo` | u128 arithmetic, tick/price conversions | `get_sqrt_ratio_at_tick()`, `get_tick_at_sqrt_ratio()`, `mul_div()` |
| **Tick Manager** | `clmm/tick.cairo` | Bitmap-based tick tracking | `flip_tick()`, `next_initialized_tick()`, `update_tick()` |
| **Liquidity Engine** | `clmm/liquidity.cairo` | Q64.96 fixed-point calculations | `get_liquidity_for_amounts()`, `get_amounts_for_liquidity()` |
| **Pool State** | `clmm/pool.cairo` | Pool storage and initialization | `initialize_pool()`, `get_pool_state()`, event emissions |
| **Swap Engine** | `clmm/swap.cairo` | Swap execution and tick crossing | `swap()`, `swap_step()`, `cross_tick()` |
| **Position Manager** | `clmm/position.cairo` | Position minting/burning/fee collection | `mint()`, `burn()`, `collect()`, position tracking |

### Privacy Layer Components

| Component | Module | Responsibility | Key Functions |
|-----------|--------|----------------|---------------|
| **Merkle Tree** | `privacy/merkle_tree.cairo` | Poseidon BN254 Merkle tree | `insert_leaf()`, `get_root()`, `verify_proof()` |
| **Commitment** | `privacy/commitment.cairo` | Commitment generation and validation | `compute_commitment()`, `validate_commitment()` |
| **Deposit Handler** | `privacy/deposit.cairo` | Private deposit processing | `deposit()`, commitment insertion, event emission |
| **Nullifier Registry** | `privacy/nullifier.cairo` | Double-spend prevention | `mark_nullifier_spent()`, `is_nullifier_spent()` |
| **Verifier** | `privacy/verifier.cairo` | Garaga Groth16 verification | `verify_proof()`, public input validation |

### Integration Layer Components

| Component | Module | Responsibility | Key Functions |
|-----------|--------|----------------|---------------|
| **Private Swap** | `integration/swap.cairo` | ZK-verified swap execution | `private_swap()`, proof verification, CLMM execution |
| **Private Withdraw** | `integration/withdraw.cairo` | Nullifier-checked withdrawals | `private_withdraw()`, nullifier marking, token transfer |
| **Private LP** | `integration/lp.cairo` | Commitment-based positions | `mint_position()`, `burn_position()`, fee collection |

### Off-Chain Components

| Component | Language | Responsibility | Interfaces |
|-----------|----------|----------------|------------|
| **Association Set Provider** | Rust | Event indexing, Merkle path serving | REST API (port 8080) |
| **Circom Circuits** | Circom | ZK proof generation | `membership.circom`, `swap.circom`, `withdraw.circom` |
| **Proof Generator** | JavaScript/WASM | Client-side proof generation | snarkjs library integration |

---

## Data Models

### Pool Storage Structure

```cairo
struct PoolStorage {
    // Token pair
    token0: ContractAddress,
    token1: ContractAddress,

    // Pool parameters
    fee: u128,                      // Fee in basis points (e.g., 3000 = 0.3%)
    tick_spacing: i32,              // Tick spacing (e.g., 60)

    // Current state
    sqrt_price_x96: u128,           // Current sqrt price (Q96 fixed-point)
    tick: i32,                      // Current tick
    liquidity: u128,                // Active liquidity (Q64.96)

    // Fee accumulators
    fee_growth_global0_x128: u256,  // Token0 fee growth (Q128)
    fee_growth_global1_x128: u256,  // Token1 fee growth (Q128)

    // Protocol fees
    protocol_fee0: u128,            // Token0 protocol fees accumulated
    protocol_fee1: u128,            // Token1 protocol fees accumulated
}
```

### Tick Information

```cairo
struct TickInfo {
    initialized: bool,                        // Whether tick is initialized
    liquidity_gross: u128,                    // Total liquidity referencing this tick
    liquidity_net: i128,                      // Liquidity added/removed when crossing
    fee_growth_outside0_x128: u256,           // Token0 fee growth outside this tick
    fee_growth_outside1_x128: u256,           // Token1 fee growth outside this tick
}
```

### Position Information

```cairo
struct PositionInfo {
    liquidity: u128,                          // Liquidity provided
    fee_growth_inside0_last_x128: u256,       // Last tracked fee growth (token0)
    fee_growth_inside1_last_x128: u256,       // Last tracked fee growth (token1)
    tokens_owed0: u128,                       // Uncollected fees (token0)
    tokens_owed1: u128,                       // Uncollected fees (token1)
}
```

### Merkle Tree Storage

```cairo
struct MerkleTreeStorage {
    root: felt252,                  // Current Merkle root
    next_index: u32,                // Next available leaf index
    depth: u8,                      // Tree depth (default: 20)
    leaves: Map<u32, felt252>,      // Leaf storage (sparse)
}
```

### Commitment Structure (Off-Chain)

```typescript
interface Commitment {
  secret: bigint;           // Random secret (private)
  nullifier: bigint;        // Unique nullifier (private)
  amount: bigint;           // Token amount (private)
  commitment: bigint;       // Hash(Hash(secret, nullifier), amount)
  leafIndex: number;        // Merkle tree index
}
```

### Fixed-Point Representations

| Type | Notation | Range | Usage |
|------|----------|-------|-------|
| **sqrt_price** | Q96 | [MIN_SQRT_RATIO, MAX_SQRT_RATIO] | Pool price representation |
| **liquidity** | Q64.96 | [0, 2^128) | Liquidity amounts |
| **fee_growth** | Q128 | [0, 2^256) | Fee accumulation tracking |
| **amounts** | u128 | [0, 2^128) | Token amounts |

---

## Integration Patterns

### Private Swap Flow

```
┌─────────┐                                    ┌──────────────┐
│  User   │                                    │   Contract   │
└────┬────┘                                    └──────┬───────┘
     │                                                │
     │  1. Request Merkle path                       │
     ├──────────────────────────────────────────────►│
     │            from ASP                            │  ASP
     │◄──────────────────────────────────────────────┤
     │  2. Path returned                              │
     │                                                │
     │  3. Generate ZK proof                          │
     │     (membership + swap correctness)            │
     │     [Off-chain: Circom + snarkjs]              │
     │                                                │
     │  4. Submit proof + public inputs               │
     ├──────────────────────────────────────────────►│
     │                                                │
     │                           5. Verify ZK proof   │
     │                              (Garaga verifier) │
     │                                                │
     │                        6. Validate membership  │
     │                           (Merkle root check)  │
     │                                                │
     │                     7. Execute CLMM swap       │
     │                        (update pool state)     │
     │                                                │
     │                  8. Insert output commitment   │
     │                     (update Merkle tree)       │
     │                                                │
     │  9. Emit SwapExecuted event                    │
     │◄──────────────────────────────────────────────┤
     │                                                │
     │  10. ASP indexes event                         │
     │      (updates tree replica)                    │
     │                                                │
```

### Private Deposit Flow

```
User → Contract: deposit(amount, commitment)
Contract → Privacy Layer: verify commitment format
Contract → CLMM: transfer tokens from user
Contract → Merkle Tree: insert commitment
Contract → Events: emit Deposit(commitment, index)
ASP → Events: index deposit event
ASP → Internal: update Merkle tree replica
```

### Private Withdrawal Flow

```
User → ASP: request Merkle path
ASP → User: return path
User → Off-chain: generate ZK proof (membership + nullifier)
User → Contract: private_withdraw(proof, nullifier, amount, recipient)
Contract → Verifier: verify proof
Contract → Nullifier Registry: check nullifier not spent
Contract → Nullifier Registry: mark nullifier spent
Contract → Token: transfer to recipient
Contract → Events: emit Withdrawal(nullifier_hash, amount_hash)
```

---

## Security Architecture

### Threat Model

| Threat Category | Attack Vector | Mitigation Strategy |
|----------------|---------------|---------------------|
| **Double-Spend** | Reuse commitment/nullifier | Nullifier registry with uniqueness check |
| **Invalid Proof** | Forged ZK proof | Groth16 verification via Garaga |
| **Front-Running** | MEV extraction on swaps | Commitments hide amounts, slippage limits |
| **Overflow/Underflow** | Arithmetic manipulation | u256 intermediate calculations, bounds checking |
| **Precision Loss** | Rounding errors | Exact integer arithmetic, consistent rounding |
| **Statistical Analysis** | Deanonymization via patterns | Large anonymity set, associated sets |
| **ASP Compromise** | Malicious path serving | Self-verifiable proofs, multiple ASP operators |
| **Reentrancy** | Recursive calls | Cairo's ownership model prevents reentrancy |

### Access Control Matrix

| Operation | Access Control | Validation |
|-----------|----------------|------------|
| **Initialize Pool** | Admin/Factory | One-time initialization check |
| **Deposit** | Any user | Token approval, valid commitment |
| **Private Swap** | Proof holder | ZK proof verification, Merkle membership |
| **Private Withdraw** | Proof holder | ZK proof verification, nullifier uniqueness |
| **Mint Position** | Commitment owner | ZK proof verification, tick range validation |
| **Burn Position** | Commitment owner | ZK proof verification, position existence |
| **Collect Fees** | Position owner | Position ownership verification |

### Cryptographic Guarantees

| Component | Algorithm | Security Level | Notes |
|-----------|-----------|----------------|-------|
| **Commitment** | Poseidon BN254 | 128-bit | Collision-resistant hash |
| **Merkle Tree** | Poseidon BN254 | 128-bit | 2^depth commitments supported |
| **ZK Proofs** | Groth16 | 128-bit | Succinct, constant-size proofs |
| **Nullifiers** | Poseidon BN254 | 128-bit | Unique per commitment |

---

## Performance Considerations

### Gas Cost Analysis

| Operation | Estimated Gas | Optimization Strategy |
|-----------|--------------|----------------------|
| **Simple Swap** | ~300K | Bitmap lookup, minimal storage access |
| **Multi-tick Swap** | ~500K-1M | Efficient tick crossing, bounded iterations |
| **Proof Verification** | ~1.5-2M | Garaga-optimized pairing checks |
| **Deposit** | ~200K | Single Merkle insertion |
| **Withdraw** | ~2.2M | Proof verification + nullifier check |
| **Mint Position** | ~2.5M | Proof verification + position creation |
| **Burn Position** | ~2.3M | Proof verification + fee collection |

### Storage Optimization

| Data Structure | Storage Pattern | Optimization |
|----------------|-----------------|--------------|
| **Tick Data** | Sparse mapping | Only store initialized ticks |
| **Bitmap** | Packed u256 | 256 ticks per storage slot |
| **Positions** | Keyed by commitment hash | O(1) lookup |
| **Merkle Leaves** | Sparse array | Only store actual commitments |
| **Nullifiers** | Set (Map<felt252, bool>) | Single storage slot per nullifier |

### Computational Complexity

| Operation | Time Complexity | Space Complexity |
|-----------|----------------|------------------|
| **Price Calculation** | O(1) | O(1) |
| **Tick Lookup** | O(1) average, O(n) worst | O(k) for k initialized ticks |
| **Merkle Proof** | O(log n) | O(log n) path elements |
| **Swap Execution** | O(k) for k crossed ticks | O(1) state updates |
| **Position Update** | O(1) | O(1) |

### Scalability Metrics

| Metric | Current Capacity | Future Scaling |
|--------|-----------------|----------------|
| **Max Commitments** | 2^20 (~1M) | Increase tree depth to 2^25 |
| **Concurrent Swaps** | Limited by block gas | Batch proofs for efficiency |
| **Pools Supported** | Unlimited | Independent pool storage |
| **Ticks per Pool** | 887,272 ticks | Bitmap spans full range |
| **ASP Throughput** | 1000+ deposits/day | Horizontal scaling |

---

## Deployment Architecture

### Network Configuration

| Environment | Network | Configuration |
|-------------|---------|---------------|
| **Development** | Local Devnet | Fast blocks, unlimited gas |
| **Testing** | Starknet Goerli | Public testnet, faucet available |
| **Staging** | Starknet Sepolia | Pre-production validation |
| **Production** | Starknet Mainnet | Full security, gas optimization |

### Contract Deployment Order

```
1. Deploy Math Library
2. Deploy Tick Management
3. Deploy Liquidity Engine
4. Deploy Pool State
5. Deploy Swap Engine
6. Deploy Position Manager
7. Deploy Merkle Tree
8. Deploy Commitment Handler
9. Deploy Verifier (Garaga)
10. Deploy Nullifier Registry
11. Deploy Integration Layer
12. Deploy Main Zylith Contract
13. Initialize Pool
14. Deploy ASP Server
```

### Infrastructure Requirements

| Component | Minimum Specs | Recommended Specs |
|-----------|--------------|-------------------|
| **ASP Server** | 2 CPU, 4GB RAM | 4 CPU, 8GB RAM |
| **Database** | PostgreSQL 14+ | PostgreSQL 15+ with replication |
| **RPC Provider** | Starknet RPC | Dedicated node or premium RPC |
| **Storage** | 50GB SSD | 200GB SSD |
| **Network** | 100 Mbps | 1 Gbps |

---

## Monitoring and Observability

### Key Metrics

| Category | Metrics | Alerting Threshold |
|----------|---------|-------------------|
| **Contract** | Gas usage, transaction success rate | >2M gas, <95% success |
| **ASP** | Sync lag, API response time, uptime | >10 blocks lag, >1s response, <99% uptime |
| **Privacy** | Proof verification rate, nullifier collisions | <90% valid proofs, any collision |
| **CLMM** | Pool liquidity, swap volume, price deviation | <$10K liquidity, price >5% deviation |

### Health Checks

```
GET /health                 # ASP health
GET /merkle/sync-status     # Merkle tree sync status
GET /metrics                # Prometheus metrics
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | December 2025 | Initial architecture documentation |

---

## References

- [Product Requirements Document](PRD.md)
- [System Requirements](REQUIREMENTS.md)
- [Tools and Technologies](TOOLS_AND_TECHNOLOGIES.md)
- [API Reference](API_REFERENCE.md)
- [Deployment Guide](zylith/docs/DEPLOYMENT.md)

---

**Maintained By**: Zylith Protocol Team
**Contact**: For architecture questions or clarifications, please open an issue or contact the development team.
