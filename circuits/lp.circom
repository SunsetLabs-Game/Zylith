// Private Liquidity Provision Circuit for Zylith
// Proves valid balance for minting/burning LP positions
// Aligned with zylith.cairo private_mint/private_burn() expected public inputs

pragma circom 2.1.0;

include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/bitify.circom";
include "./lib/merkleTree.circom";

template LPOperation(depth) {
    // ============================================
    // PUBLIC INPUTS (order must match contract)
    // ============================================
    // [0]: nullifier - prevents double-spend of input note
    signal input nullifier;
    // [1]: root - Merkle root for membership proof
    signal input root;
    // [2]: tick_lower - lower tick of LP position
    signal input tick_lower;
    // [3]: tick_upper - upper tick of LP position
    signal input tick_upper;
    // [4]: liquidity - amount of liquidity to mint/burn
    signal input liquidity;
    // [5]: new_commitment - output note commitment (change)
    signal input new_commitment;
    // [6]: position_commitment - unique identifier for LP position
    signal input position_commitment;

    // ============================================
    // PRIVATE INPUTS
    // ============================================
    // Input note secrets
    signal input secret_in;
    signal input amount_in; // Total balance in input note
    // Output note secrets
    signal input secret_out;
    signal input nullifier_out;
    signal input amount_out; // Remaining balance after LP operation
    // Merkle proof for input commitment
    signal input pathElements[depth];
    signal input pathIndices[depth];
    
    // ============================================
    // STEP 1: Verify input commitment structure
    // commitment = Mask(Hash(Mask(Hash(secret, nullifier)), amount))
    // ============================================
    component poseidon1 = Poseidon(2);
    poseidon1.inputs[0] <== secret_in;
    poseidon1.inputs[1] <== nullifier;

    component mask1 = Mask250();
    mask1.in <== poseidon1.out;
    
    component poseidon2 = Poseidon(2);
    poseidon2.inputs[0] <== mask1.out;
    poseidon2.inputs[1] <== amount_in;

    component mask2 = Mask250();
    mask2.in <== poseidon2.out;
    signal commitment_in;
    commitment_in <== mask2.out;
    
    // ============================================
    // STEP 2: Verify Merkle membership of input note
    // ============================================
    component merkleTree = MerkleTreeChecker(depth);
    merkleTree.leaf <== commitment_in;
    merkleTree.root <== root;
    
    for (var i = 0; i < depth; i++) {
        merkleTree.pathElements[i] <== pathElements[i];
        merkleTree.pathIndices[i] <== pathIndices[i];
    }
    
    // ============================================
    // STEP 3: Verify tick range is valid
    // tick_lower < tick_upper
    // ============================================
    signal tick_diff;
    tick_diff <== tick_upper - tick_lower;
    
    component n2b_tick = Num2Bits(252);
    n2b_tick.in <== tick_diff;

    // ============================================
    // STEP 4: Verify balance sufficiency
    // For mint: need enough balance to provide liquidity
    // amount_in >= some_function(liquidity, tick_lower, tick_upper)
    // Simplified: just check amount_in >= liquidity for MVP
    // ============================================
    signal balance_check;
    balance_check <== amount_in - liquidity;
    
    component n2b_balance = Num2Bits(252);
    n2b_balance.in <== balance_check;
    
    // ============================================
    // STEP 5: Verify output commitment (change note)
    // ============================================
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
    
    // Output commitment must match public input
    mask4.out === new_commitment;

    // ============================================
    // STEP 6: Verify position commitment
    // position_commitment uniquely identifies this LP position
    // It's derived from secrets known only to the user
    // ============================================
    component poseidon5 = Poseidon(2);
    poseidon5.inputs[0] <== secret_in;
    poseidon5.inputs[1] <== tick_lower + tick_upper; // Include tick info

    component mask5 = Mask250();
    mask5.in <== poseidon5.out;
    
    // Position commitment must match public input
    mask5.out === position_commitment;

    // ============================================
    // STEP 7: Verify amount conservation
    // amount_out = amount_in - liquidity_cost
    // Simplified for MVP: amount_out = amount_in - liquidity
    // ============================================
    amount_out === amount_in - liquidity;
}

// Depth = 25 to match Cairo contract (TREE_DEPTH = 25)
// Public inputs in order: nullifier, root, tick_lower, tick_upper,
//                         liquidity, new_commitment, position_commitment
component main {public [
    nullifier,
    root,
    tick_lower,
    tick_upper,
    liquidity,
    new_commitment,
    position_commitment
]} = LPOperation(25);
