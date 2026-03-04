use super::*;

fn zero_encoded_bytes(bytes: &mut vs_encoded_bytes) {
    bytes.ptr = std::ptr::null_mut();
    bytes.len = 0;
}
fn bgra_to_rgba(bytes: &[u8], width: usize, height: usize, stride: usize) -> Option<Vec<u8>> {
    let row_bytes = width.checked_mul(4)?;
    if stride < row_bytes {
        return None;
    }

    let mut rgba = vec![0u8; row_bytes.checked_mul(height)?];
    for y in 0..height {
        let src_row = &bytes[y * stride..y * stride + row_bytes];
        let dst_row = &mut rgba[y * row_bytes..(y + 1) * row_bytes];
        for x in 0..width {
            let si = x * 4;
            let di = si;
            dst_row[di] = src_row[si + 2];
            dst_row[di + 1] = src_row[si + 1];
            dst_row[di + 2] = src_row[si];
            dst_row[di + 3] = src_row[si + 3];
        }
    }
    Some(rgba)
}

fn rgba_to_rgb(rgba: &[u8]) -> Vec<u8> {
    let mut rgb = Vec::with_capacity(rgba.len() / 4 * 3);
    for chunk in rgba.chunks_exact(4) {
        rgb.push(chunk[0]);
        rgb.push(chunk[1]);
        rgb.push(chunk[2]);
    }
    rgb
}

#[no_mangle]
pub unsafe extern "C" fn vs_encode_bgra_image(
    source: vs_bgra_image_view,
    format: u8,
    jpeg_quality: u8,
    out_bytes: *mut vs_encoded_bytes,
) -> i32 {
    if out_bytes.is_null() {
        return -1;
    }

    // SAFETY: caller provides writable pointer.
    let out_bytes_ref = unsafe { &mut *out_bytes };
    zero_encoded_bytes(out_bytes_ref);

    // SAFETY: validates pointer/len invariants before returning bytes.
    let (bytes, width, height, stride) = match unsafe { bgra_view_slice(source) } {
        Some(v) => v,
        None => return -2,
    };
    let rgba = match bgra_to_rgba(bytes, width, height, stride) {
        Some(v) => v,
        None => return -2,
    };
    if !ffi_encode::supports_image_format(format, VS_IMAGE_ENCODE_PNG, VS_IMAGE_ENCODE_JPEG) {
        return -2;
    }

    let encoded = match format {
        VS_IMAGE_ENCODE_PNG => {
            let mut out = Vec::<u8>::new();
            let encoder = PngEncoder::new(&mut out);
            if encoder
                .write_image(&rgba, width as u32, height as u32, ColorType::Rgba8.into())
                .is_err()
            {
                return -3;
            }
            out
        }
        VS_IMAGE_ENCODE_JPEG => {
            let quality = ffi_encode::normalized_jpeg_quality(jpeg_quality);
            let rgb = rgba_to_rgb(&rgba);
            let mut out = Vec::<u8>::new();
            let encoder = JpegEncoder::new_with_quality(&mut out, quality);
            if encoder
                .write_image(&rgb, width as u32, height as u32, ColorType::Rgb8.into())
                .is_err()
            {
                return -3;
            }
            out
        }
        _ => unreachable!("format validated above"),
    };

    let mut owned = encoded;
    out_bytes_ref.ptr = owned.as_mut_ptr();
    out_bytes_ref.len = owned.len();
    std::mem::forget(owned);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_encoded_bytes_destroy(bytes: *mut vs_encoded_bytes) {
    if bytes.is_null() {
        return;
    }

    let bytes_ref = unsafe { &mut *bytes };
    if !bytes_ref.ptr.is_null() && bytes_ref.len > 0 {
        // SAFETY: pointer/len came from Vec allocation in `vs_encode_bgra_image`.
        unsafe {
            drop(Vec::from_raw_parts(
                bytes_ref.ptr,
                bytes_ref.len,
                bytes_ref.len,
            ));
        }
    }
    zero_encoded_bytes(bytes_ref);
}

#[no_mangle]
pub unsafe extern "C" fn vs_bgra_owned_image_destroy(image: *mut vs_bgra_owned_image) {
    if image.is_null() {
        return;
    }

    let image = unsafe { &mut *image };
    if !image.ptr.is_null() && image.len > 0 {
        // SAFETY: pointer/len came from Vec allocation in `vs_stitch_merge_bgra`.
        unsafe {
            drop(Vec::from_raw_parts(image.ptr, image.len, image.len));
        }
    }

    zero_bgra_owned_image(image);
}
