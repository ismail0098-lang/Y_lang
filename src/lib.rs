use std::collections::HashMap;

// Y Language Type System
// Phase 1: Memory Layout Types

/// Number of shared memory banks on Ada Lovelace (RTX 4070)
const SMEM_BANKS: u32 = 32;
/// Bank width in bytes
const BANK_WIDTH_BYTES: u32 = 4;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Swizzle {
    pub xor_bits: u32,     // how many bits to XOR
    pub base_shift: u32,   // base shift amount  
    pub offset: u32,       // offset bits
}

impl Swizzle {
    pub const fn new(xor_bits: u32, base_shift: u32, offset: u32) -> Self {
        Self { xor_bits, base_shift, offset }
    }

    /// The standard conflict-free swizzle for Ada Lovelace f16 GEMM
    pub const CUTLASS_F16: Self = Self::new(3, 3, 3);
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Dtype {
    F16,
    BF16,
    TF32,
    F32,
}

impl Dtype {
    pub const fn size_bytes(self) -> u32 {
        match self {
            Dtype::F16  => 2,
            Dtype::BF16 => 2,
            Dtype::TF32 => 4,
            Dtype::F32  => 4,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct SmemLayout {
    pub dtype:   Dtype,
    pub rows:    u32,
    pub cols:    u32,
    pub swizzle: Swizzle,
}

impl SmemLayout {
    pub const fn new(dtype: Dtype, rows: u32, cols: u32, swizzle: Swizzle) -> Self {
        Self { dtype, rows, cols, swizzle }
    }

    pub const fn swizzled_col(&self, row: u32, col: u32) -> u32 {
        let row_bits = row & ((1 << self.swizzle.xor_bits) - 1);
        col ^ (row_bits << self.swizzle.offset)
    }

    pub const fn bank(&self, row: u32, col: u32) -> u32 {
        let swizzled = self.swizzled_col(row, col);
        let linear_idx = row * self.cols + swizzled;
        let byte_addr = linear_idx * self.dtype.size_bytes();
        (byte_addr >> 2) & (SMEM_BANKS - 1)
    }
}

pub fn verify_conflict_free(layout: &SmemLayout) -> Result<(), String> {
    let elements_per_bank = BANK_WIDTH_BYTES / layout.dtype.size_bytes();
    
    for row in 0..layout.rows {
        let mut banks_used = HashMap::new();
        for col in (0..layout.cols).step_by(elements_per_bank as usize) {
            let bank = layout.bank(row, col);
            if let Some(prev_col) = banks_used.insert(bank, col) {
                return Err(format!(
                    "Bank conflict at row {}: col {} and col {} both map to bank {}",
                    row, prev_col, col, bank
                ));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_swizzle_conflict_free() {
        let layout = SmemLayout::new(
            Dtype::F16,
            16,
            64,
            Swizzle::CUTLASS_F16,
        );
        assert!(verify_conflict_free(&layout).is_ok());
    }

    #[test]
    fn test_no_swizzle_has_conflicts() {
        // FIX: Increased cols to 128 to force bank wrap-around (32 banks * 2 elements/bank = 64 elements per wrap)
        let layout = SmemLayout::new(
            Dtype::F16,
            16,
            128, 
            Swizzle::new(0, 0, 0),
        );

        assert!(verify_conflict_free(&layout).is_err());
    }

    #[test]
    fn debug_no_swizzle() {
        let layout = SmemLayout::new(Dtype::F16, 8, 8, Swizzle::new(0,0,0));
        println!("\n--- Bank Mapping Trace ---");
        for row in 0..4u32 {
            print!("row {}: ", row);
            for col in (0..8u32).step_by(2) {
                print!("col{}→bank{} ", col, layout.bank(row, col));
            }
            println!();
        }
    }
}