#!/bin/bash
set -e

# 1. Ptau generation (Mock trusted setup for development)
echo "Generating Powers of Tau..."
./node_modules/.bin/snarkjs powersoftau new bn128 16 pot16_0000.ptau -v
./node_modules/.bin/snarkjs powersoftau contribute pot16_0000.ptau pot16_final.ptau --name="First contribution" -v -e="random text"
# We skip phase2 prepare for non-beacon setup in development, or just use the result directly
# Actually prepare phase2 is good practice:
./node_modules/.bin/snarkjs powersoftau prepare phase2 pot16_final.ptau pot16_prepared.ptau -v

# 2. Key Generation for each circuit
CIRCUITS=("membership" "withdraw" "lp" "swap")

for CIRCUIT in "${CIRCUITS[@]}"; do
    echo "Generating keys for $CIRCUIT..."
    
    # Setup
    ./node_modules/.bin/snarkjs groth16 setup out/$CIRCUIT.r1cs pot16_prepared.ptau out/${CIRCUIT}_0000.zkey
    
    # Contribute (dummy randomness)
    ./node_modules/.bin/snarkjs zkey contribute out/${CIRCUIT}_0000.zkey out/${CIRCUIT}_final.zkey --name="Relayer" -v -e="random entropy"
    
    # Export Verification Key
    ./node_modules/.bin/snarkjs zkey export verificationkey out/${CIRCUIT}_final.zkey out/${CIRCUIT}_vk.json
    
    echo "$CIRCUIT keys generated!"
done

echo "All keys generated successfully."
