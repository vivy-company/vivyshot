use crate::vs_stitch_delta;
use vivyshot_domain::{
    stitch_estimate_delta as domain_stitch_estimate_delta, BgraImageView as DomainBgraImageView,
};

pub(crate) fn estimate_delta(
    previous: DomainBgraImageView<'_>,
    current: DomainBgraImageView<'_>,
    preferred_side: i32,
    expected_rows: u32,
    has_expected_rows: bool,
    relaxed: bool,
) -> Option<vs_stitch_delta> {
    let preferred = match preferred_side {
        0 => Some(0u8),
        1 => Some(1u8),
        _ => None,
    };
    let expected = if has_expected_rows {
        Some(expected_rows)
    } else {
        None
    };

    domain_stitch_estimate_delta(previous, current, preferred, expected, relaxed).map(|delta| {
        vs_stitch_delta {
            rows: delta.rows,
            side: delta.side,
            score: delta.score,
        }
    })
}
