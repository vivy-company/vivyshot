pub(crate) fn validate_annotation_index(index: u32, len: usize) -> Option<usize> {
    let idx = index as usize;
    if idx < len {
        Some(idx)
    } else {
        None
    }
}
