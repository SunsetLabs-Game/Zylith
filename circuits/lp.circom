// Private Liquidity Provision Circuit for Zylith
// Proves valid balance for minting/burning LP positions

pragma circom 2.1.0;

include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/bitify.circom";
include "./lib/merkleTree.circom";

template LPOperation(depth) {
    // Public inputs
    signal input root;
    signal input balance_commitment_in;
    signal input balance_commitment_out;
    signal input liquidity_amount; // Amount of tokens contributing/receiving
    
    // Private inputs
    signal input secret;
    signal input nullifier;
    signal input total_balance_in;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // Verify input balance commitment: Mask(Hash(Mask(Hash(secret, nullifier)), total_balance_in))
    component poseidon1 = Poseidon(2);
    poseidon1.inputs[0] <== secret;
    poseidon1.inputs[1] <== nullifier;

    component mask1 = Mask250();
    mask1.in <== poseidon1.out;
    
    component poseidon2 = Poseidon(2);
    poseidon2.inputs[0] <== mask1.out;
    poseidon2.inputs[1] <== total_balance_in;

    component mask2 = Mask250();
    mask2.in <== poseidon2.out;
    mask2.out === balance_commitment_in;
    
    // Verify Merkle membership of input balance
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== balance_commitment_in;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
    
    // Check balance sufficiency
    signal diff;
    diff <== total_balance_in - liquidity_amount;
    
    component n2b = Num2Bits(252);
    n2b.in <== diff; 
    
    // Output commitment for remaining balance
    component poseidon3 = Poseidon(2);
    poseidon3.inputs[0] <== secret; // User can reuse secret or use new one
    poseidon3.inputs[1] <== nullifier + 1; // Simple nullifier evolution for MVP

    component mask3 = Mask250();
    mask3.in <== poseidon3.out;
    
    component poseidon4 = Poseidon(2);
    poseidon4.inputs[0] <== mask3.out;
    poseidon4.inputs[1] <== diff;

    component mask4 = Mask250();
    mask4.in <== poseidon4.out;
    mask4.out === balance_commitment_out;
}

component main {public [root, balance_commitment_in, balance_commitment_out, liquidity_amount]} = LPOperation(20);
