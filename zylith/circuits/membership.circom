// Merkle Membership Circuit for Zylith
// Proves knowledge of a commitment in the Merkle tree

pragma circom 2.1.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/merkleTree.circom";

template Membership(depth) {
    // Public inputs
    signal input root;
    signal input commitment;
    
    // Private inputs
    signal input secret;
    signal input nullifier;
    signal input amount;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // Verify commitment generation: Hash(Hash(secret, nullifier), amount)
    component poseidon1 = Poseidon(2);
    poseidon1.inputs[0] <== secret;
    poseidon1.inputs[1] <== nullifier;
    
    component poseidon2 = Poseidon(2);
    poseidon2.inputs[0] <== poseidon1.out;
    poseidon2.inputs[1] <== amount;
    
    // Verify commitment matches
    poseidon2.out === commitment;
    
    // Verify Merkle membership
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== commitment;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
}

component main = Membership(20);
