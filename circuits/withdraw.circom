// Private Withdraw Circuit for Zylith
// Proves ownership and allows withdrawal
// Aligned with zylith.cairo private_withdraw() expected public inputs

pragma circom 2.1.0;

include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/bitify.circom";
include "./lib/merkleTree.circom";

template Withdraw(depth) {
    // ============================================
    // PUBLIC INPUTS (order must match contract)
    // ============================================
    // [0]: nullifier - prevents double-spend
    signal input nullifier;
    // [1]: root - Merkle root for membership proof
    signal input root;
    // [2]: recipient - address receiving withdrawn funds
    signal input recipient;
    // [3]: amount - amount to withdraw
    signal input amount;
    
    // ============================================
    // PRIVATE INPUTS
    // ============================================
    signal input secret;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // ============================================
    // STEP 1: Compute commitment from private inputs
    // commitment = Mask(Hash(Mask(Hash(secret, nullifier)), amount))
    // ============================================
    component poseidon1 = Poseidon(2);
    poseidon1.inputs[0] <== secret;
    poseidon1.inputs[1] <== nullifier;

    component mask1 = Mask250();
    mask1.in <== poseidon1.out;
    
    component poseidon2 = Poseidon(2);
    poseidon2.inputs[0] <== mask1.out;
    poseidon2.inputs[1] <== amount;

    component mask2 = Mask250();
    mask2.in <== poseidon2.out;
    
    signal commitment;
    commitment <== mask2.out;
    
    // ============================================
    // STEP 2: Verify Merkle membership
    // ============================================
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== commitment;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
    
    // ============================================
    // STEP 3: Validate amount is positive
    // ============================================
    component n2b = Num2Bits(252);
    n2b.in <== amount;
    
    // Nullifier is revealed publicly to prevent double spending
    // The contract will check if nullifier has been spent
}

// Depth = 25 to match Cairo contract (TREE_DEPTH = 25)
// Public inputs in order: nullifier, root, recipient, amount
component main {public [nullifier, root, recipient, amount]} = Withdraw(25);
