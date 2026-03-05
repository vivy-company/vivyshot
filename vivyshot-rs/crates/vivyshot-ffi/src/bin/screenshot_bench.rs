use std::process::Command;
use std::str;
use std::time::Instant;

use vivyshot_core::{
    vs_bgra_crop, vs_bgra_image_view, vs_bgra_owned_image, vs_bgra_owned_image_destroy,
    vs_encode_bgra_image, vs_encoded_bytes, vs_encoded_bytes_destroy,
};

fn main() {
    let sessions = parse_sessions();
    let warmup_sessions = parse_warmup_sessions();
    let baseline_rss_kb = current_rss_kb().unwrap_or(0);
    let source = make_source(2560, 1440);

    let started = Instant::now();
    let mut latencies_ms = Vec::with_capacity(sessions);
    let mut checksum = 0u64;

    for i in 0..warmup_sessions {
        checksum = checksum.wrapping_add(run_session(i, &source));
    }

    for i in 0..sessions {
        let session_index = warmup_sessions + i;
        let session_started = Instant::now();
        checksum = checksum.wrapping_add(run_session(session_index, &source));
        latencies_ms.push(session_started.elapsed().as_secs_f64() * 1000.0);
        if (i + 1) % 10 == 0 || i + 1 == sessions {
            println!("completed {}/{}", i + 1, sessions);
        }
    }

    let elapsed = started.elapsed();
    let avg_ms = average_ms(&latencies_ms);
    let median_ms = percentile_ms(&latencies_ms, 50.0);
    let p95_ms = percentile_ms(&latencies_ms, 95.0);
    let p99_ms = percentile_ms(&latencies_ms, 99.0);
    let peak_rss_kb = peak_rss_kb();

    println!("sessions={}", sessions);
    println!("warmup_sessions={}", warmup_sessions);
    println!("elapsed_ms={:.2}", elapsed.as_secs_f64() * 1000.0);
    println!("avg_ms_per_session={:.2}", avg_ms);
    println!("median_ms_per_session={:.2}", median_ms);
    println!("p95_ms_per_session={:.2}", p95_ms);
    println!("p99_ms_per_session={:.2}", p99_ms);
    println!("baseline_rss_kb={}", baseline_rss_kb);
    println!("peak_rss_kb={}", peak_rss_kb);
    println!("baseline_rss_mb={:.2}", baseline_rss_kb as f64 / 1024.0);
    println!("peak_rss_mb={:.2}", peak_rss_kb as f64 / 1024.0);
    println!("checksum={}", checksum);
}

#[derive(Clone)]
struct SourceImage {
    width: usize,
    height: usize,
    stride: usize,
    pixels: Vec<u8>,
}

fn parse_sessions() -> usize {
    std::env::args()
        .nth(1)
        .and_then(|v| v.parse::<usize>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(60)
}

fn parse_warmup_sessions() -> usize {
    std::env::var("VIVYSHOT_BENCH_WARMUP_SESSIONS")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(3)
}

fn run_session(index: usize, source: &SourceImage) -> u64 {
    let crop_width = 1920usize;
    let crop_height = 1080usize;
    let max_x = source.width.saturating_sub(crop_width);
    let max_y = source.height.saturating_sub(crop_height);
    let x = if max_x == 0 {
        0
    } else {
        (index.wrapping_mul(31)) % (max_x + 1)
    };
    let y = if max_y == 0 {
        0
    } else {
        (index.wrapping_mul(17)) % (max_y + 1)
    };

    let source_view = vs_bgra_image_view {
        width: source.width as u32,
        height: source.height as u32,
        stride: source.stride as u32,
        ptr: source.pixels.as_ptr(),
        len: source.pixels.len(),
    };

    let mut cropped = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    // SAFETY: source/crop pointers are valid for call duration.
    let crop_status = unsafe {
        vs_bgra_crop(
            source_view,
            x as u32,
            y as u32,
            crop_width as u32,
            crop_height as u32,
            &mut cropped,
        )
    };
    if crop_status != 0 || cropped.ptr.is_null() || cropped.len == 0 {
        unsafe { vs_bgra_owned_image_destroy(&mut cropped) };
        return 0;
    }

    let cropped_view = vs_bgra_image_view {
        width: cropped.width,
        height: cropped.height,
        stride: cropped.stride,
        ptr: cropped.ptr as *const u8,
        len: cropped.len,
    };

    let mut png = vs_encoded_bytes {
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut jpeg = vs_encoded_bytes {
        ptr: std::ptr::null_mut(),
        len: 0,
    };

    // SAFETY: pointers are valid and output structs are writable.
    let png_status = unsafe { vs_encode_bgra_image(cropped_view, 0, 100, &mut png) };
    let jpeg_status = unsafe { vs_encode_bgra_image(cropped_view, 1, 88, &mut jpeg) };

    let mut checksum = 0u64;
    if png_status == 0 && !png.ptr.is_null() && png.len > 0 {
        // SAFETY: output was allocated by Rust encoder and is valid for len bytes.
        let bytes = unsafe { std::slice::from_raw_parts(png.ptr, png.len) };
        checksum = checksum.wrapping_add(checksum_bytes(bytes));
    }
    if jpeg_status == 0 && !jpeg.ptr.is_null() && jpeg.len > 0 {
        // SAFETY: output was allocated by Rust encoder and is valid for len bytes.
        let bytes = unsafe { std::slice::from_raw_parts(jpeg.ptr, jpeg.len) };
        checksum = checksum.wrapping_add(checksum_bytes(bytes));
    }

    // SAFETY: destroy functions accept zeroed/null values and owned outputs.
    unsafe {
        vs_encoded_bytes_destroy(&mut png);
        vs_encoded_bytes_destroy(&mut jpeg);
        vs_bgra_owned_image_destroy(&mut cropped);
    }

    checksum
}

fn make_source(width: usize, height: usize) -> SourceImage {
    let stride = width * 4;
    let mut pixels = vec![0u8; stride * height];
    for y in 0..height {
        for x in 0..width {
            let idx = (y * width + x) * 4;
            pixels[idx] = ((x * 3 + y * 7) % 251) as u8;
            pixels[idx + 1] = ((x * 11 + y * 5 + 31) % 251) as u8;
            pixels[idx + 2] = ((x * 2 + y * 13 + 17) % 251) as u8;
            pixels[idx + 3] = 255;
        }
    }
    SourceImage {
        width,
        height,
        stride,
        pixels,
    }
}

fn checksum_bytes(bytes: &[u8]) -> u64 {
    if bytes.is_empty() {
        return 0;
    }
    let mut sum = 0u64;
    let step = (bytes.len() / 128).max(1);
    let mut i = 0usize;
    while i < bytes.len() {
        sum = sum.wrapping_mul(16777619).wrapping_add(bytes[i] as u64);
        i += step;
    }
    sum
}

fn percentile_ms(samples: &[f64], percentile: f64) -> f64 {
    if samples.is_empty() {
        return 0.0;
    }
    let mut sorted = samples.to_vec();
    sorted.sort_by(|a, b| a.total_cmp(b));
    let rank = ((percentile / 100.0) * (sorted.len().saturating_sub(1) as f64)).round() as usize;
    sorted[rank.min(sorted.len() - 1)]
}

fn average_ms(samples: &[f64]) -> f64 {
    if samples.is_empty() {
        return 0.0;
    }
    samples.iter().sum::<f64>() / samples.len() as f64
}

fn current_rss_kb() -> Option<u64> {
    let pid = std::process::id().to_string();
    let output = Command::new("ps")
        .args(["-o", "rss=", "-p", &pid])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = str::from_utf8(&output.stdout).ok()?;
    text.trim().parse::<u64>().ok()
}

fn peak_rss_kb() -> u64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    // SAFETY: rusage pointer is valid for initialization.
    let status = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) };
    if status != 0 {
        return 0;
    }
    // SAFETY: `getrusage` initialized `usage` on success.
    let usage = unsafe { usage.assume_init() };
    #[cfg(target_os = "macos")]
    {
        (usage.ru_maxrss as u64) / 1024
    }
    #[cfg(not(target_os = "macos"))]
    {
        usage.ru_maxrss as u64
    }
}
