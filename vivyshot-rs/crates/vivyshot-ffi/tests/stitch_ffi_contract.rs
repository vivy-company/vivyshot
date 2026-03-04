mod common;

use common::{bgra_view, pixel_bgra};
use vivyshot_core::{
    vs_bgra_crop, vs_bgra_owned_image, vs_bgra_owned_image_destroy, vs_encode_bgra_image,
    vs_encoded_bytes, vs_encoded_bytes_destroy, vs_stitch_autoscroll_reset,
    vs_stitch_autoscroll_state, vs_stitch_autoscroll_update, vs_stitch_delta,
    vs_stitch_estimate_delta_bgra, vs_stitch_merge_bgra, vs_stitch_session_create,
    vs_stitch_session_destroy, vs_stitch_session_push_frame_and_merge_bgra,
    vs_stitch_session_result, vs_stitch_session_set_base_bgra, VS_STATUS_INVALID_ARGUMENT,
};

#[test]
fn bgra_crop_and_encode_cover_image_pipeline() {
    let width = 12usize;
    let height = 10usize;
    let mut pixels = vec![0u8; width * height * 4];
    for y in 0..height {
        for x in 0..width {
            let idx = y * width * 4 + x * 4;
            pixels[idx] = (x as u8).wrapping_mul(7);
            pixels[idx + 1] = (y as u8).wrapping_mul(9);
            pixels[idx + 2] = 120;
            pixels[idx + 3] = 255;
        }
    }

    let source = bgra_view(&pixels, width, height);
    let mut cropped = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut encoded = vs_encoded_bytes {
        ptr: std::ptr::null_mut(),
        len: 0,
    };

    // SAFETY: source buffers are alive for the duration of calls.
    unsafe {
        assert_eq!(vs_bgra_crop(source, 2, 3, 4, 5, &mut cropped), 0);
        assert_eq!(cropped.width, 4);
        assert_eq!(cropped.height, 5);

        let cropped_pixels = std::slice::from_raw_parts(cropped.ptr, cropped.len);
        assert_eq!(
            pixel_bgra(cropped_pixels, cropped.stride as usize, 0, 0),
            (14, 27, 120, 255)
        );

        let view = vivyshot_core::vs_bgra_image_view {
            width: cropped.width,
            height: cropped.height,
            stride: cropped.stride,
            ptr: cropped.ptr,
            len: cropped.len,
        };
        assert_eq!(vs_encode_bgra_image(view, 0, 0, &mut encoded), 0);

        let png = std::slice::from_raw_parts(encoded.ptr, encoded.len);
        assert_eq!(png[0], 0x89);
        assert_eq!(png[1], b'P');

        vs_encoded_bytes_destroy(&mut encoded);
        vs_bgra_owned_image_destroy(&mut cropped);
    }
}

#[test]
fn stitch_delta_merge_and_session_flow_work_together() {
    let width = 64usize;
    let height = 48usize;
    let shift = 6usize;

    let mut frame_a = vec![0u8; width * height * 4];
    for y in 0..height {
        for x in 0..width {
            let idx = y * width * 4 + x * 4;
            frame_a[idx] = ((x * 5 + y * 7) % 251) as u8;
            frame_a[idx + 1] = ((x * 11 + y * 3) % 251) as u8;
            frame_a[idx + 2] = ((x * 13 + y * 17) % 251) as u8;
            frame_a[idx + 3] = 255;
        }
    }

    let mut frame_b = vec![0u8; width * height * 4];
    for y in 0..(height - shift) {
        let src = (y + shift) * width * 4;
        let dst = y * width * 4;
        frame_b[dst..dst + width * 4].copy_from_slice(&frame_a[src..src + width * 4]);
    }
    for y in (height - shift)..height {
        for x in 0..width {
            let idx = y * width * 4 + x * 4;
            frame_b[idx] = ((x * 19 + y * 23 + 31) % 251) as u8;
            frame_b[idx + 1] = ((x * 29 + y * 7 + 41) % 251) as u8;
            frame_b[idx + 2] = ((x * 3 + y * 37 + 53) % 251) as u8;
            frame_b[idx + 3] = 255;
        }
    }

    let view_a = bgra_view(&frame_a, width, height);
    let view_b = bgra_view(&frame_b, width, height);

    let mut delta = vs_stitch_delta::default();
    // SAFETY: views remain valid during calls.
    unsafe {
        assert_eq!(
            vs_stitch_estimate_delta_bgra(
                view_a,
                view_b,
                -1,
                shift as u32,
                true,
                false,
                &mut delta
            ),
            0
        );
    }
    assert_eq!(delta.rows, shift as u32);
    assert_eq!(delta.side, 1);

    let mut merged = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    // SAFETY: views and output pointer are valid.
    unsafe {
        assert_eq!(vs_stitch_merge_bgra(view_a, view_b, 1, &mut merged), 0);
        assert_eq!(merged.width as usize, width);
        // Direct merge appends the entire segment buffer on the selected side.
        assert_eq!(merged.height as usize, height * 2);
        vs_bgra_owned_image_destroy(&mut merged);
    }

    let session = vs_stitch_session_create();
    assert!(!session.is_null());

    let mut result = vs_stitch_session_result::default();
    let mut merged_frame = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };

    // SAFETY: session handle and views are valid.
    unsafe {
        assert_eq!(vs_stitch_session_set_base_bgra(session, view_a, 1), 0);
        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                view_a,
                &mut result,
                &mut merged_frame
            ),
            0
        );
        assert!(!result.accepted);

        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                view_b,
                &mut result,
                &mut merged_frame
            ),
            0
        );
        assert!(result.accepted);
        assert_eq!(result.rows, shift as u32);
        assert_eq!(result.segment_count, 2);

        if !merged_frame.ptr.is_null() {
            vs_bgra_owned_image_destroy(&mut merged_frame);
        }
        vs_stitch_session_destroy(session);
    }
}

#[test]
fn stitch_autoscroll_policy_flips_once() {
    let mut state = vs_stitch_autoscroll_state::default();

    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(vs_stitch_autoscroll_reset(&mut state), 0);
    }
    assert_eq!(state.direction_sign, -1);

    for _ in 0..4 {
        let mut next = vs_stitch_autoscroll_state::default();
        // SAFETY: output pointers are valid.
        unsafe {
            assert_eq!(
                vs_stitch_autoscroll_update(true, false, false, 4, state, &mut next),
                0
            );
        }
        state = next;
    }

    assert_eq!(state.direction_sign, 1);
    assert!(state.did_flip_direction);
    assert_eq!(state.no_motion_ticks, 0);
}

#[test]
fn stale_stitch_session_handle_is_rejected_after_destroy() {
    let session = vs_stitch_session_create();
    assert!(!session.is_null());

    let pixels = vec![0u8; 16 * 16 * 4];
    let view = bgra_view(&pixels, 16, 16);

    // SAFETY: handle is valid for destroy; stale-handle call checks rejection.
    unsafe {
        vs_stitch_session_destroy(session);
        assert_eq!(
            vs_stitch_session_set_base_bgra(session, view, 1),
            VS_STATUS_INVALID_ARGUMENT
        );
    }
}
