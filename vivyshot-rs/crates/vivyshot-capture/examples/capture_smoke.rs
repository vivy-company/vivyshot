use std::env;
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use vivyshot_capture::{
    Backend, CaptureDeviceKind, CaptureRect, RecordingConfig, RecordingEncoder,
    PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST,
};

#[derive(Debug, Clone)]
struct Options {
    rect: CaptureRect,
    duration_ms: u64,
    frame_rates: Vec<u32>,
    encoders: Vec<RecordingEncoder>,
    screenshot: bool,
    record: bool,
    capture_system_audio: bool,
    capture_microphone: bool,
    show_cursor: bool,
    highlight_mouse_clicks: bool,
    include_window_ids: Vec<u32>,
    exclude_current_process: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            rect: CaptureRect {
                x: 0.0,
                y: 0.0,
                width: 640.0,
                height: 360.0,
            },
            duration_ms: 900,
            frame_rates: vec![30],
            encoders: vec![RecordingEncoder::StandardH264],
            screenshot: true,
            record: true,
            capture_system_audio: false,
            capture_microphone: false,
            show_cursor: true,
            highlight_mouse_clicks: true,
            include_window_ids: Vec::new(),
            exclude_current_process: true,
        }
    }
}

fn main() {
    let options = match parse_options(env::args().skip(1)) {
        Ok(options) => options,
        Err(error) => {
            eprintln!("{error}");
            print_usage();
            std::process::exit(2);
        }
    };

    let backend = Backend::new();
    let capabilities = backend.capabilities();
    println!("capabilities: {capabilities:?}");

    for kind in [CaptureDeviceKind::Display, CaptureDeviceKind::Microphone] {
        match backend.devices(kind) {
            Ok(devices) => println!("{kind:?} devices: {devices:?}"),
            Err(error) => println!("{kind:?} devices unavailable: {error}"),
        }
    }

    if options.screenshot {
        smoke_screenshot(&backend, options.rect);
    }

    if options.record {
        for encoder in &options.encoders {
            for frame_rate in &options.frame_rates {
                smoke_recording(&backend, &options, *encoder, *frame_rate);
            }
        }
    }
}

fn smoke_screenshot(backend: &Backend, rect: CaptureRect) {
    let image = backend
        .capture_screenshot(rect)
        .unwrap_or_else(|error| panic!("screenshot failed: {error}"));
    assert!(image.width > 0, "screenshot width must be non-zero");
    assert!(image.height > 0, "screenshot height must be non-zero");
    assert_eq!(
        image.pixel_format, PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST,
        "screenshot pixel format"
    );
    assert!(
        image.bytes_per_row >= image.width * 4,
        "screenshot row stride must hold BGRA pixels"
    );
    assert!(
        image.data.len() >= image.bytes_per_row as usize * image.height as usize,
        "screenshot data must hold all rows"
    );
    println!(
        "screenshot ok: {}x{} stride={} bytes={}",
        image.width,
        image.height,
        image.bytes_per_row,
        image.data.len()
    );
}

fn smoke_recording(
    backend: &Backend,
    options: &Options,
    encoder: RecordingEncoder,
    frame_rate: u32,
) {
    let output_path = smoke_output_path(encoder, frame_rate);
    let config = RecordingConfig {
        selection_rect_screen: options.rect,
        output_path: output_path.clone(),
        frame_rate,
        encoder,
        capture_system_audio: options.capture_system_audio,
        capture_microphone: options.capture_microphone,
        show_cursor: options.show_cursor,
        highlight_mouse_clicks: options.highlight_mouse_clicks,
        include_window_ids: options.include_window_ids.clone(),
        exclude_current_process: options.exclude_current_process,
    };

    let session = backend.start_recording(config).unwrap_or_else(|error| {
        panic!("recording start failed for {encoder:?} {frame_rate}fps: {error}")
    });
    thread::sleep(Duration::from_millis(options.duration_ms));
    let output = session.stop().unwrap_or_else(|error| {
        panic!("recording stop failed for {encoder:?} {frame_rate}fps: {error}")
    });

    let metadata = std::fs::metadata(&output.output_path)
        .unwrap_or_else(|error| panic!("recording output missing: {error}"));
    assert!(metadata.len() > 0, "recording output must be non-empty");
    assert!(output.width > 0, "recording width must be non-zero");
    assert!(output.height > 0, "recording height must be non-zero");
    assert_eq!(output.frame_rate, frame_rate.max(1), "effective frame rate");
    println!(
        "recording ok: {encoder:?} {}fps {:?}/{:?} {}x{} {} bytes at {}",
        output.frame_rate,
        output.codec,
        output.container,
        output.width,
        output.height,
        metadata.len(),
        output.output_path.display()
    );

    if output_path != output.output_path {
        let _ = std::fs::remove_file(output_path);
    }
}

fn smoke_output_path(encoder: RecordingEncoder, frame_rate: u32) -> PathBuf {
    let encoder = match encoder {
        RecordingEncoder::StandardH264 => "h264",
        RecordingEncoder::SmallerFileHevc => "hevc",
        RecordingEncoder::SoftwareH264 => "software-h264",
    };
    env::temp_dir().join(format!(
        "vivyshot-capture-smoke-{encoder}-{frame_rate}-{}.mp4",
        std::process::id()
    ))
}

fn parse_options(args: impl Iterator<Item = String>) -> Result<Options, String> {
    let mut options = Options::default();
    let mut args = args.peekable();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--help" | "-h" => {
                print_usage();
                std::process::exit(0);
            }
            "--rect" => {
                let value = args.next().ok_or("--rect requires x,y,width,height")?;
                options.rect = parse_rect(&value)?;
            }
            "--duration-ms" => {
                let value = args.next().ok_or("--duration-ms requires a value")?;
                options.duration_ms = value
                    .parse()
                    .map_err(|_| "--duration-ms must be a positive integer")?;
            }
            "--frame-rate" => {
                let value = args.next().ok_or("--frame-rate requires a value")?;
                options.frame_rates = vec![parse_frame_rate(&value)?];
            }
            "--frame-rates" => {
                let value = args
                    .next()
                    .ok_or("--frame-rates requires comma-separated values")?;
                options.frame_rates = value
                    .split(',')
                    .map(parse_frame_rate)
                    .collect::<Result<Vec<_>, _>>()?;
            }
            "--encoder" => {
                let value = args
                    .next()
                    .ok_or("--encoder requires h264, hevc, or software-h264")?;
                options.encoders = vec![parse_encoder(&value)?];
            }
            "--encoders" => {
                let value = args
                    .next()
                    .ok_or("--encoders requires comma-separated values")?;
                options.encoders = value
                    .split(',')
                    .map(parse_encoder)
                    .collect::<Result<Vec<_>, _>>()?;
            }
            "--matrix" => {
                options.frame_rates = vec![30, 60, 120];
                options.encoders = vec![
                    RecordingEncoder::StandardH264,
                    RecordingEncoder::SmallerFileHevc,
                    RecordingEncoder::SoftwareH264,
                ];
            }
            "--screenshot-only" => {
                options.screenshot = true;
                options.record = false;
            }
            "--record-only" => {
                options.screenshot = false;
                options.record = true;
            }
            "--system-audio" => options.capture_system_audio = true,
            "--microphone" => options.capture_microphone = true,
            "--no-cursor" => options.show_cursor = false,
            "--no-mouse-clicks" => options.highlight_mouse_clicks = false,
            "--include-window-id" => {
                let value = args
                    .next()
                    .ok_or("--include-window-id requires a window id")?;
                options.include_window_ids.push(parse_window_id(&value)?);
            }
            "--include-window-ids" => {
                let value = args
                    .next()
                    .ok_or("--include-window-ids requires comma-separated window ids")?;
                options.include_window_ids = value
                    .split(',')
                    .map(parse_window_id)
                    .collect::<Result<Vec<_>, _>>()?;
            }
            "--no-exclude-current-process" => options.exclude_current_process = false,
            other => return Err(format!("unknown option: {other}")),
        }
    }

    if options.frame_rates.is_empty() {
        return Err("at least one frame rate is required".to_string());
    }
    if options.encoders.is_empty() {
        return Err("at least one encoder is required".to_string());
    }
    Ok(options)
}

fn parse_rect(value: &str) -> Result<CaptureRect, String> {
    let parts = value
        .split(',')
        .map(|part| part.parse::<f64>())
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| "--rect values must be numbers")?;
    if parts.len() != 4 {
        return Err("--rect requires x,y,width,height".to_string());
    }
    Ok(CaptureRect {
        x: parts[0],
        y: parts[1],
        width: parts[2],
        height: parts[3],
    })
}

fn parse_frame_rate(value: &str) -> Result<u32, String> {
    let frame_rate: u32 = value
        .parse()
        .map_err(|_| "frame rate must be a positive integer")?;
    if frame_rate == 0 {
        return Err("frame rate must be positive".to_string());
    }
    Ok(frame_rate)
}

fn parse_encoder(value: &str) -> Result<RecordingEncoder, String> {
    match value {
        "h264" => Ok(RecordingEncoder::StandardH264),
        "hevc" => Ok(RecordingEncoder::SmallerFileHevc),
        "software-h264" => Ok(RecordingEncoder::SoftwareH264),
        other => Err(format!("unsupported smoke encoder: {other}")),
    }
}

fn parse_window_id(value: &str) -> Result<u32, String> {
    value
        .parse()
        .map_err(|_| "window id must be a positive u32".to_string())
}

fn print_usage() {
    eprintln!(
        "usage: cargo run -p vivyshot-capture --example capture_smoke -- [--matrix] [--rect x,y,w,h] [--duration-ms ms] [--system-audio] [--microphone] [--include-window-id id]"
    );
}
