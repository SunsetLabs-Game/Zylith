#!/bin/bash
# Compile Circom circuits to R1CS and WASM

set -e

echo "Compiling Zylith circuits..."

cd circuits

# Compile membership circuit
echo "Compiling membership.circom..."
circom membership.circom --r1cs --wasm --sym

# Compile swap circuit
echo "Compiling swap.circom..."
circom swap.circom --r1cs --wasm --sym

# Compile withdraw circuit
echo "Compiling withdraw.circom..."
circom withdraw.circom --r1cs --wasm --sym

echo "All circuits compiled successfully!"
echo "Generated files:"
echo "  - membership.r1cs, membership.wasm"
echo "  - swap.r1cs, swap.wasm"
echo "  - withdraw.r1cs, withdraw.wasm"
