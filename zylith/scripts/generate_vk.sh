#!/bin/bash
# Generate verification keys from compiled circuits

set -e

BUILD_DIR="circuits/build"
KEYS_DIR="circuits/keys"
PTAU_FILE="powersOfTau28_hez_final_16.ptau"

echo "Generating verification keys..."

# Check if snarkjs is installed
if ! command -v snarkjs &> /dev/null; then
    echo "Error: snarkjs is not installed"
    echo "Install with: npm install -g snarkjs"
    exit 1
fi

mkdir -p "$KEYS_DIR"

# Download powers of tau if not present
if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading powers of tau file..."
    wget -q "https://hermez.s3-eu-west-1.amazonaws.com/$PTAU_FILE" || {
        echo "Error: Failed to download powers of tau file"
        exit 1
    }
fi

# Generate keys for membership circuit
if [ -f "$BUILD_DIR/membership.r1cs" ]; then
    echo "Generating keys for membership circuit..."
    snarkjs groth16 setup "$BUILD_DIR/membership.r1cs" "$PTAU_FILE" "$KEYS_DIR/membership_0000.zkey"
    snarkjs zkey contribute "$KEYS_DIR/membership_0000.zkey" "$KEYS_DIR/membership_0001.zkey" \
        --name="First contribution" -v
    snarkjs zkey export verificationkey "$KEYS_DIR/membership_0001.zkey" "$KEYS_DIR/membership_verification_key.json"
    echo "✓ membership verification key generated"
fi

# Generate keys for swap circuit
if [ -f "$BUILD_DIR/swap.r1cs" ]; then
    echo "Generating keys for swap circuit..."
    snarkjs groth16 setup "$BUILD_DIR/swap.r1cs" "$PTAU_FILE" "$KEYS_DIR/swap_0000.zkey"
    snarkjs zkey contribute "$KEYS_DIR/swap_0000.zkey" "$KEYS_DIR/swap_0001.zkey" \
        --name="First contribution" -v
    snarkjs zkey export verificationkey "$KEYS_DIR/swap_0001.zkey" "$KEYS_DIR/swap_verification_key.json"
    echo "✓ swap verification key generated"
fi

echo "Verification key generation complete!"
echo "Keys are in: $KEYS_DIR"

