# Zylith - Shielded CLMM for Starknet

Zylith is a shielded Concentrated Liquidity Market Maker (CLMM) built on Starknet. It combines Ekubo-style CLMM mechanics with zero-knowledge privacy features using Groth16 proofs verified via Garaga.

## Features

### CLMM Engine
- **Full Ekubo-style CLMM**: Complete swap engine with tick crossing
- **128.128 Fixed-Point Math**: High-precision sqrt price calculations
- **Tick Bitmap**: Efficient tick navigation using bitmap lookup
- **Liquidity Management**: Mint, burn positions across tick ranges
- **Fee Accounting**: Per-tick fee growth tracking and collection
- **Protocol Fees**: Configurable withdrawal fees

### Privacy Layer
- **Shielded Notes**: Commitments using `Hash(Hash(secret, nullifier), amount)`
- **Merkle Tree**: Depth-25 tree for membership proofs (~16M capacity)
- **Historical Root Tracking**: Proofs valid against any past root
- **Nullifier Registry**: Prevents double-spending
- **Private Operations**: Deposit, withdraw, swap, mint, burn - all with ZK proofs

### ZK Verification
- **Groth16 Proofs**: Generated with snarkjs/Circom
- **Garaga Verifiers**: On-chain proof verification
- **Four Circuit Types**: Membership, swap, withdraw, LP operations

## Quick Start

### Prerequisites

```bash
# Install Scarb
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
```

### Build and Test

```bash
cd zylith
scarb build
snforge test
```

### Deploy

```bash
# Deploy to devnet
./scripts/deploy.sh devnet

# Deploy to Sepolia
./scripts/deploy.sh sepolia
```

## Architecture

```
zylith/
├── src/
│   ├── clmm/              # CLMM engine
│   │   ├── math.cairo     # 128.128 fixed-point arithmetic
│   │   ├── tick.cairo     # Bitmap and tick management
│   │   ├── liquidity.cairo
│   │   ├── pool.cairo
│   │   └── position.cairo
│   ├── privacy/           # ZK privacy layer
│   │   ├── merkle_tree.cairo
│   │   ├── commitment.cairo
│   │   ├── verifier.cairo
│   │   └── verifiers/     # Garaga-generated verifiers
│   │       ├── membership/
│   │       ├── swap/
│   │       ├── withdraw/
│   │       └── lp/
│   ├── interfaces/        # Contract interfaces
│   │   ├── izylith.cairo
│   │   ├── ierc20.cairo
│   │   └── iprivacy.cairo
│   ├── mocks/             # Test mocks
│   │   └── erc20.cairo    # MockERC20 for testing
│   └── zylith.cairo       # Main contract
├── tests/
│   ├── test_privacy.cairo
│   ├── test_integration.cairo
│   └── test_e2e_proofs.cairo
├── scripts/
│   └── deploy.sh
└── docs/
    ├── USAGE.md
    └── DEPLOYMENT.md
```

## Documentation

- **[Usage Guide](docs/USAGE.md)** - How to use Zylith (deposits, swaps, proofs)
- **[Deployment Guide](docs/DEPLOYMENT.md)** - How to deploy to devnet/testnet

## Circuits

Located in `../circuits/`:

| Circuit | Purpose | Public Inputs |
|---------|---------|---------------|
| membership | Merkle membership proof | root, commitment |
| withdraw | Private withdrawal | nullifier, root, recipient, amount |
| swap | Private swap | nullifier, root, new_commitment, amounts, price, tick |
| lp | Private LP operations | nullifier, root, ticks, liquidity, commitments |

### Generate Proofs

   ```bash
   cd circuits
   npm install
node scripts/generate_proof.js membership input.json
```

## ASP (Association Set Provider)

Located in `../asp/`:

The ASP server maintains off-chain Merkle trees by syncing deposit events:

```bash
cd asp
cargo run --release
```

API:
- `GET /deposit/proof/:index` - Get Merkle proof
- `GET /deposit/root` - Get current root
- `GET /health` - Health check

## Testing

```bash
# Run all tests
snforge test

# Run specific tests
snforge test test_integration
snforge test test_e2e_proofs

# Verbose output
snforge test -v
```

## Development Status

### ✅ Completed

- [x] CLMM Math and Tick Management
- [x] Swap Engine with Tick Crossing
- [x] Liquidity Management
- [x] Fee Accounting
- [x] Merkle Tree (depth 25)
- [x] Historical Root Tracking
- [x] Nullifier Registry
- [x] Private Deposit/Withdraw
- [x] Private Swap with Binding
- [x] Private LP Operations
- [x] ERC20 Integration
- [x] MockERC20 for Testing
- [x] Deployment Scripts
- [x] Documentation

### Circuit Alignment

- [x] Circuits updated to depth=25
- [x] Public inputs aligned with contract
- [x] VKs regenerated with Garaga

## Security Considerations

- **Poseidon BN254**: Compatible with Circom circuits
- **Nullifier Uniqueness**: Each note can only be spent once
- **Historical Roots**: Proofs remain valid against past roots
- **Proof Binding**: Swap proofs bound to on-chain state transitions
- **Position Keys**: LP positions keyed by commitment hash

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Submit a pull request

## License

MIT

## Acknowledgments

- Inspired by Uniswap V3 and Ekubo CLMM
- Uses Garaga for Groth16 verification
- Privacy model based on Privacy Pools
- Built on Starknet
