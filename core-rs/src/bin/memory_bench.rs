use std::time::Instant;

use vivyshot_core::{
  vs_add_arrow, vs_add_blur_rect, vs_add_line, vs_add_pixelate_rect, vs_add_rect, vs_add_text,
  vs_blur_rect_command, vs_create_document_from_bgra, vs_destroy_document, vs_dirty_rect,
  vs_line_command, vs_pixelate_rect_command, vs_rect_command, vs_redo, vs_render_dirty,
  vs_render_full, vs_text_command, vs_undo, vs_arrow_command,
};

fn main() {
  let sessions = parse_sessions();
  let started = Instant::now();
  let mut checksum = 0u64;
  let mut latencies_ms = Vec::with_capacity(sessions);

  for i in 0..sessions {
    let session_started = Instant::now();
    checksum = checksum.wrapping_add(run_session(i));
    latencies_ms.push(session_started.elapsed().as_secs_f64() * 1000.0);
    if (i + 1) % 10 == 0 || i + 1 == sessions {
      println!("completed {}/{}", i + 1, sessions);
    }
  }

  let elapsed = started.elapsed();
  let avg_ms = elapsed.as_secs_f64() * 1000.0 / sessions as f64;
  let median_ms = percentile_ms(&latencies_ms, 50.0);
  let p95_ms = percentile_ms(&latencies_ms, 95.0);
  let p99_ms = percentile_ms(&latencies_ms, 99.0);
  println!("sessions={}", sessions);
  println!("elapsed_ms={:.2}", elapsed.as_secs_f64() * 1000.0);
  println!("avg_ms_per_session={:.2}", avg_ms);
  println!("median_ms_per_session={:.2}", median_ms);
  println!("p95_ms_per_session={:.2}", p95_ms);
  println!("p99_ms_per_session={:.2}", p99_ms);
  println!("checksum={}", checksum);
}

fn parse_sessions() -> usize {
  std::env::args()
    .nth(1)
    .and_then(|v| v.parse::<usize>().ok())
    .filter(|v| *v > 0)
    .unwrap_or(100)
}

fn run_session(index: usize) -> u64 {
  let (width, height) = pick_dimensions(index);
  let stride = width * 4;
  let base = make_base(width, height, index as u32);
  let mut out = vec![0u8; base.len()];

  // SAFETY: all pointers passed to FFI are backed by stable vectors for the call duration.
  unsafe {
    let doc = vs_create_document_from_bgra(
      width as u32,
      height as u32,
      stride as u32,
      base.as_ptr(),
      base.len(),
    );
    assert!(!doc.is_null());

    assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);

    let rect = vs_rect_command {
      x: (width as i32 / 12).max(2),
      y: (height as i32 / 10).max(2),
      width: (width as i32 / 3).max(8),
      height: (height as i32 / 4).max(8),
      stroke_width: 3,
      r: 40,
      g: 220,
      b: 255,
      a: 230,
    };
    assert_eq!(vs_add_rect(doc, rect), 0);
    render_dirty(doc, &mut out);

    let line = vs_line_command {
      x0: (width as i32 / 8).max(2),
      y0: (height as i32 / 2).max(2),
      x1: (width as i32 * 7 / 8).max(3),
      y1: (height as i32 * 3 / 4).max(3),
      stroke_width: 3,
      r: 180,
      g: 255,
      b: 20,
      a: 220,
    };
    assert_eq!(vs_add_line(doc, line), 0);
    render_dirty(doc, &mut out);

    let arrow = vs_arrow_command {
      x0: (width as i32 / 6).max(2),
      y0: (height as i32 * 4 / 5).max(2),
      x1: (width as i32 * 5 / 6).max(3),
      y1: (height as i32 / 5).max(3),
      stroke_width: 3,
      r: 255,
      g: 180,
      b: 0,
      a: 235,
    };
    assert_eq!(vs_add_arrow(doc, arrow), 0);
    render_dirty(doc, &mut out);

    let text_cmd = vs_text_command {
      x: (width as i32 / 16).max(1),
      y: (height as i32 / 16).max(1),
      font_px: 18,
      r: 255,
      g: 255,
      b: 255,
      a: 240,
    };
    let label = format!("Session {}", index + 1);
    assert_eq!(
      vs_add_text(doc, label.as_ptr(), label.len(), text_cmd),
      0
    );
    render_dirty(doc, &mut out);

    let pixelate = vs_pixelate_rect_command {
      x: (width as i32 / 3).max(1),
      y: (height as i32 / 3).max(1),
      width: (width as i32 / 4).max(8),
      height: (height as i32 / 4).max(8),
      block_size: 12,
    };
    assert_eq!(vs_add_pixelate_rect(doc, pixelate), 0);
    render_dirty(doc, &mut out);

    let blur = vs_blur_rect_command {
      x: (width as i32 / 2).max(1),
      y: (height as i32 / 6).max(1),
      width: (width as i32 / 5).max(8),
      height: (height as i32 / 4).max(8),
      radius: 4,
    };
    assert_eq!(vs_add_blur_rect(doc, blur), 0);
    render_dirty(doc, &mut out);

    assert_eq!(vs_undo(doc), 0);
    render_dirty(doc, &mut out);
    assert_eq!(vs_redo(doc), 0);
    render_dirty(doc, &mut out);

    assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);

    let checksum = checksum_bytes(&out);
    vs_destroy_document(doc);
    checksum
  }
}

unsafe fn render_dirty(doc: *mut std::ffi::c_void, out: &mut [u8]) {
  let mut dirty = vs_dirty_rect {
    x: 0,
    y: 0,
    width: 0,
    height: 0,
  };
  let mut written: usize = 0;
  assert_eq!(
    vs_render_dirty(
      doc,
      out.as_mut_ptr(),
      out.len(),
      &mut dirty,
      1,
      &mut written
    ),
    0
  );
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

fn make_base(width: usize, height: usize, seed: u32) -> Vec<u8> {
  let mut data = vec![0u8; width * height * 4];
  for y in 0..height {
    for x in 0..width {
      let idx = (y * width + x) * 4;
      data[idx] = ((x as u32 + seed * 17) % 256) as u8;
      data[idx + 1] = ((y as u32 + seed * 23) % 256) as u8;
      data[idx + 2] = (((x as u32 + y as u32) / 2 + seed * 31) % 256) as u8;
      data[idx + 3] = 255;
    }
  }
  data
}

fn pick_dimensions(index: usize) -> (usize, usize) {
  match index % 4 {
    0 => (1280, 720),
    1 => (1920, 1080),
    2 => (2048, 1152),
    _ => (2560, 1440),
  }
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
