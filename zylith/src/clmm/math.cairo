// CLMM Math - u128 arithmetic for sqrt price and tick conversions
// Based on Ekubo/Uniswap v3 mathematical approach
// Uses Q64.96 fixed point format (64 bits integer, 96 bits fractional)

/// Q64.96 format constants
const Q96: u128 = 79228162514264337593543950336; // 2^96
const MIN_SQRT_RATIO: u128 = 4295128739; // sqrt(1.0001)^(-887272) * 2^96
const MAX_SQRT_RATIO: u128 = 79226673515401279992447579055; // Simplified max for u128
pub const MIN_TICK: i32 = -887272;
pub const MAX_TICK: i32 = 887272;

/// Get sqrt price at a given tick
/// Formula: sqrtPrice = 1.0001^(tick/2) * 2^96
/// Simplified implementation for MVP
pub fn get_sqrt_ratio_at_tick(tick: i32) -> u128 {
    assert(tick >= MIN_TICK && tick <= MAX_TICK, 'Tick out of bounds');
    
    let abs_tick = if tick < 0 { -tick } else { tick };
    
    // Base ratio for tick = 0
    let mut ratio: u128 = Q96;
    
    if abs_tick == 0 {
        return ratio;
    };
    
    // Simplified calculation for MVP
    // Full implementation would use binary exponentiation with lookup table
    // Convert i32 to u128 by using absolute value and handling sign separately
    let abs_tick_u128: u128 = abs_tick.try_into().unwrap();
    
    if tick > 0 {
        // Approximate: ratio increases with tick
        // Using simplified formula: ratio * (1 + tick/2000000)
        let increment = (ratio * abs_tick_u128) / 2000000;
        ratio = ratio + increment;
    } else {
        // Approximate: ratio decreases with tick
        let decrement = (ratio * abs_tick_u128) / 2000000;
        if decrement < ratio {
            ratio = ratio - decrement;
        } else {
            ratio = MIN_SQRT_RATIO;
        };
    };
    
    ratio
}

/// Get tick at a given sqrt price
/// Uses binary search to find the tick
pub fn get_tick_at_sqrt_ratio(sqrt_price_x96: u128) -> i32 {
    assert(sqrt_price_x96 >= MIN_SQRT_RATIO && sqrt_price_x96 < MAX_SQRT_RATIO, 'Sqrt price out of bounds');
    
    // Binary search for the tick
    let mut low = MIN_TICK;
    let mut high = MAX_TICK;
    
    while low < high {
        let mid = (low + high + 1) / 2;
        let sqrt_ratio_mid = get_sqrt_ratio_at_tick(mid);
        
        if sqrt_ratio_mid <= sqrt_price_x96 {
            low = mid;
        } else {
            high = mid - 1;
        };
    };
    
    low
}

/// Convert a tick to sqrt price (Q64.96 format)
pub fn tick_to_sqrt_price_x96(tick: i32) -> u128 {
    get_sqrt_ratio_at_tick(tick)
}

/// Convert a sqrt price (Q64.96 format) to a tick
pub fn sqrt_price_x96_to_tick(sqrt_price_x96: u128) -> i32 {
    get_tick_at_sqrt_ratio(sqrt_price_x96)
}

/// Multiply two u128 values maintaining Q64.96 format
/// Returns (a * b) / 2^96
pub fn mul_u128(a: u128, b: u128) -> u128 {
    // For Q64.96 format: result = (a * b) / 2^96
    let product = a * b;
    product / Q96
}

/// Divide two u128 values maintaining Q64.96 format
/// Returns (a * 2^96) / b
pub fn div_u128(a: u128, b: u128) -> u128 {
    assert(b != 0, 'Division by zero');
    // For Q64.96 format: result = (a * 2^96) / b
    let numerator = a * Q96;
    numerator / b
}

/// Multiply two Q64.96 values
pub fn mul_ratio(a: u128, b: u128) -> u128 {
    mul_u128(a, b)
}

/// Divide two Q64.96 values
pub fn div_ratio(a: u128, b: u128) -> u128 {
    div_u128(a, b)
}
