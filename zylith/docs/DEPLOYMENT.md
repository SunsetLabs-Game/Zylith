# Zylith Deployment Guide

## Overview

This guide covers deploying Zylith to Starknet devnet and testnet (Sepolia).

## Prerequisites

1. **Scarb** - Cairo package manager
2. **Starknet Foundry** - snforge and sncast
3. **Funded Account** - Account with ETH for gas fees
4. **RPC Access** - For Sepolia, use a public or private RPC

## Quick Start (Devnet)

### 1. Start Local Devnet

```bash
# Install starknet-devnet
pip install starknet-devnet

# Start devnet
starknet-devnet --seed 0
```

### 2. Create Account

```bash
# Generate account
sncast account create --name devnet_account --add-profile devnet

# Deploy account
sncast account deploy --name devnet_account --fee-token eth
```

### 3. Deploy Contracts

```bash
cd zylith
./scripts/deploy.sh devnet
```

## Sepolia Testnet Deployment

### 1. Get Sepolia ETH

- Use the [Starknet Faucet](https://faucet.starknet.io/)
- Or bridge from Ethereum Sepolia

### 2. Configure Account

Create `accounts/sepolia.json`:

```json
{
    "version": 1,
    "accounts": {
        "sepolia_account": {
            "private_key": "0x...",
            "public_key": "0x...",
            "address": "0x...",
            "deployed": true
        }
    }
}
```

Or use sncast to import:

```bash
sncast account add \
    --name sepolia_account \
    --address 0x... \
    --private-key 0x... \
    --add-profile sepolia
```

### 3. Deploy

```bash
./scripts/deploy.sh sepolia
```

## Manual Deployment Steps

If the script fails, deploy manually:

### Step 1: Build

```bash
scarb build
```

### Step 2: Declare Contracts

```bash
# Declare Zylith
sncast --profile sepolia declare --contract-name Zylith

# Note the class_hash from output
```

### Step 3: Deploy Verifiers

For each verifier (membership, swap, withdraw, lp):

```bash
sncast --profile sepolia deploy \
    --class-hash 0x<verifier_class_hash>
```

### Step 4: Deploy Zylith

```bash
sncast --profile sepolia deploy \
    --class-hash 0x<zylith_class_hash> \
    --constructor-calldata \
        0x<owner_address> \
        0x<membership_verifier_address> \
        0x<swap_verifier_address> \
        0x<withdraw_verifier_address> \
        0x<lp_verifier_address>
```

## Post-Deployment

### 1. Verify Deployment

```bash
# Check contract is accessible
sncast --profile sepolia call \
    --contract-address 0x<zylith_address> \
    --function get_merkle_root
```

### 2. Initialize a Pool

```bash
sncast --profile sepolia invoke \
    --contract-address 0x<zylith_address> \
    --function initialize \
    --calldata \
        0x<token0_address> \
        0x<token1_address> \
        3000 \
        60 \
        340282366920938463463374607431768211456
```

### 3. Start ASP Server

```bash
cd ../asp
# Configure RPC URL in .env
echo "STARKNET_RPC=https://starknet-sepolia.public.blastapi.io/rpc/v0_8" > .env
echo "CONTRACT_ADDRESS=0x<zylith_address>" >> .env

cargo run --release
```

## Configuration Files

### snfoundry.toml

```toml
[sncast.sepolia]
url = "https://starknet-sepolia.public.blastapi.io/rpc/v0_8"
accounts-file = "./accounts/sepolia.json"
account = "sepolia_account"
wait-params = { timeout = 600, retry-interval = 10 }
block-explorer = "StarkScan"
show-explorer-links = true
```

## Deployment Output

The deploy script saves deployment info to `deployment_<profile>_<timestamp>.json`:

```json
{
    "profile": "sepolia",
    "timestamp": "2024-01-01T12:00:00+00:00",
    "contracts": {
        "zylith": {
            "class_hash": "0x...",
            "address": "0x..."
        },
        "membership_verifier": {
            "class_hash": "0x...",
            "address": "0x..."
        },
        ...
    }
}
```

## Troubleshooting

### "Contract not declared"

The class hash doesn't exist on-chain. Run declare first:

```bash
sncast declare --contract-name Zylith
```

### "Insufficient balance"

Fund your account with more ETH for gas fees.

### "Transaction reverted"

Check constructor arguments match expected types and order.

### "Account not deployed"

Deploy your account first:

```bash
sncast account deploy --name <account_name>
```

## Security Checklist

- [ ] Verifier contracts use production verification keys
- [ ] Owner address is a secure multisig or admin account
- [ ] Private keys are stored securely
- [ ] RPC endpoint is reliable and not rate-limited
- [ ] ASP server is properly secured

## Network Information

| Network | Chain ID | Block Explorer |
|---------|----------|----------------|
| Devnet | N/A | N/A |
| Sepolia | SN_SEPOLIA | [StarkScan](https://sepolia.starkscan.co) |
| Mainnet | SN_MAIN | [StarkScan](https://starkscan.co) |

## Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| Declare Zylith | ~5M |
| Deploy Verifier | ~1M |
| Deploy Zylith | ~2M |
| Initialize Pool | ~500K |
| Private Deposit | ~2M |
| Private Withdraw | ~3M |

