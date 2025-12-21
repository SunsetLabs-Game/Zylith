// Private Withdraw Circuit for Zylith
// Proves ownership and allows withdrawal

pragma circom 2.1.0;

include "./node_modules/circomlib/circuits/poseidon.circom";
include "./lib/merkleTree.circom";

template Withdraw(depth) {
    // Public inputs
    signal input root;
    signal input commitment;
    signal input nullifier;
    signal input amount;
    signal input recipient; // Contract address
    
    // Private inputs
    signal input secret;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // Verify commitment: Mask(Hash(Mask(Hash(secret, nullifier)), amount))
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
    
    // Verify commitment matches
    mask2.out === commitment;
    
    // Verify Merkle membership
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== commitment;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
    
    // Nullifier is revealed to prevent double spending
    // The contract will check if nullifier has been spent
}

component main {public [root, commitment, nullifier, amount, recipient]} = Withdraw(20);

