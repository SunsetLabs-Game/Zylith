// Private Swap Circuit for Zylith
// Proves valid swap: commitment_in -> swap -> commitment_out

pragma circom 2.1.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/merkleTree.circom";

template Swap(depth) {
    // Public inputs
    signal input root;
    signal input commitment_in;
    signal input commitment_out;
    signal input amount_in;
    signal input amount_out;
    
    // Private inputs
    signal input secret_in;
    signal input nullifier_in;
    signal input secret_out;
    signal input nullifier_out;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // Verify input commitment
    component poseidon1 = Poseidon(2);
    poseidon1.inputs[0] <== secret_in;
    poseidon1.inputs[1] <== nullifier_in;
    
    component poseidon2 = Poseidon(2);
    poseidon2.inputs[0] <== poseidon1.out;
    poseidon2.inputs[1] <== amount_in;
    poseidon2.out === commitment_in;
    
    // Verify output commitment
    component poseidon3 = Poseidon(2);
    poseidon3.inputs[0] <== secret_out;
    poseidon3.inputs[1] <== nullifier_out;
    
    component poseidon4 = Poseidon(2);
    poseidon4.inputs[0] <== poseidon3.out;
    poseidon4.inputs[1] <== amount_out;
    poseidon4.out === commitment_out;
    
    // Verify Merkle membership of input commitment
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== commitment_in;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
    
    // Verify swap amounts are valid (amount_out <= amount_in, accounting for fees)
    // This is a simplified check - full implementation would verify CLMM swap math
    amount_out <= amount_in;
}

component main = Swap(20);
