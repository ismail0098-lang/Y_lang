use std::fs;
use std::path::Path;

extern "C" {
    fn probe_cpu_features(out_buffer: *mut u32);
    fn measure_l1_latency() -> u64;
}

pub struct HardwareProfile {
    pub has_avx: bool,
    pub has_avx512: bool,
    pub l2_line_size: u32,
    pub l1_latency_cycles: u64,
}

pub fn check_or_probe_hardware() -> HardwareProfile {
    let profile_path = ".ysu_hw_profile";
    
    if Path::new(profile_path).exists() {
        println!("[*] Found existing {}, skipping Sentinel Probe.", profile_path);
        // Deserializing the profile (mock logic for now)
        let contents = fs::read_to_string(profile_path).unwrap_or_default();
        let has_avx512 = contents.contains("AVX512=true");
        
        return HardwareProfile {
            has_avx: true,
            has_avx512,
            l2_line_size: 64,
            l1_latency_cycles: 4,
        };
    }

    println!("[*] First boot detected! Running Sentinel Hardware Probe...");

    let mut features = [0u32; 4];
    let l1_cycles;

    unsafe {
        // Call out to the raw NASM microbenchmark!
        probe_cpu_features(features.as_mut_ptr());
        l1_cycles = measure_l1_latency();
    }

    // features[0] = standard features (ECX)
    // features[1] = standard features (EDX)
    // features[2] = extended features (EBX)
    // features[3] = cache line size (ECX)

    let has_avx = (features[0] & (1 << 28)) != 0; // AVX bit
    let has_avx512 = (features[2] & (1 << 16)) != 0; // AVX512F bit
    let l2_line_size = features[3] & 0xFF; // Cache line size is usually low byte

    let profile = HardwareProfile {
        has_avx,
        has_avx512,
        l2_line_size,
        l1_latency_cycles: l1_cycles,
    };

    println!("    -> Detected AVX: {}", profile.has_avx);
    println!("    -> Detected AVX-512: {}", profile.has_avx512);
    println!("    -> L2 Cache Line Size: {} bytes", profile.l2_line_size);
    println!("    -> Baseline L1 Latency: {} cycles", profile.l1_latency_cycles);

    println!("[*] Saving hardware topology to {}...", profile_path);
    let serialized = format!("AVX={}\nAVX512={}\nL2_LINE={}\nL1_CYCLES={}\n", 
        profile.has_avx, profile.has_avx512, profile.l2_line_size, profile.l1_latency_cycles);
    fs::write(profile_path, serialized).expect("Failed to write profile");

    profile
}
