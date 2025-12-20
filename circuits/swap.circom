// Private Swap Circuit for Zylith
// Proves valid swap: commitment_in -> swap -> commitment_out

pragma circom 2.1.0;

include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/bitify.circom";
include "./lib/merkleTree.circom";

include "./lib/swapMath.circom";

template Swap(depth) {
    // Public inputs
    signal input root;
    signal input commitment_in;
    signal input commitment_out;
    signal input amount_in;
    signal input amount_out;
    signal input sqrt_p_old;
    signal input sqrt_p_new;
    signal input liquidity;
    signal input zero_for_one;
    
    // Private inputs
    signal input secret_in;
    signal input nullifier_in;
    signal input secret_out;
    signal input nullifier_out;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // ... [Masking logic remains same] ... (simplified for clarity in this diff)
    // Note: I will replace the whole component definition to be precise
    
    // [REPLACED WITH MASKED COMMITMENT LOGIC]
    component poseidon1 = Poseidon(2);
    poseidon1.inputs[0] <== secret_in;
    poseidon1.inputs[1] <== nullifier_in;
    component mask1 = Mask250();
    mask1.in <== poseidon1.out;
    component poseidon2 = Poseidon(2);
    poseidon2.inputs[0] <== mask1.out;
    poseidon2.inputs[1] <== amount_in;
    component mask2 = Mask250();
    mask2.in <== poseidon2.out;
    mask2.out === commitment_in;

    component poseidon3 = Poseidon(2);
    poseidon3.inputs[0] <== secret_out;
    poseidon3.inputs[1] <== nullifier_out;
    component mask3 = Mask250();
    mask3.in <== poseidon3.out;
    component poseidon4 = Poseidon(2);
    poseidon4.inputs[0] <== mask3.out;
    poseidon4.inputs[1] <== amount_out;
    component mask4 = Mask250();
    mask4.in <== poseidon4.out;
    mask4.out === commitment_out;

    // Verify Merkle membership of input commitment
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== commitment_in;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
    
    // NEW: Verify CLMM Price Transition
    component clmm = GetAmountOut();
    clmm.liquidity <== liquidity;
    clmm.sqrt_p_old <== sqrt_p_old;
    clmm.sqrt_p_new <== sqrt_p_new;
    clmm.zero_for_one <== zero_for_one;
    
    // amount_out must match the CLMM transition
    clmm.amount_out === amount_out;
}

component main {public [root, commitment_in, commitment_out, amount_in, amount_out, sqrt_p_old, sqrt_p_new, liquidity, zero_for_one]} = Swap(20);