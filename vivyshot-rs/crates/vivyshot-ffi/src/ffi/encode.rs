pub(crate) fn normalized_jpeg_quality(raw: u8) -> u8 {
    if raw == 0 {
        90
    } else {
        raw.min(100)
    }
}

pub(crate) fn supports_image_format(format: u8, png: u8, jpeg: u8) -> bool {
    format == png || format == jpeg
}
