#![allow(dead_code)]

use std::ffi::c_void;
use vivyshot_core::{
    vs_annotation_info, vs_bgra_image_view, vs_clip_transform, vs_create_document_from_bgra,
    vs_destroy_document, vs_timeline_clip_info, vs_timeline_track_info,
};

pub fn make_base(width: usize, height: usize) -> Vec<u8> {
    let mut pixels = vec![0u8; width * height * 4];
    for i in (3..pixels.len()).step_by(4) {
        pixels[i] = 255;
    }
    pixels
}

pub unsafe fn make_doc(width: usize, height: usize) -> *mut c_void {
    let base = make_base(width, height);
    unsafe {
        vs_create_document_from_bgra(
            width as u32,
            height as u32,
            (width * 4) as u32,
            base.as_ptr(),
            base.len(),
        )
    }
}

pub unsafe fn destroy_doc(doc: *mut c_void) {
    unsafe { vs_destroy_document(doc) }
}

pub fn solid_bgra(width: usize, height: usize, b: u8, g: u8, r: u8, a: u8) -> Vec<u8> {
    let mut pixels = vec![0u8; width * height * 4];
    for y in 0..height {
        for x in 0..width {
            let idx = y * width * 4 + x * 4;
            pixels[idx] = b;
            pixels[idx + 1] = g;
            pixels[idx + 2] = r;
            pixels[idx + 3] = a;
        }
    }
    pixels
}

pub fn bgra_view(pixels: &[u8], width: usize, height: usize) -> vs_bgra_image_view {
    vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: (width * 4) as u32,
        ptr: pixels.as_ptr(),
        len: pixels.len(),
    }
}

pub fn pixel_bgra(pixels: &[u8], stride: usize, x: usize, y: usize) -> (u8, u8, u8, u8) {
    let idx = y * stride + x * 4;
    (
        pixels[idx],
        pixels[idx + 1],
        pixels[idx + 2],
        pixels[idx + 3],
    )
}

pub fn zero_annotation_info() -> vs_annotation_info {
    vs_annotation_info {
        index: 0,
        kind: 0,
        x: 0,
        y: 0,
        width: 0,
        height: 0,
    }
}

pub fn zero_track_info() -> vs_timeline_track_info {
    vs_timeline_track_info {
        kind: 0,
        visible: false,
        clip_count: 0,
    }
}

pub fn zero_clip_info() -> vs_timeline_clip_info {
    vs_timeline_clip_info {
        id: 0,
        track_index: 0,
        start_ms: 0,
        end_ms: 0,
        kind: 0,
        transform: vs_clip_transform {
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: 0.0,
            rotation: 0.0,
            opacity: 0.0,
        },
    }
}

pub fn approx_eq(a: f32, b: f32, eps: f32) -> bool {
    (a - b).abs() <= eps
}
