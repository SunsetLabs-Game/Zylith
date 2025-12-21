/**
 * Zylith Proof Generation Module
 * Generates Groth16 proofs for all circuit types using snarkjs
 * 
 * Usage:
 *   node generate_proof.js <circuit> <input_file>
 *   
 * Examples:
 *   node generate_proof.js membership input_membership.json
 *   node generate_proof.js withdraw input_withdraw.json
 *   node generate_proof.js swap input_swap.json
 *   node generate_proof.js lp input_lp.json
 */

const snarkjs = require("snarkjs");
const fs = require("fs");
const path = require("path");

// Circuit configurations
const CIRCUITS = {
    membership: {
        wasm: "../out/membership_js/membership.wasm",
        zkey: "../out/membership_final.zkey",
        vkey: "../out/membership_vk.json"
    },
    withdraw: {
        wasm: "../out/withdraw_js/withdraw.wasm",
        zkey: "../out/withdraw_final.zkey",
        vkey: "../out/withdraw_vk.json"
    },
    swap: {
        wasm: "../out/swap_js/swap.wasm",
        zkey: "../out/swap_final.zkey",
        vkey: "../out/swap_vk.json"
    },
    lp: {
        wasm: "../out/lp_js/lp.wasm",
        zkey: "../out/lp_final.zkey",
        vkey: "../out/lp_vk.json"
    }
};

/**
 * Generate a Groth16 proof for the specified circuit
 * @param {string} circuitName - Name of the circuit (membership, withdraw, swap, lp)
 * @param {object} input - Circuit inputs as an object
 * @returns {object} { proof, publicSignals }
 */
async function generateProof(circuitName, input) {
    const circuit = CIRCUITS[circuitName];
    if (!circuit) {
        throw new Error(`Unknown circuit: ${circuitName}. Valid options: ${Object.keys(CIRCUITS).join(", ")}`);
    }

    const wasmPath = path.join(__dirname, circuit.wasm);
    const zkeyPath = path.join(__dirname, circuit.zkey);

    // Verify files exist
    if (!fs.existsSync(wasmPath)) {
        throw new Error(`WASM file not found: ${wasmPath}`);
    }
    if (!fs.existsSync(zkeyPath)) {
        throw new Error(`zkey file not found: ${zkeyPath}`);
    }

    console.log(`Generating ${circuitName} proof...`);
    console.log(`  WASM: ${wasmPath}`);
    console.log(`  zkey: ${zkeyPath}`);

    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        input,
        wasmPath,
        zkeyPath
    );

    return { proof, publicSignals };
}

/**
 * Verify a Groth16 proof
 * @param {string} circuitName - Name of the circuit
 * @param {object} proof - The proof object
 * @param {array} publicSignals - The public signals
 * @returns {boolean} True if proof is valid
 */
async function verifyProof(circuitName, proof, publicSignals) {
    const circuit = CIRCUITS[circuitName];
    if (!circuit) {
        throw new Error(`Unknown circuit: ${circuitName}`);
    }

    const vkeyPath = path.join(__dirname, circuit.vkey);
    if (!fs.existsSync(vkeyPath)) {
        throw new Error(`Verification key not found: ${vkeyPath}`);
    }

    const vkey = JSON.parse(fs.readFileSync(vkeyPath));
    return await snarkjs.groth16.verify(vkey, publicSignals, proof);
}

/**
 * Export proof in Garaga-compatible format for Cairo
 * @param {object} proof - The snarkjs proof
 * @param {array} publicSignals - The public signals
 * @returns {array} Proof as felt252 array for Cairo
 */
function exportForCairo(proof, publicSignals) {
    // Garaga expects proof in specific format
    // This is a simplified export - actual format depends on Garaga version
    const proofArray = [
        proof.pi_a[0],
        proof.pi_a[1],
        proof.pi_b[0][0],
        proof.pi_b[0][1],
        proof.pi_b[1][0],
        proof.pi_b[1][1],
        proof.pi_c[0],
        proof.pi_c[1],
        ...publicSignals
    ];
    return proofArray;
}

/**
 * Format proof for Garaga calldata
 * @param {object} proof - The snarkjs proof
 * @param {array} publicSignals - The public signals  
 * @returns {string} Calldata string for Cairo
 */
async function formatCalldataGroth16(proof, publicSignals) {
    const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
    return calldata;
}

// CLI interface
async function main() {
    const args = process.argv.slice(2);
    
    if (args.length < 2) {
        console.log("Usage: node generate_proof.js <circuit> <input_file>");
        console.log("Circuits: membership, withdraw, swap, lp");
        console.log("\nExample: node generate_proof.js membership input.json");
        process.exit(1);
    }

    const [circuitName, inputFile] = args;

    // Load input
    const inputPath = path.resolve(inputFile);
    if (!fs.existsSync(inputPath)) {
        console.error(`Input file not found: ${inputPath}`);
        process.exit(1);
    }

    const input = JSON.parse(fs.readFileSync(inputPath, "utf8"));
    console.log("Input:", JSON.stringify(input, null, 2));

    try {
        // Generate proof
        const { proof, publicSignals } = await generateProof(circuitName, input);
        
        console.log("\n=== Proof Generated ===");
        console.log("Public Signals:", publicSignals);
        
        // Verify locally
        const isValid = await verifyProof(circuitName, proof, publicSignals);
        console.log("Local Verification:", isValid ? "PASSED" : "FAILED");

        // Export results
        const outputDir = path.join(__dirname, "../proofs");
        if (!fs.existsSync(outputDir)) {
            fs.mkdirSync(outputDir, { recursive: true });
        }

        const timestamp = Date.now();
        const outputFile = path.join(outputDir, `${circuitName}_proof_${timestamp}.json`);
        
        fs.writeFileSync(outputFile, JSON.stringify({
            circuit: circuitName,
            proof,
            publicSignals,
            cairoCalldata: exportForCairo(proof, publicSignals),
            timestamp: new Date().toISOString()
        }, null, 2));

        console.log(`\nProof saved to: ${outputFile}`);

    } catch (error) {
        console.error("Error generating proof:", error.message);
        process.exit(1);
    }
}

// Export for programmatic use
module.exports = {
    generateProof,
    verifyProof,
    exportForCairo,
    formatCalldataGroth16,
    CIRCUITS
};

// Run CLI if executed directly
if (require.main === module) {
    main().catch(console.error);
}

