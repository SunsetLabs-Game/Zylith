use ark_bn254::Fr;
use ark_ff::{BigInteger, PrimeField};
use light_poseidon::{Poseidon, PoseidonHasher};
use num_bigint::BigUint;
use num_traits::Num;
use std::str::FromStr;
use serde_json;

/// Mask used in Cairo contract to ensure BN254 hash fits in felt252
/// 0x3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff (250 bits)
const MASK: &str = "3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

/// Generate a commitment from secret, nullifier, and amount
/// Replicates the logic from zylith/src/privacy/commitment.cairo
/// Formula: Poseidon(Poseidon(secret, nullifier), amount)
pub fn generate_commitment(secret: &str, nullifier: &str, amount: u128) -> Result<String, String> {
    let mask = BigUint::from_str_radix(MASK, 16)
        .map_err(|_| "Failed to parse mask".to_string())?;

    // Parse inputs to Fr
    let secret_fr = parse_felt_to_fr(secret)?;
    let nullifier_fr = parse_felt_to_fr(nullifier)?;
    let amount_fr = Fr::from(amount);

    // First hash: Poseidon(secret, nullifier)
    let mut poseidon1 = Poseidon::<Fr>::new_circom(2)
        .map_err(|e| format!("Failed to create Poseidon hasher: {:?}", e))?;
    let intermediate = poseidon1.hash(&[secret_fr, nullifier_fr])
        .map_err(|e| format!("Failed to hash: {:?}", e))?;

    // Second hash: Poseidon(intermediate, amount)
    let mut poseidon2 = Poseidon::<Fr>::new_circom(2)
        .map_err(|e| format!("Failed to create Poseidon hasher: {:?}", e))?;
    let result = poseidon2.hash(&[intermediate, amount_fr])
        .map_err(|e| format!("Failed to hash: {:?}", e))?;

    // Convert to BigUint and apply mask (matches Cairo contract)
    let result_big = biguint_from_fr(&result);
    let safe_val = result_big & mask;

    // Convert to hex string
    Ok(format!("0x{:x}", safe_val))
}

/// Generate random secret and nullifier
pub fn generate_note() -> (String, String) {
    use rand::Rng;
    
    let mut rng = rand::thread_rng();
    
    // Generate 32 random bytes for secret
    let secret_bytes: Vec<u8> = (0..32).map(|_| rng.gen()).collect();
    let secret = format!("0x{}", hex::encode(secret_bytes));
    
    // Generate 32 random bytes for nullifier
    let nullifier_bytes: Vec<u8> = (0..32).map(|_| rng.gen()).collect();
    let nullifier = format!("0x{}", hex::encode(nullifier_bytes));
    
    (secret, nullifier)
}

/// Parse felt252 from hex string to Fr
fn parse_felt_to_fr(hex_str: &str) -> Result<Fr, String> {
    let cleaned = hex_str.trim_start_matches("0x");
    let big = BigUint::from_str_radix(cleaned, 16)
        .map_err(|e| format!("Failed to parse felt252: {}", e))?;
    
    // Convert BigUint to Fr using from_be_bytes_mod_order
    let bytes = big.to_bytes_be();
    let mut buf = [0u8; 32];
    let len = bytes.len().min(32);
    buf[32 - len..].copy_from_slice(&bytes[bytes.len().saturating_sub(len)..]);
    
    Ok(Fr::from_be_bytes_mod_order(&buf))
}

/// Convert Fr to BigUint
fn biguint_from_fr(fr: &Fr) -> BigUint {
    let bytes = fr.into_bigint().to_bytes_be();
    BigUint::from_bytes_be(&bytes)
}

/// Convert i32 to Fr (BN254 field element)
/// Negative values are represented as PRIME - |value| in the field
/// This matches how Circom interprets negative numbers in inputs
fn i32_to_fr_field(value: i32) -> Result<Fr, String> {
    if value >= 0 {
        Ok(Fr::from(value as u64))
    } else {
        // For negative: represent as PRIME - |value| in the field
        // BN254 prime: p = 21888242871839275222246405745257275088548364400416034343698204186575808495617
        let prime_str = "21888242871839275222246405745257275088548364400416034343698204186575808495617";
        let prime_big = BigUint::from_str(prime_str)
            .map_err(|_| "Failed to parse BN254 prime".to_string())?;
        let abs_value = (-value) as u64;
        let abs_big = BigUint::from(abs_value);
        let result_big = &prime_big - &abs_big;
        
        // Convert BigUint to Fr using from_be_bytes_mod_order
        let bytes = result_big.to_bytes_be();
        let mut buf = [0u8; 32];
        let len = bytes.len().min(32);
        buf[32 - len..].copy_from_slice(&bytes[bytes.len().saturating_sub(len)..]);
        Ok(Fr::from_be_bytes_mod_order(&buf))
    }
}

/// Generate position commitment for LP operations using Node.js script
/// This ensures we use the exact same logic as the circuit/test fixture
/// Formula: Mask(Poseidon(secret, tick_lower + tick_upper))
pub fn generate_position_commitment(secret: &str, tick_lower: i32, tick_upper: i32) -> Result<String, String> {
    use std::process::Command;
    use std::path::Path;
    
    // Get script path (relative to project root)
    let project_root = Path::new(env!("CARGO_MANIFEST_DIR")).parent()
        .ok_or("Failed to get project root")?;
    let script_path = project_root.join("scripts").join("calculate_position_commitment.js");
    let circuits_dir = project_root.join("circuits");
    
    if !script_path.exists() {
        // Fallback to Rust implementation if script doesn't exist
        println!("[ASP] ⚠️  Script not found: {}, using Rust fallback", script_path.display());
        return generate_position_commitment_rust(secret, tick_lower, tick_upper);
    }
    
    // Call Node.js script to calculate position commitment
    // Run from circuits directory to resolve node_modules
    println!("[ASP] 🔍 Calling Node.js script for position commitment:");
    println!("[ASP]    Script: {}", script_path.display());
    println!("[ASP]    Working dir: {}", circuits_dir.display());
    println!("[ASP]    Secret: {}", secret);
    println!("[ASP]    Tick lower: {}, Tick upper: {}", tick_lower, tick_upper);
    
    let output = Command::new("node")
        .arg(&script_path)
        .arg(secret)
        .arg(tick_lower.to_string())
        .arg(tick_upper.to_string())
        .current_dir(&circuits_dir) // Run from circuits directory to resolve node_modules
        .output()
        .map_err(|e| format!("Failed to run position commitment script: {}", e))?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        println!("[ASP] ⚠️  Node.js script failed, falling back to Rust implementation");
        println!("[ASP]    STDERR: {}", stderr);
        println!("[ASP]    STDOUT: {}", stdout);
        return generate_position_commitment_rust(secret, tick_lower, tick_upper);
    }
    
    // Parse JSON output from script (last line only, ignore debug output)
    let stdout = String::from_utf8_lossy(&output.stdout);
    let lines: Vec<&str> = stdout.lines().collect();
    let json_line = lines.last()
        .ok_or("No output from script")?;
    
    println!("[ASP] 🔍 Script output (last line): {}", json_line);
    
    let result: serde_json::Value = serde_json::from_str(json_line.trim())
        .map_err(|e| format!("Failed to parse script output: {}. Output: {}", e, json_line))?;
    
    let position_commitment = result["position_commitment"]
        .as_str()
        .ok_or("Missing position_commitment in script output")?;
    
    println!("[ASP] ✅ Position commitment from Node.js: {}", position_commitment);
    
    Ok(position_commitment.to_string())
}

/// Rust implementation of position commitment (fallback)
fn generate_position_commitment_rust(secret: &str, tick_lower: i32, tick_upper: i32) -> Result<String, String> {
    let mask = BigUint::from_str_radix(MASK, 16)
        .map_err(|_| "Failed to parse mask".to_string())?;

    // Parse secret to Fr
    let secret_fr = parse_felt_to_fr(secret)?;
    
    // Calculate tick_sum = tick_lower + tick_upper (as i32, can be negative)
    // This matches JavaScript: BigInt(tickLower) + BigInt(tickUpper)
    // Then convert the result to field representation
    let tick_sum_i32 = tick_lower + tick_upper;
    let tick_sum_fr = i32_to_fr_field(tick_sum_i32)?;
    
    // Debug: log the values
    println!("[ASP] 🔍 Position commitment debug (Rust fallback):");
    println!("[ASP]    tick_lower: {}, tick_upper: {}", tick_lower, tick_upper);
    println!("[ASP]    tick_sum_i32: {}", tick_sum_i32);
    let tick_sum_big = biguint_from_fr(&tick_sum_fr);
    println!("[ASP]    tick_sum_fr (as BigUint): {}", tick_sum_big);

    // Hash: Poseidon(secret, tick_sum)
    let mut poseidon = Poseidon::<Fr>::new_circom(2)
        .map_err(|e| format!("Failed to create Poseidon hasher: {:?}", e))?;
    let result = poseidon.hash(&[secret_fr, tick_sum_fr])
        .map_err(|e| format!("Failed to hash: {:?}", e))?;

    // Convert to BigUint and apply mask (matches Cairo contract)
    let result_big = biguint_from_fr(&result);
    let safe_val = result_big & mask;

    // Convert to hex string
    Ok(format!("0x{:x}", safe_val))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_commitment() {
        let secret = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        let nullifier = "0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321";
        let amount = 1000000000000000000u128; // 1 token with 18 decimals
        
        let commitment = generate_commitment(secret, nullifier, amount).unwrap();
        assert!(commitment.starts_with("0x"));
        assert_eq!(commitment.len(), 66); // 0x + 64 hex chars
    }

    #[test]
    fn test_generate_note() {
        let (secret, nullifier) = generate_note();
        assert!(secret.starts_with("0x"));
        assert!(nullifier.starts_with("0x"));
        assert_eq!(secret.len(), 66);
        assert_eq!(nullifier.len(), 66);
    }
}

