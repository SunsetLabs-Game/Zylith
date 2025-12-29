use starknet::core::types::FieldElement;
use std::str::FromStr;
use num_bigint::BigUint;
use num_traits::Num;

/// Build calldata for ERC20 approve
pub fn build_approve_calldata(spender: &str, amount_low: u128, amount_high: u128) -> Result<Vec<FieldElement>, String> {
    // approve(spender: ContractAddress, amount: u256)
    // ContractAddress is a single felt252, NOT u256
    // Calldata: [spender (felt252), amount.low, amount.high]
    
    let spender_felt = parse_felt(spender)?;
    
    Ok(vec![
        spender_felt, // ContractAddress as single felt252
        FieldElement::from(amount_low),
        FieldElement::from(amount_high),
    ])
}

/// Build calldata for private_deposit
pub fn build_deposit_calldata(
    token: &str,
    amount_low: u128,
    amount_high: u128,
    commitment: &str,
) -> Result<Vec<FieldElement>, String> {
    // private_deposit(token: ContractAddress, amount: u256, commitment: felt252)
    // ContractAddress is a single felt252, NOT u256
    // Calldata: [token (felt252), amount.low, amount.high, commitment (felt252)]
    
    let token_felt = parse_felt(token)?;
    let commitment_felt = parse_felt(commitment)?;
    
    Ok(vec![
        token_felt, // ContractAddress as single felt252
        FieldElement::from(amount_low),
        FieldElement::from(amount_high),
        commitment_felt,
    ])
}

/// Build calldata for private_swap
pub fn build_swap_calldata(
    proof: &[String],
    public_inputs: &[String],
    zero_for_one: bool,
    amount_specified: u128,
    sqrt_price_limit_low: u128,
    sqrt_price_limit_high: u128,
    new_commitment: &str,
) -> Result<Vec<FieldElement>, String> {
    // private_swap(
    //   proof: Array<felt252>,
    //   public_inputs: Array<felt252>,
    //   zero_for_one: bool,
    //   amount_specified: u128,
    //   sqrt_price_limit_x128: u256,
    //   new_commitment: felt252
    // )
    
    let mut calldata = Vec::new();
    
    // Format proof array: [length, ...elements]
    calldata.push(FieldElement::from(proof.len() as u64));
    for p in proof {
        calldata.push(parse_felt(p)?);
    }
    
    // Format public_inputs array: [length, ...elements]
    calldata.push(FieldElement::from(public_inputs.len() as u64));
    for pi in public_inputs {
        calldata.push(parse_felt(pi)?);
    }
    
    // zero_for_one: bool -> 0 or 1
    calldata.push(if zero_for_one { FieldElement::ONE } else { FieldElement::ZERO });
    
    // amount_specified: u128
    calldata.push(FieldElement::from(amount_specified));
    
    // sqrt_price_limit_x128: u256 -> [low, high]
    calldata.push(FieldElement::from(sqrt_price_limit_low));
    calldata.push(FieldElement::from(sqrt_price_limit_high));
    
    // new_commitment: felt252
    calldata.push(parse_felt(new_commitment)?);
    
    Ok(calldata)
}

/// Build calldata for private_withdraw
pub fn build_withdraw_calldata(
    proof: &[String],
    public_inputs: &[String],
    token: &str,
    recipient: &str,
    amount: u128,
) -> Result<Vec<FieldElement>, String> {
    // private_withdraw(
    //   proof: Array<felt252>,
    //   public_inputs: Array<felt252>,
    //   token: ContractAddress,
    //   recipient: ContractAddress,
    //   amount: u128
    // )
    
    let mut calldata = Vec::new();
    
    // Format proof array
    calldata.push(FieldElement::from(proof.len() as u64));
    for p in proof {
        calldata.push(parse_felt(p)?);
    }
    
    // Format public_inputs array
    calldata.push(FieldElement::from(public_inputs.len() as u64));
    for pi in public_inputs {
        calldata.push(parse_felt(pi)?);
    }
    
    // token: ContractAddress -> single felt252
    let token_felt = parse_felt(token)?;
    calldata.push(token_felt);
    
    // recipient: ContractAddress -> single felt252
    let recipient_felt = parse_felt(recipient)?;
    calldata.push(recipient_felt);
    
    // amount: u128
    calldata.push(FieldElement::from(amount));
    
    Ok(calldata)
}

/// Build calldata for private_mint_liquidity
/// Returns Vec<String> with decimal strings (not hex) to avoid JSON serialization issues
pub fn build_mint_liquidity_calldata(
    proof: &[String],
    public_inputs: &[String],
    tick_lower: i32,
    tick_upper: i32,
    liquidity: u128,
    new_commitment: &str,
) -> Result<Vec<String>, String> {
    // private_mint_liquidity(
    //   proof: Array<felt252>,
    //   public_inputs: Array<felt252>,
    //   tick_lower: i32,
    //   tick_upper: i32,
    //   liquidity: u128,
    //   new_commitment: felt252
    // )
    
    println!("[Calldata] Building mint_liquidity calldata:");
    println!("[Calldata]   proof length: {}", proof.len());
    println!("[Calldata]   public_inputs length: {}", public_inputs.len());
    println!("[Calldata]   tick_lower: {} (i32)", tick_lower);
    println!("[Calldata]   tick_upper: {} (i32)", tick_upper);
    println!("[Calldata]   liquidity: {}", liquidity);
    println!("[Calldata]   new_commitment: {}", new_commitment);
    
    let mut calldata = Vec::new();
    
    // Format proof array - convert to decimal strings
    calldata.push(proof.len().to_string());
    for p in proof {
        // Parse and convert to decimal string
        let felt = parse_felt(p)?;
        let fe_str = format!("{:x}", felt); // Get hex without 0x prefix
        let big_uint = BigUint::from_str_radix(&fe_str, 16)
            .map_err(|e| format!("Failed to parse proof element '{}': {}", p, e))?;
        calldata.push(big_uint.to_str_radix(10)); // Convert to decimal string
    }
    
    // Format public_inputs array - convert to decimal strings
    calldata.push(public_inputs.len().to_string());
    for pi in public_inputs {
        // Parse and convert to decimal string
        let felt = parse_felt(pi)?;
        let fe_str = format!("{:x}", felt); // Get hex without 0x prefix
        let big_uint = BigUint::from_str_radix(&fe_str, 16)
            .map_err(|e| format!("Failed to parse public input '{}': {}", pi, e))?;
        calldata.push(big_uint.to_str_radix(10)); // Convert to decimal string
    }
    
    println!("[Calldata] After arrays: calldata length = {}", calldata.len());
    
    // tick_lower: i32 -> send as signed integer string
    // StarkNet.js will handle the conversion to felt252 internally
    // Don't pre-convert to felt252 - let the SDK do it
    let tick_lower_str = tick_lower.to_string(); // e.g., "-1000" or "1000"
    println!("[Calldata] tick_lower: {} (i32) -> {} (string) - StarkNet.js will convert to felt252", 
        tick_lower, tick_lower_str);
    calldata.push(tick_lower_str);
    
    // tick_upper: i32 -> send as signed integer string
    // StarkNet.js will handle the conversion to felt252 internally
    let tick_upper_str = tick_upper.to_string(); // e.g., "-1000" or "1000"
    println!("[Calldata] tick_upper: {} (i32) -> {} (string) - StarkNet.js will convert to felt252", 
        tick_upper, tick_upper_str);
    calldata.push(tick_upper_str);
    
    // liquidity: u128 -> decimal string
    calldata.push(liquidity.to_string());
    
    // new_commitment: felt252 -> decimal string
    let commitment_felt = parse_felt(new_commitment)?;
    let commitment_str = format!("{:x}", commitment_felt); // Get hex without 0x prefix
    let commitment_big = BigUint::from_str_radix(&commitment_str, 16)
        .map_err(|e| format!("Failed to parse commitment '{}': {}", new_commitment, e))?;
    calldata.push(commitment_big.to_str_radix(10)); // Convert to decimal string
    
    Ok(calldata)
}

/// Build calldata for private_burn_liquidity
pub fn build_burn_liquidity_calldata(
    proof: &[String],
    public_inputs: &[String],
    tick_lower: i32,
    tick_upper: i32,
    liquidity: u128,
    new_commitment: &str,
) -> Result<Vec<String>, String> {
    // Same signature as mint
    build_mint_liquidity_calldata(proof, public_inputs, tick_lower, tick_upper, liquidity, new_commitment)
}

/// Convert u256 amount to (low, high) tuple
pub fn u256_to_low_high(amount: u128) -> (u128, u128) {
    // For amounts that fit in u128, high is always 0
    (amount, 0)
}

// Note: ContractAddress in Cairo is a single felt252, NOT u256
// It should be passed directly as a FieldElement, not split into low/high

/// Convert i32 to felt252 (handles negative values)
/// In Cairo, i32 negative values use Cairo prime field arithmetic
/// Negative value -n is represented as: CAIRO_PRIME - n
/// CAIRO_PRIME = 2^251 + 17 * 2^192 + 1 = 0x800000000000011000000000000000000000000000000000000000000000001
fn i32_to_felt(value: i32) -> FieldElement {
    if value >= 0 {
        FieldElement::from(value as u64)
    } else {
        // For negative: use Cairo prime field arithmetic
        // Formula: CAIRO_PRIME - |value|
        // CAIRO_PRIME = 3618502788666131106986593281521497120414687020801267626233049500247285301248
        let cairo_prime_str = "3618502788666131106986593281521497120414687020801267626233049500247285301248";
        let cairo_prime = FieldElement::from_str(cairo_prime_str)
            .expect("Failed to parse CAIRO_PRIME constant");
        
        let abs_value = (-value) as u64;
        let abs_felt = FieldElement::from(abs_value);
        
        // CAIRO_PRIME - abs_value (field arithmetic)
        cairo_prime - abs_felt
    }
}

/// Build calldata for initialize
pub fn build_initialize_calldata(
    token0: &str,
    token1: &str,
    fee: u128,
    tick_spacing: i32,
    sqrt_price_low: u128,
    sqrt_price_high: u128,
) -> Result<Vec<FieldElement>, String> {
    // initialize(
    //     token0: ContractAddress,
    //     token1: ContractAddress,
    //     fee: u128,
    //     tick_spacing: i32,
    //     sqrt_price_x128: u256
    // )
    // Calldata: [token0 (felt252), token1 (felt252), fee (u128), tick_spacing (i32), sqrt_price.low, sqrt_price.high]
    
    let token0_felt = parse_felt(token0)?;
    let token1_felt = parse_felt(token1)?;
    
    // Convert i32 to u128 for FieldElement (i32 is signed, but we'll pass it as u128)
    // In Cairo, i32 is stored as a felt252, which can represent negative values
    // For simplicity, we'll pass it as u128 and let Cairo handle the conversion
    let tick_spacing_u128 = tick_spacing as u128;
    
    Ok(vec![
        token0_felt, // ContractAddress as single felt252
        token1_felt, // ContractAddress as single felt252
        FieldElement::from(fee),
        FieldElement::from(tick_spacing_u128), // i32 as felt252
        FieldElement::from(sqrt_price_low),
        FieldElement::from(sqrt_price_high),
    ])
}

/// Parse felt252 from hex string or decimal string
/// Handles values that may exceed felt252 by applying modulo arithmetic
fn parse_felt(value_str: &str) -> Result<FieldElement, String> {
    // STARKNET_FELT_MAX = 2^251 + 17 * 2^192 + 1
    // This value exceeds u128, so we use BigUint for calculations
    let felt_max_str = "3618502788666131106986593281521497120414687020801267626233049500247285301248";
    let felt_max_big = BigUint::from_str(felt_max_str)
        .map_err(|_| "Failed to parse FELT_MAX constant".to_string())?;
    
    // Parse value as BigUint (handles both hex and decimal)
    let value_big = if value_str.starts_with("0x") {
        // Parse hex string - remove "0x" prefix and parse as base 16
        num_bigint::BigUint::from_str_radix(&value_str[2..], 16)
            .map_err(|e| format!("Failed to parse hex value '{}': {}", value_str, e))?
    } else {
        // Parse decimal string
        BigUint::from_str(value_str)
            .map_err(|e| format!("Failed to parse decimal value '{}': {}", value_str, e))?
    };
    
    // Apply felt252 modulo if value exceeds limit
    let modulo_big = if value_big >= felt_max_big {
        &value_big % &felt_max_big
    } else {
        value_big.clone()
    };
    
    // Convert BigUint to string and parse as FieldElement
    // FieldElement can handle the full felt252 range directly
    let modulo_str = modulo_big.to_str_radix(10);
    FieldElement::from_str(&modulo_str)
        .map_err(|e| format!("Failed to convert to FieldElement: {}", e))
}

