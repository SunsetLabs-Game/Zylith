/**
 * Generate Test Fixtures for Zylith Cairo Tests
 * 
 * This script generates proofs with known inputs that can be used
 * in Cairo tests. The outputs are formatted as Cairo constants.
 * 
 * Usage: node generate_test_fixtures.js
 */

const { generateProof, verifyProof, exportForCairo } = require("./generate_proof");
const { 
    generateCommitment, 
    buildMerkleTree, 
    getMerkleProof,
    generatePositionCommitment,
    initPoseidon
} = require("./utils");
const fs = require("fs");
const path = require("path");

// Test values (simple numbers for easy verification)
const TEST_SECRET_IN = 123n;
const TEST_NULLIFIER = 456n;
const TEST_AMOUNT = 1000000n; // 1M units

const TEST_SECRET_OUT = 789n;
const TEST_NULLIFIER_OUT = 101112n;
const TEST_AMOUNT_OUT = 500000n; // 500K units

const TEST_RECIPIENT = 0x1234567890abcdefn;

// Tree depth matching Cairo contract
const TREE_DEPTH = 25;

/**
 * Generate Membership proof fixture
 */
async function generateMembershipFixture() {
    console.log("\n=== Generating Membership Fixture ===");
    
    // Generate commitment
    const commitment = await generateCommitment(TEST_SECRET_IN, TEST_NULLIFIER, TEST_AMOUNT);
    console.log("Commitment:", commitment.toString());
    
    // Build tree with single leaf
    const { root, tree } = await buildMerkleTree([commitment], TREE_DEPTH);
    console.log("Root:", root.toString());
    
    // Get proof for leaf at index 0
    const { pathElements, pathIndices } = getMerkleProof(tree, 0, TREE_DEPTH);
    
    const input = {
        root: root.toString(),
        commitment: commitment.toString(),
        secret: TEST_SECRET_IN.toString(),
        nullifier: TEST_NULLIFIER.toString(),
        amount: TEST_AMOUNT.toString(),
        pathElements,
        pathIndices
    };
    
    console.log("Generating proof...");
    const { proof, publicSignals } = await generateProof("membership", input);
    
    const isValid = await verifyProof("membership", proof, publicSignals);
    console.log("Proof valid:", isValid);
    
    return {
        name: "membership",
        input,
        proof,
        publicSignals,
        cairoFormat: formatForCairo(proof, publicSignals)
    };
}

/**
 * Generate Withdraw proof fixture
 */
async function generateWithdrawFixture() {
    console.log("\n=== Generating Withdraw Fixture ===");
    
    // Generate commitment
    const commitment = await generateCommitment(TEST_SECRET_IN, TEST_NULLIFIER, TEST_AMOUNT);
    
    // Build tree with single leaf
    const { root, tree } = await buildMerkleTree([commitment], TREE_DEPTH);
    
    // Get proof for leaf at index 0
    const { pathElements, pathIndices } = getMerkleProof(tree, 0, TREE_DEPTH);
    
    const input = {
        nullifier: TEST_NULLIFIER.toString(),
        root: root.toString(),
        recipient: TEST_RECIPIENT.toString(),
        amount: TEST_AMOUNT.toString(),
        secret: TEST_SECRET_IN.toString(),
        pathElements,
        pathIndices
    };
    
    console.log("Generating proof...");
    const { proof, publicSignals } = await generateProof("withdraw", input);
    
    const isValid = await verifyProof("withdraw", proof, publicSignals);
    console.log("Proof valid:", isValid);
    
    return {
        name: "withdraw",
        input,
        proof,
        publicSignals,
        cairoFormat: formatForCairo(proof, publicSignals)
    };
}

/**
 * Generate LP proof fixture
 */
async function generateLPFixture() {
    console.log("\n=== Generating LP Fixture ===");
    
    // Generate input commitment
    const commitmentIn = await generateCommitment(TEST_SECRET_IN, TEST_NULLIFIER, TEST_AMOUNT);
    
    // Build tree with single leaf
    const { root, tree } = await buildMerkleTree([commitmentIn], TREE_DEPTH);
    
    // Get proof for leaf at index 0
    const { pathElements, pathIndices } = getMerkleProof(tree, 0, TREE_DEPTH);
    
    // LP parameters
    const tickLower = -600;
    const tickUpper = 600;
    const liquidity = 500000n; // Half of input amount
    const amountOut = TEST_AMOUNT - liquidity; // Change
    
    // Generate output commitment
    const commitmentOut = await generateCommitment(TEST_SECRET_OUT, TEST_NULLIFIER_OUT, amountOut);
    
    // Generate position commitment
    const positionCommitment = await generatePositionCommitment(TEST_SECRET_IN, tickLower, tickUpper);
    
    const input = {
        nullifier: TEST_NULLIFIER.toString(),
        root: root.toString(),
        tick_lower: tickLower.toString(),
        tick_upper: tickUpper.toString(),
        liquidity: liquidity.toString(),
        new_commitment: commitmentOut.toString(),
        position_commitment: positionCommitment.toString(),
        secret_in: TEST_SECRET_IN.toString(),
        amount_in: TEST_AMOUNT.toString(),
        secret_out: TEST_SECRET_OUT.toString(),
        nullifier_out: TEST_NULLIFIER_OUT.toString(),
        amount_out: amountOut.toString(),
        pathElements,
        pathIndices
    };
    
    console.log("Generating proof...");
    const { proof, publicSignals } = await generateProof("lp", input);
    
    const isValid = await verifyProof("lp", proof, publicSignals);
    console.log("Proof valid:", isValid);
    
    return {
        name: "lp",
        input,
        proof,
        publicSignals,
        cairoFormat: formatForCairo(proof, publicSignals)
    };
}

/**
 * Generate Swap proof fixture
 */
async function generateSwapFixture() {
    console.log("\n=== Generating Swap Fixture ===");
    
    // Generate input commitment
    const commitmentIn = await generateCommitment(TEST_SECRET_IN, TEST_NULLIFIER, TEST_AMOUNT);
    
    // Build tree with single leaf
    const { root, tree } = await buildMerkleTree([commitmentIn], TREE_DEPTH);
    
    // Get proof for leaf at index 0
    const { pathElements, pathIndices } = getMerkleProof(tree, 0, TREE_DEPTH);
    
    // Swap parameters (simplified for test)
    const amountSpecified = 100000n;
    const zeroForOne = 1; // Swapping token0 for token1
    const amount0Delta = amountSpecified;
    const amount1Delta = 99000n; // ~1% fee
    const sqrtPriceOld = BigInt("340282366920938463463374607431768211456"); // Q128
    const sqrtPriceNew = BigInt("340000000000000000000000000000000000000"); // Slightly less
    const newTick = -1;
    const liquidity = 1000000n;
    
    // Output amount after swap
    const amountOut = TEST_AMOUNT - amountSpecified + amount1Delta;
    
    // Generate output commitment
    const commitmentOut = await generateCommitment(TEST_SECRET_OUT, TEST_NULLIFIER_OUT, amountOut);
    
    const input = {
        nullifier: TEST_NULLIFIER.toString(),
        root: root.toString(),
        new_commitment: commitmentOut.toString(),
        amount_specified: amountSpecified.toString(),
        zero_for_one: zeroForOne.toString(),
        amount0_delta: amount0Delta.toString(),
        amount1_delta: amount1Delta.toString(),
        new_sqrt_price_x128: sqrtPriceNew.toString(),
        new_tick: newTick.toString(),
        secret_in: TEST_SECRET_IN.toString(),
        amount_in: TEST_AMOUNT.toString(),
        secret_out: TEST_SECRET_OUT.toString(),
        nullifier_out: TEST_NULLIFIER_OUT.toString(),
        amount_out: amountOut.toString(),
        pathElements,
        pathIndices,
        sqrt_price_old: sqrtPriceOld.toString(),
        liquidity: liquidity.toString()
    };
    
    console.log("Generating proof...");
    try {
        const { proof, publicSignals } = await generateProof("swap", input);
        
        const isValid = await verifyProof("swap", proof, publicSignals);
        console.log("Proof valid:", isValid);
        
        return {
            name: "swap",
            input,
            proof,
            publicSignals,
            cairoFormat: formatForCairo(proof, publicSignals)
        };
    } catch (error) {
        console.log("Swap proof generation failed (expected - CLMM math constraints):", error.message);
        return null;
    }
}

/**
 * Format proof for Cairo test constants
 */
function formatForCairo(proof, publicSignals) {
    const lines = [];
    
    lines.push("// Proof components (pi_a, pi_b, pi_c)");
    lines.push(`const PI_A_X: felt252 = ${proof.pi_a[0]};`);
    lines.push(`const PI_A_Y: felt252 = ${proof.pi_a[1]};`);
    lines.push(`const PI_B_X1: felt252 = ${proof.pi_b[0][0]};`);
    lines.push(`const PI_B_X2: felt252 = ${proof.pi_b[0][1]};`);
    lines.push(`const PI_B_Y1: felt252 = ${proof.pi_b[1][0]};`);
    lines.push(`const PI_B_Y2: felt252 = ${proof.pi_b[1][1]};`);
    lines.push(`const PI_C_X: felt252 = ${proof.pi_c[0]};`);
    lines.push(`const PI_C_Y: felt252 = ${proof.pi_c[1]};`);
    
    lines.push("\n// Public signals");
    publicSignals.forEach((sig, i) => {
        lines.push(`const PUBLIC_${i}: felt252 = ${sig};`);
    });
    
    return lines.join("\n");
}

/**
 * Generate Cairo test file with fixtures
 */
function generateCairoTestFile(fixtures) {
    const lines = [
        "// Auto-generated test fixtures for E2E proof verification",
        "// Generated by: circuits/scripts/generate_test_fixtures.js",
        `// Generated at: ${new Date().toISOString()}`,
        "",
        "use core::array::ArrayTrait;",
        "",
    ];
    
    for (const fixture of fixtures) {
        if (!fixture) continue;
        
        lines.push(`// ==================== ${fixture.name.toUpperCase()} FIXTURE ====================`);
        lines.push(fixture.cairoFormat);
        lines.push("");
    }
    
    lines.push("// Helper to build proof array");
    lines.push("fn get_test_proof() -> Array<felt252> {");
    lines.push("    let mut proof = ArrayTrait::new();");
    lines.push("    // Add proof components here");
    lines.push("    proof");
    lines.push("}");
    
    return lines.join("\n");
}

async function main() {
    console.log("=== Zylith Test Fixture Generator ===");
    console.log("Tree depth:", TREE_DEPTH);
    
    // Initialize Poseidon
    await initPoseidon();
    
    const fixtures = [];
    
    // Generate each fixture type
    try {
        fixtures.push(await generateMembershipFixture());
    } catch (e) {
        console.log("Membership fixture failed:", e.message);
    }
    
    try {
        fixtures.push(await generateWithdrawFixture());
    } catch (e) {
        console.log("Withdraw fixture failed:", e.message);
    }
    
    try {
        fixtures.push(await generateLPFixture());
    } catch (e) {
        console.log("LP fixture failed:", e.message);
    }
    
    try {
        fixtures.push(await generateSwapFixture());
    } catch (e) {
        console.log("Swap fixture failed:", e.message);
    }
    
    // Save fixtures
    const outputDir = path.join(__dirname, "../proofs");
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }
    
    // Save JSON fixtures
    const jsonOutput = path.join(outputDir, "test_fixtures.json");
    fs.writeFileSync(jsonOutput, JSON.stringify(fixtures.filter(f => f !== null), null, 2));
    console.log(`\nJSON fixtures saved to: ${jsonOutput}`);
    
    // Save Cairo fixtures
    const cairoOutput = path.join(outputDir, "test_fixtures.cairo");
    fs.writeFileSync(cairoOutput, generateCairoTestFile(fixtures));
    console.log(`Cairo fixtures saved to: ${cairoOutput}`);
    
    console.log("\n=== Fixture Generation Complete ===");
}

main().catch(console.error);

