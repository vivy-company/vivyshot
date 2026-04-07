use super::*;

fn make_base(width: usize, height: usize) -> Vec<u8> {
    let mut data = vec![0u8; width * height * 4];
    for i in (3..data.len()).step_by(4) {
        data[i] = 255;
    }
    data
}

unsafe fn make_doc(width: usize, height: usize) -> *mut c_void {
    let base = make_base(width, height);
    // SAFETY: buffer is alive for call duration.
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

fn zero_transform() -> vs_clip_transform {
    vs_clip_transform {
        x: 0.0,
        y: 0.0,
        width: 0.0,
        height: 0.0,
        rotation: 0.0,
        opacity: 0.0,
    }
}

fn zero_clip_info() -> vs_timeline_clip_info {
    vs_timeline_clip_info {
        id: 0,
        track_index: 0,
        start_ms: 0,
        end_ms: 0,
        kind: 0,
        transform: zero_transform(),
    }
}

fn solid_bgra(width: usize, height: usize, b: u8, g: u8, r: u8, a: u8) -> Vec<u8> {
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

fn pixel_bgra(pixels: &[u8], stride: usize, x: usize, y: usize) -> (u8, u8, u8, u8) {
    let idx = y * stride + x * 4;
    (
        pixels[idx],
        pixels[idx + 1],
        pixels[idx + 2],
        pixels[idx + 3],
    )
}

fn approx_eq(lhs: f32, rhs: f32, epsilon: f32) -> bool {
    (lhs - rhs).abs() <= epsilon
}

fn patterned_bgra(width: usize, height: usize, seed: u32) -> Vec<u8> {
    let mut pixels = vec![0u8; width * height * 4];
    for y in 0..height {
        for x in 0..width {
            let idx = y * width * 4 + x * 4;
            pixels[idx] = ((x as u32 * 11 + y as u32 * 7 + seed * 3) % 251) as u8;
            pixels[idx + 1] = ((x as u32 * 5 + y as u32 * 13 + seed * 17) % 251) as u8;
            pixels[idx + 2] = ((x as u32 * 19 + y as u32 * 2 + seed * 29) % 251) as u8;
            pixels[idx + 3] = 255;
        }
    }
    pixels
}

fn process_rss_kb() -> Option<u64> {
    let pid = std::process::id().to_string();
    let output = std::process::Command::new("ps")
        .args(["-o", "rss=", "-p", &pid])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8(output.stdout).ok()?;
    stdout.split_whitespace().next()?.parse::<u64>().ok()
}

#[test]
fn handle_registries_return_to_baseline_after_stress() {
    let baseline = live_handle_counts();

    for iter in 0..48u32 {
        let width = 64usize + ((iter % 4) as usize) * 16;
        let height = 48usize + ((iter % 3) as usize) * 16;
        let stride = width * 4;
        let pixels = patterned_bgra(width, height, iter);
        let view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: pixels.as_ptr(),
            len: pixels.len(),
        };

        // SAFETY: handles and pointers are valid for each call duration.
        unsafe {
            let doc = vs_create_document_from_bgra(
                width as u32,
                height as u32,
                stride as u32,
                pixels.as_ptr(),
                pixels.len(),
            );
            assert!(!doc.is_null());
            let mut out = vec![0u8; pixels.len()];
            assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);
            vs_destroy_document(doc);

            let stitch = vs_stitch_session_create();
            assert!(!stitch.is_null());
            assert_eq!(vs_stitch_session_set_base_bgra(stitch, view, 1), 0);
            vs_stitch_session_destroy(stitch);

            let video = vs_video_session_create(vs_video_session_config {
                frame_rate: 30,
                capture_system_audio: false,
                capture_microphone: false,
                show_webcam: false,
                highlight_mouse_clicks: false,
                highlight_keystrokes: false,
            });
            assert!(!video.is_null());
            vs_video_session_destroy(video);

            let timeline = vs_timeline_create(3_000, width as u32, height as u32);
            assert!(!timeline.is_null());
            vs_timeline_destroy(timeline);

            let stats = vs_stats_session_create();
            assert!(!stats.is_null());
            vs_stats_session_destroy(stats);
        }
    }

    assert_eq!(live_handle_counts(), baseline);
}

#[test]
fn stats_session_tracks_totals_and_serializes() {
    let stats = vs_stats_session_create();
    assert!(!stats.is_null());

    let capture_id = b"capture-1";
    let screenshot_key = b"screenshot_capture:capture-1";
    let completion_key = b"screenshot_session_completed:capture-1";
    let recording_id = b"recording-1";
    let recording_key = b"recording_completed:recording-1";
    let mut applied = false;

    let screenshot = vs_stats_event {
        event_type: VS_STATS_EVENT_SCREENSHOT_CAPTURED,
        reserved0: [0, 0, 0],
        timezone_offset_minutes: 480,
        occurred_at_ms: 1_710_000_000_000,
        bytes_produced: 12_345,
        duration_ms: -1,
        screenshot_completion_duration_ms: -1,
        event_key_ptr: screenshot_key.as_ptr(),
        event_key_len: screenshot_key.len(),
        capture_id_ptr: capture_id.as_ptr(),
        capture_id_len: capture_id.len(),
    };
    let completion = vs_stats_event {
        event_type: VS_STATS_EVENT_SCREENSHOT_SESSION_COMPLETED,
        reserved0: [0, 0, 0],
        timezone_offset_minutes: 480,
        occurred_at_ms: 1_710_000_010_000,
        bytes_produced: 0,
        duration_ms: -1,
        screenshot_completion_duration_ms: 10_000,
        event_key_ptr: completion_key.as_ptr(),
        event_key_len: completion_key.len(),
        capture_id_ptr: capture_id.as_ptr(),
        capture_id_len: capture_id.len(),
    };
    let recording = vs_stats_event {
        event_type: VS_STATS_EVENT_RECORDING_COMPLETED,
        reserved0: [0, 0, 0],
        timezone_offset_minutes: 480,
        occurred_at_ms: 1_710_086_400_000,
        bytes_produced: 54_321,
        duration_ms: 90_000,
        screenshot_completion_duration_ms: -1,
        event_key_ptr: recording_key.as_ptr(),
        event_key_len: recording_key.len(),
        capture_id_ptr: recording_id.as_ptr(),
        capture_id_len: recording_id.len(),
    };

    unsafe {
        assert_eq!(vs_stats_session_ingest_event(stats, screenshot, &mut applied), 0);
        assert!(applied);
        assert_eq!(vs_stats_session_ingest_event(stats, screenshot, &mut applied), 0);
        assert!(!applied);
        assert_eq!(vs_stats_session_ingest_event(stats, completion, &mut applied), 0);
        assert!(applied);
        assert_eq!(vs_stats_session_ingest_event(stats, recording, &mut applied), 0);
        assert!(applied);

        let mut summary = vs_stats_summary::default();
        assert_eq!(vs_stats_session_get_summary(stats, &mut summary), 0);
        assert_eq!(summary.total_screenshots_captured, 1);
        assert_eq!(summary.total_recordings_completed, 1);
        assert_eq!(summary.total_capture_bytes_produced, 66_666);
        assert_eq!(summary.average_screenshot_editor_completion_duration_ms, 10_000);
        assert_eq!(summary.current_capture_streak_days, 2);

        let mut written = 0;
        assert_eq!(
            vs_stats_session_get_all_daily_buckets(stats, std::ptr::null_mut(), 0, &mut written),
            0
        );
        assert_eq!(written, 2);

        let mut buckets = vec![vs_stats_daily_bucket::default(); written as usize];
        assert_eq!(
            vs_stats_session_get_all_daily_buckets(
                stats,
                buckets.as_mut_ptr(),
                buckets.len() as u32,
                &mut written
            ),
            0
        );
        assert_eq!(written, 2);
        assert_eq!(buckets[0].screenshot_count, 1);
        assert_eq!(buckets[1].recording_count, 1);

        let mut buffer = vec![0u8; 8_192];
        assert_eq!(
            vs_stats_session_serialize_json(
                stats,
                buffer.as_mut_ptr(),
                buffer.len() as u32,
                &mut written
            ),
            0
        );
        let restored = vs_stats_session_deserialize_json(buffer.as_ptr(), written);
        assert!(!restored.is_null());
        vs_stats_session_destroy(restored);
        vs_stats_session_destroy(stats);
    }
}

#[test]
fn screenshot_pipeline_resident_memory_stays_bounded() {
    let Some(baseline_rss) = process_rss_kb() else {
        eprintln!("skipping RSS bound assertion: unable to read process RSS");
        return;
    };

    let peak_limit_kb = std::env::var("VIVYSHOT_RSS_PEAK_LIMIT_KB")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(650_000);
    let settled_limit_kb = std::env::var("VIVYSHOT_RSS_SETTLED_LIMIT_KB")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(300_000);

    let width = 1920usize;
    let height = 1080usize;
    let stride = width * 4;
    let pixels = patterned_bgra(width, height, 123);
    let view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: pixels.as_ptr(),
        len: pixels.len(),
    };

    let mut peak_rss = baseline_rss;
    for iter in 0..20u32 {
        // SAFETY: pointers are valid for call duration and owned outputs are destroyed.
        unsafe {
            let mut encoded = vs_encoded_bytes {
                ptr: std::ptr::null_mut(),
                len: 0,
            };
            assert_eq!(
                vs_encode_bgra_image(view, VS_IMAGE_ENCODE_PNG, 92, &mut encoded),
                0
            );
            vs_encoded_bytes_destroy(&mut encoded);

            let mut cropped = vs_bgra_owned_image {
                width: 0,
                height: 0,
                stride: 0,
                ptr: std::ptr::null_mut(),
                len: 0,
            };
            let x = ((iter as usize) % 8) * 9;
            let y = ((iter as usize) % 6) * 11;
            assert_eq!(
                vs_bgra_crop(view, x as u32, y as u32, 1280, 720, &mut cropped),
                0
            );
            vs_bgra_owned_image_destroy(&mut cropped);

            let doc = vs_create_document_from_bgra(
                width as u32,
                height as u32,
                stride as u32,
                pixels.as_ptr(),
                pixels.len(),
            );
            assert!(!doc.is_null());
            let mut out = vec![0u8; pixels.len()];
            assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);
            vs_destroy_document(doc);
        }

        if let Some(rss) = process_rss_kb() {
            peak_rss = peak_rss.max(rss);
        }
    }

    std::thread::sleep(std::time::Duration::from_millis(120));
    let Some(final_rss) = process_rss_kb() else {
        eprintln!("skipping final RSS assertion: unable to read process RSS");
        return;
    };

    let peak_growth_kb = peak_rss.saturating_sub(baseline_rss);
    let settled_growth_kb = final_rss.saturating_sub(baseline_rss);
    assert!(
        peak_growth_kb <= peak_limit_kb,
        "peak RSS growth exceeded bound: baseline={}KB peak={}KB delta={}KB limit={}KB",
        baseline_rss,
        peak_rss,
        peak_growth_kb,
        peak_limit_kb
    );
    assert!(
        settled_growth_kb <= settled_limit_kb,
        "settled RSS growth exceeded bound: baseline={}KB final={}KB delta={}KB limit={}KB",
        baseline_rss,
        final_rss,
        settled_growth_kb,
        settled_limit_kb
    );
}

#[test]
fn undo_and_redo_affect_rendered_pixels() {
    // SAFETY: FFI pointers are managed and freed in this test.
    unsafe {
        let doc = make_doc(32, 24);
        assert!(!doc.is_null());

        let cmd = vs_rect_command {
            x: 4,
            y: 4,
            width: 10,
            height: 8,
            stroke_width: 2,
            r: 255,
            g: 0,
            b: 0,
            a: 255,
        };

        assert_eq!(vs_add_rect(doc, cmd), 0);

        let mut rendered = vec![0u8; 32 * 24 * 4];
        assert_eq!(
            vs_render_full(doc, rendered.as_mut_ptr(), rendered.len()),
            0
        );

        let idx = 4 * (32 * 4) + 4 * 4;
        assert_eq!(rendered[idx + 2], 255);

        assert_eq!(vs_undo(doc), 0);
        assert_eq!(
            vs_render_full(doc, rendered.as_mut_ptr(), rendered.len()),
            0
        );
        assert_eq!(rendered[idx + 2], 0);

        assert_eq!(vs_redo(doc), 0);
        assert_eq!(
            vs_render_full(doc, rendered.as_mut_ptr(), rendered.len()),
            0
        );
        assert_eq!(rendered[idx + 2], 255);

        vs_destroy_document(doc);
    }
}

#[test]
fn render_dirty_returns_changed_rect() {
    // SAFETY: FFI pointers are managed and freed in this test.
    unsafe {
        let doc = make_doc(64, 64);
        assert!(!doc.is_null());

        let mut out = make_base(64, 64);
        assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);

        let cmd = vs_rect_command {
            x: 10,
            y: 12,
            width: 20,
            height: 18,
            stroke_width: 3,
            r: 0,
            g: 255,
            b: 0,
            a: 255,
        };
        assert_eq!(vs_add_rect(doc, cmd), 0);

        let mut dirty = vs_dirty_rect {
            x: 0,
            y: 0,
            width: 0,
            height: 0,
        };
        let mut written = 0usize;

        assert_eq!(
            vs_render_dirty(
                doc,
                out.as_mut_ptr(),
                out.len(),
                &mut dirty,
                1,
                &mut written,
            ),
            0
        );

        assert_eq!(written, 1);
        assert_eq!(dirty.x, 10);
        assert_eq!(dirty.y, 12);
        assert_eq!(dirty.width, 20);
        assert_eq!(dirty.height, 18);

        let idx = 12 * (64 * 4) + 10 * 4;
        assert_eq!(out[idx + 1], 255);

        assert_eq!(
            vs_render_dirty(
                doc,
                out.as_mut_ptr(),
                out.len(),
                &mut dirty,
                1,
                &mut written,
            ),
            0
        );
        assert_eq!(written, 0);

        vs_destroy_document(doc);
    }
}

#[test]
fn remove_annotation_clears_rendered_pixels() {
    // SAFETY: FFI pointers are managed and freed in this test.
    unsafe {
        let doc = make_doc(48, 36);
        assert!(!doc.is_null());

        let cmd = vs_rect_command {
            x: 8,
            y: 6,
            width: 18,
            height: 12,
            stroke_width: 3,
            r: 255,
            g: 64,
            b: 0,
            a: 255,
        };
        assert_eq!(vs_add_rect(doc, cmd), 0);

        let mut out = make_base(48, 36);
        assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);

        let probe_idx = 6 * (48 * 4) + 8 * 4;
        assert_eq!(out[probe_idx + 2], 255);
        assert_eq!(out[probe_idx + 1], 64);

        assert_eq!(vs_remove_annotation(doc, 0), 0);

        let mut dirty = vs_dirty_rect {
            x: 0,
            y: 0,
            width: 0,
            height: 0,
        };
        let mut written = 0usize;
        assert_eq!(
            vs_render_dirty(
                doc,
                out.as_mut_ptr(),
                out.len(),
                &mut dirty,
                1,
                &mut written,
            ),
            0
        );
        assert_eq!(written, 1);
        assert_eq!(dirty.x, 8);
        assert_eq!(dirty.y, 6);
        assert_eq!(dirty.width, 18);
        assert_eq!(dirty.height, 12);

        assert_eq!(out[probe_idx + 2], 0);
        assert_eq!(out[probe_idx + 1], 0);

        vs_destroy_document(doc);
    }
}

#[test]
fn video_session_export_plan_tracks_counts_and_trim() {
    let config = vs_video_session_config {
        frame_rate: 60,
        capture_system_audio: true,
        capture_microphone: false,
        show_webcam: true,
        highlight_mouse_clicks: true,
        highlight_keystrokes: true,
    };
    let session = vs_video_session_create(config);
    assert!(!session.is_null());

    let key_a = b"CmdK";
    let key_b = b"Esc";

    // SAFETY: pointers remain valid for call duration and session handle is valid.
    unsafe {
        assert_eq!(
            vs_video_session_add_key_event(
                session,
                vs_video_key_event {
                    timestamp_ns: 10,
                    token_ptr: key_a.as_ptr(),
                    token_len: key_a.len(),
                },
            ),
            0
        );
        assert_eq!(
            vs_video_session_add_key_event(
                session,
                vs_video_key_event {
                    timestamp_ns: 20,
                    token_ptr: key_b.as_ptr(),
                    token_len: key_b.len(),
                },
            ),
            0
        );
        assert_eq!(
            vs_video_session_add_click_event(
                session,
                vs_video_click_event {
                    timestamp_ns: 30,
                    normalized_x: 0.35,
                    normalized_y: 0.82,
                    button: 0,
                },
            ),
            0
        );
        assert_eq!(vs_video_session_set_trim(session, 120, 980), 0);

        let mut plan = vs_video_export_plan {
            trim_start_ms: 0,
            trim_end_ms: 0,
            key_event_count: 0,
            click_event_count: 0,
            plan_mode: 0,
            include_audio: false,
            include_webcam: false,
            text_overlay_count: 0,
            overlay_item_count: 0,
            requires_intermediate_for_gif: false,
            needs_custom_compositor: false,
        };
        assert_eq!(vs_video_session_get_export_plan(session, &mut plan), 0);
        assert_eq!(plan.trim_start_ms, 120);
        assert_eq!(plan.trim_end_ms, 980);
        assert_eq!(plan.key_event_count, 2);
        assert_eq!(plan.click_event_count, 1);
        assert_eq!(plan.plan_mode, VS_VIDEO_PLAN_MODE_COMPOSITE_MP4);
        assert_eq!(plan.overlay_item_count, 2);
        assert!(plan.requires_intermediate_for_gif);
        assert_eq!(
            vs_video_session_set_export_context(
                session,
                vs_video_export_context {
                    source_has_audio: true,
                    source_has_webcam_asset: true,
                    audio_track_visible: false,
                    webcam_track_visible: true,
                    text_overlay_count: 3,
                },
            ),
            0
        );
        assert_eq!(vs_video_session_get_export_plan(session, &mut plan), 0);
        assert!(!plan.include_audio);
        assert!(plan.include_webcam);
        assert_eq!(plan.text_overlay_count, 3);
        assert_eq!(plan.overlay_item_count, 5);
        assert_eq!(plan.plan_mode, VS_VIDEO_PLAN_MODE_COMPOSITE_MP4);
        assert!(plan.requires_intermediate_for_gif);
        assert!(plan.needs_custom_compositor);

        vs_video_session_destroy(session);
    }
}

#[test]
fn stitch_estimate_detects_bottom_delta_for_shifted_frames() {
    let width = 80usize;
    let height = 56usize;
    let shift = 7usize;
    let stride = width * 4;

    let mut previous = vec![0u8; stride * height];
    for y in 0..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            previous[idx] = ((x * 3 + y * 5) % 251) as u8;
            previous[idx + 1] = ((x * 11 + y * 7) % 251) as u8;
            previous[idx + 2] = ((x * 13 + y * 17) % 251) as u8;
            previous[idx + 3] = 255;
        }
    }

    let mut current = vec![0u8; stride * height];
    for y in 0..(height - shift) {
        let src = (y + shift) * stride;
        let dst = y * stride;
        current[dst..dst + stride].copy_from_slice(&previous[src..src + stride]);
    }
    for y in (height - shift)..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            current[idx] = ((x * 19 + y * 23 + 29) % 251) as u8;
            current[idx + 1] = ((x * 31 + y * 7 + 41) % 251) as u8;
            current[idx + 2] = ((x * 5 + y * 37 + 53) % 251) as u8;
            current[idx + 3] = 255;
        }
    }

    let prev_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: previous.as_ptr(),
        len: previous.len(),
    };
    let curr_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: current.as_ptr(),
        len: current.len(),
    };
    let mut delta = vs_stitch_delta::default();

    // SAFETY: views point to valid slices for the full duration of the call.
    let status = unsafe {
        vs_stitch_estimate_delta_bgra(
            prev_view,
            curr_view,
            -1,
            shift as u32,
            true,
            false,
            &mut delta,
        )
    };
    assert_eq!(status, 0);
    assert_eq!(delta.rows, shift as u32);
    assert_eq!(delta.side, VS_STITCH_SIDE_BOTTOM);
}

#[test]
fn stitch_merge_places_segment_on_requested_side() {
    let width = 16usize;
    let base_height = 10usize;
    let segment_height = 3usize;
    let stride = width * 4;
    let base = solid_bgra(width, base_height, 10, 20, 30, 255);
    let segment = solid_bgra(width, segment_height, 200, 150, 100, 255);

    let base_view = vs_bgra_image_view {
        width: width as u32,
        height: base_height as u32,
        stride: stride as u32,
        ptr: base.as_ptr(),
        len: base.len(),
    };
    let segment_view = vs_bgra_image_view {
        width: width as u32,
        height: segment_height as u32,
        stride: stride as u32,
        ptr: segment.as_ptr(),
        len: segment.len(),
    };

    let mut merged_bottom = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut merged_top = merged_bottom;

    // SAFETY: views reference valid memory; owned output is destroyed before test returns.
    unsafe {
        assert_eq!(
            vs_stitch_merge_bgra(
                base_view,
                segment_view,
                VS_STITCH_SIDE_BOTTOM,
                &mut merged_bottom
            ),
            0
        );
        assert_eq!(
            vs_stitch_merge_bgra(base_view, segment_view, VS_STITCH_SIDE_TOP, &mut merged_top),
            0
        );

        let bottom_pixels = std::slice::from_raw_parts(merged_bottom.ptr, merged_bottom.len);
        assert_eq!(merged_bottom.height as usize, base_height + segment_height);
        assert_eq!(
            pixel_bgra(bottom_pixels, merged_bottom.stride as usize, 0, 0),
            (10, 20, 30, 255)
        );
        assert_eq!(
            pixel_bgra(bottom_pixels, merged_bottom.stride as usize, 0, base_height),
            (200, 150, 100, 255)
        );

        let top_pixels = std::slice::from_raw_parts(merged_top.ptr, merged_top.len);
        assert_eq!(merged_top.height as usize, base_height + segment_height);
        assert_eq!(
            pixel_bgra(top_pixels, merged_top.stride as usize, 0, 0),
            (200, 150, 100, 255)
        );
        assert_eq!(
            pixel_bgra(top_pixels, merged_top.stride as usize, 0, segment_height),
            (10, 20, 30, 255)
        );

        vs_bgra_owned_image_destroy(&mut merged_bottom);
        vs_bgra_owned_image_destroy(&mut merged_top);
    }
}

#[test]
fn bgra_crop_extracts_expected_region() {
    let width = 8usize;
    let height = 6usize;
    let stride = width * 4;
    let mut pixels = vec![0u8; stride * height];

    for y in 0..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            pixels[idx] = (x as u8).wrapping_mul(10);
            pixels[idx + 1] = (y as u8).wrapping_mul(20);
            pixels[idx + 2] = 140;
            pixels[idx + 3] = 255;
        }
    }

    let source_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: pixels.as_ptr(),
        len: pixels.len(),
    };
    let mut cropped = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };

    // SAFETY: view references valid source bytes and owned image is released below.
    unsafe {
        assert_eq!(vs_bgra_crop(source_view, 2, 1, 3, 4, &mut cropped), 0);
        assert_eq!(cropped.width, 3);
        assert_eq!(cropped.height, 4);
        let cropped_pixels = std::slice::from_raw_parts(cropped.ptr, cropped.len);
        assert_eq!(
            pixel_bgra(cropped_pixels, cropped.stride as usize, 0, 0),
            (20, 20, 140, 255)
        );
        assert_eq!(
            pixel_bgra(cropped_pixels, cropped.stride as usize, 2, 3),
            (40, 80, 140, 255)
        );
        vs_bgra_owned_image_destroy(&mut cropped);
    }
}

#[test]
fn selection_move_rect_clamps_to_bounds() {
    let current = vs_f32_rect {
        x: 50.0,
        y: 40.0,
        width: 120.0,
        height: 80.0,
    };
    let bounds = vs_f32_rect {
        x: 0.0,
        y: 0.0,
        width: 200.0,
        height: 160.0,
    };
    let mut out = vs_f32_rect::default();

    // SAFETY: out pointer is valid.
    let status = unsafe { vs_selection_move_rect(current, bounds, 200.0, -100.0, &mut out) };
    assert_eq!(status, 0);
    assert_eq!(out.x, 80.0);
    assert_eq!(out.y, 0.0);
    assert_eq!(out.width, 120.0);
    assert_eq!(out.height, 80.0);
}

#[test]
fn selection_resize_rect_applies_corner_and_minimums() {
    let start = vs_f32_rect {
        x: 60.0,
        y: 30.0,
        width: 120.0,
        height: 100.0,
    };
    let bounds = vs_f32_rect {
        x: 0.0,
        y: 0.0,
        width: 300.0,
        height: 200.0,
    };
    let mut out = vs_f32_rect::default();

    // SAFETY: out pointer is valid.
    let status = unsafe {
        vs_selection_resize_rect(
            start,
            bounds,
            VS_RESIZE_CORNER_TOP_LEFT,
            200.0,
            -90.0,
            80.0,
            60.0,
            &mut out,
        )
    };
    assert_eq!(status, 0);
    assert_eq!(out.width, 80.0);
    assert_eq!(out.height, 60.0);
    assert!(out.x >= 0.0);
    assert!(out.y >= 0.0);
}

#[test]
fn encode_bgra_image_outputs_png_and_jpeg_bytes() {
    let width = 5usize;
    let height = 4usize;
    let stride = width * 4;
    let pixels = solid_bgra(width, height, 12, 34, 56, 255);
    let source = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: pixels.as_ptr(),
        len: pixels.len(),
    };
    let mut png = vs_encoded_bytes {
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut jpeg = png;

    // SAFETY: source view is valid and owned buffers are released below.
    unsafe {
        assert_eq!(
            vs_encode_bgra_image(source, VS_IMAGE_ENCODE_PNG, 0, &mut png),
            0
        );
        assert!(png.len > 8);
        let png_bytes = std::slice::from_raw_parts(png.ptr, png.len);
        assert_eq!(png_bytes[0], 0x89);
        assert_eq!(png_bytes[1], b'P');
        assert_eq!(png_bytes[2], b'N');
        assert_eq!(png_bytes[3], b'G');

        assert_eq!(
            vs_encode_bgra_image(source, VS_IMAGE_ENCODE_JPEG, 90, &mut jpeg),
            0
        );
        assert!(jpeg.len > 4);
        let jpeg_bytes = std::slice::from_raw_parts(jpeg.ptr, jpeg.len);
        assert_eq!(jpeg_bytes[0], 0xFF);
        assert_eq!(jpeg_bytes[1], 0xD8);

        vs_encoded_bytes_destroy(&mut png);
        vs_encoded_bytes_destroy(&mut jpeg);
    }
}

#[test]
fn stitch_session_push_frame_and_merge_accumulates_segments() {
    let width = 96usize;
    let height = 68usize;
    let shift = 9usize;
    let stride = width * 4;

    let mut frame_a = vec![0u8; stride * height];
    for y in 0..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            frame_a[idx] = ((x * 5 + y * 13) % 251) as u8;
            frame_a[idx + 1] = ((x * 17 + y * 3) % 251) as u8;
            frame_a[idx + 2] = ((x * 7 + y * 11) % 251) as u8;
            frame_a[idx + 3] = 255;
        }
    }

    let mut frame_b = vec![0u8; stride * height];
    for y in 0..(height - shift) {
        let src = (y + shift) * stride;
        let dst = y * stride;
        frame_b[dst..dst + stride].copy_from_slice(&frame_a[src..src + stride]);
    }
    for y in (height - shift)..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            frame_b[idx] = ((x * 19 + y * 23 + 31) % 251) as u8;
            frame_b[idx + 1] = ((x * 29 + y * 7 + 41) % 251) as u8;
            frame_b[idx + 2] = ((x * 3 + y * 37 + 53) % 251) as u8;
            frame_b[idx + 3] = 255;
        }
    }

    let base_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_a.as_ptr(),
        len: frame_a.len(),
    };
    let first_view = base_view;
    let second_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_b.as_ptr(),
        len: frame_b.len(),
    };

    let session = vs_stitch_session_create();
    assert!(!session.is_null());

    let mut first_result = vs_stitch_session_result::default();
    let mut first_merged = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut second_result = first_result;
    let mut second_merged = first_merged;

    // SAFETY: pointers and handle are valid for call duration; owned output is destroyed below.
    unsafe {
        assert_eq!(vs_stitch_session_set_base_bgra(session, base_view, 1), 0);
        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                first_view,
                &mut first_result,
                &mut first_merged
            ),
            0
        );
        assert!(!first_result.accepted);
        assert!(first_merged.ptr.is_null());

        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                second_view,
                &mut second_result,
                &mut second_merged
            ),
            0
        );
        assert!(second_result.accepted);
        assert_eq!(second_result.side, VS_STITCH_SIDE_BOTTOM);
        assert_eq!(second_result.rows, shift as u32);
        assert_eq!(second_result.segment_count, 2);
        assert_eq!(second_merged.width as usize, width);
        assert_eq!(second_merged.height as usize, height + shift);

        vs_bgra_owned_image_destroy(&mut second_merged);
        vs_stitch_session_destroy(session);
    }
}

#[test]
fn stitch_session_locked_direction_rejects_relaxed_only_match() {
    let width = 112usize;
    let height = 80usize;
    let shift = 9usize;
    let stride = width * 4;

    let mut frame_a = vec![0u8; stride * height];
    for y in 0..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            let lane = (y / 4) % 7;
            let text_like = lane == 1 || lane == 2;
            let nibble = ((x / 6) + (y / 9)) % 5;
            let base = if text_like && nibble < 2 {
                178u8
            } else if lane == 0 {
                228u8
            } else {
                244u8
            };
            frame_a[idx] = base;
            frame_a[idx + 1] = base;
            frame_a[idx + 2] = base;
            frame_a[idx + 3] = 255;
        }
    }

    let mut frame_b = vec![0u8; stride * height];
    for y in 0..(height - shift) {
        let src = (y + shift) * stride;
        let dst = y * stride;
        frame_b[dst..dst + stride].copy_from_slice(&frame_a[src..src + stride]);
    }
    for y in (height - shift)..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            let stripe = ((x / 7) + y) % 6;
            let base = if stripe < 2 { 186u8 } else { 243u8 };
            frame_b[idx] = base;
            frame_b[idx + 1] = base;
            frame_b[idx + 2] = base;
            frame_b[idx + 3] = 255;
        }
    }

    let base_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_a.as_ptr(),
        len: frame_a.len(),
    };
    let first_view = base_view;
    let second_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_b.as_ptr(),
        len: frame_b.len(),
    };

    let session = vs_stitch_session_create();
    assert!(!session.is_null());

    let mut first_result = vs_stitch_session_result::default();
    let mut second_result = vs_stitch_session_result::default();
    let mut first_merged = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut second_merged = first_merged;

    // SAFETY: pointers and handle are valid for call duration; owned output is destroyed below.
    unsafe {
        assert_eq!(vs_stitch_session_set_base_bgra(session, base_view, 1), 0);
        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                first_view,
                &mut first_result,
                &mut first_merged
            ),
            0
        );
        assert!(!first_result.accepted);
        assert!(first_merged.ptr.is_null());

        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                second_view,
                &mut second_result,
                &mut second_merged
            ),
            0
        );
        assert!(second_result.accepted);
        assert_eq!(second_result.side, VS_STITCH_SIDE_BOTTOM);
        assert!(second_result.direction_locked);
        assert!(second_result.expected_rows >= 4);
    }

    let expected_rows = second_result.expected_rows;
    let mut candidate_frame: Option<Vec<u8>> = None;

    for seed in 0..2048u32 {
        let reverse_shift = 5usize + (seed as usize % 8);
        let mut candidate = vec![0u8; stride * height];

        for y in 0..(height - reverse_shift) {
            let src = y * stride;
            let dst = (y + reverse_shift) * stride;
            candidate[dst..dst + stride].copy_from_slice(&frame_b[src..src + stride]);
        }

        for y in 0..reverse_shift {
            for x in 0..width {
                let idx = y * stride + x * 4;
                let grain = ((x as u32 * 13 + y as u32 * 31 + seed * 17) % 19) as u8;
                let base = if grain < 3 { 182u8 } else { 246u8 };
                candidate[idx] = base;
                candidate[idx + 1] = base;
                candidate[idx + 2] = base;
                candidate[idx + 3] = 255;
            }
        }

        let candidate_view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: candidate.as_ptr(),
            len: candidate.len(),
        };

        let mut strict_delta = vs_stitch_delta::default();
        // SAFETY: views point to valid frame memory for call duration.
        let strict_status = unsafe {
            vs_stitch_estimate_delta_bgra(
                second_view,
                candidate_view,
                VS_STITCH_SIDE_BOTTOM as i32,
                expected_rows,
                true,
                false,
                &mut strict_delta,
            )
        };
        if strict_status == 0 {
            continue;
        }

        let mut relaxed_delta = vs_stitch_delta::default();
        // SAFETY: views point to valid frame memory for call duration.
        let relaxed_status = unsafe {
            vs_stitch_estimate_delta_bgra(
                second_view,
                candidate_view,
                VS_STITCH_SIDE_BOTTOM as i32,
                expected_rows,
                true,
                true,
                &mut relaxed_delta,
            )
        };

        if relaxed_status == 0 && relaxed_delta.rows >= 4 {
            candidate_frame = Some(candidate);
            break;
        }
    }

    let frame_c = candidate_frame.expect("failed to synthesize relaxed-only stitch candidate");
    let third_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_c.as_ptr(),
        len: frame_c.len(),
    };
    let mut third_result = vs_stitch_session_result::default();
    let mut third_merged = first_merged;

    // SAFETY: pointers and handle are valid for call duration; owned output is destroyed below.
    unsafe {
        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                third_view,
                &mut third_result,
                &mut third_merged
            ),
            0
        );
        assert!(!third_result.accepted);
        assert!(third_merged.ptr.is_null());

        if !second_merged.ptr.is_null() {
            vs_bgra_owned_image_destroy(&mut second_merged);
        }
        vs_stitch_session_destroy(session);
    }
}

#[test]
fn stitch_session_rejects_reverse_scroll_after_direction_lock() {
    let width = 104usize;
    let height = 78usize;
    let down_shift = 8usize;
    let up_shift = 6usize;
    let stride = width * 4;

    let mut frame_a = vec![0u8; stride * height];
    for y in 0..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            frame_a[idx] = ((x * 7 + y * 5) % 251) as u8;
            frame_a[idx + 1] = ((x * 11 + y * 3 + 17) % 251) as u8;
            frame_a[idx + 2] = ((x * 13 + y * 9 + 29) % 251) as u8;
            frame_a[idx + 3] = 255;
        }
    }

    let mut frame_b = vec![0u8; stride * height];
    for y in 0..(height - down_shift) {
        let src = (y + down_shift) * stride;
        let dst = y * stride;
        frame_b[dst..dst + stride].copy_from_slice(&frame_a[src..src + stride]);
    }
    for y in (height - down_shift)..height {
        for x in 0..width {
            let idx = y * stride + x * 4;
            frame_b[idx] = ((x * 19 + y * 23 + 31) % 251) as u8;
            frame_b[idx + 1] = ((x * 5 + y * 29 + 41) % 251) as u8;
            frame_b[idx + 2] = ((x * 3 + y * 7 + 53) % 251) as u8;
            frame_b[idx + 3] = 255;
        }
    }

    let mut frame_c = vec![0u8; stride * height];
    for y in 0..(height - up_shift) {
        let src = y * stride;
        let dst = (y + up_shift) * stride;
        frame_c[dst..dst + stride].copy_from_slice(&frame_b[src..src + stride]);
    }
    for y in 0..up_shift {
        for x in 0..width {
            let idx = y * stride + x * 4;
            frame_c[idx] = ((x * 2 + y * 17 + 67) % 251) as u8;
            frame_c[idx + 1] = ((x * 23 + y * 13 + 71) % 251) as u8;
            frame_c[idx + 2] = ((x * 31 + y * 11 + 79) % 251) as u8;
            frame_c[idx + 3] = 255;
        }
    }

    let base_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_a.as_ptr(),
        len: frame_a.len(),
    };
    let first_view = base_view;
    let second_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_b.as_ptr(),
        len: frame_b.len(),
    };
    let third_view = vs_bgra_image_view {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        ptr: frame_c.as_ptr(),
        len: frame_c.len(),
    };

    let session = vs_stitch_session_create();
    assert!(!session.is_null());

    let mut first_result = vs_stitch_session_result::default();
    let mut second_result = vs_stitch_session_result::default();
    let mut third_result = vs_stitch_session_result::default();
    let mut first_merged = vs_bgra_owned_image {
        width: 0,
        height: 0,
        stride: 0,
        ptr: std::ptr::null_mut(),
        len: 0,
    };
    let mut second_merged = first_merged;
    let mut third_merged = first_merged;
    let mut merged_snapshot = first_merged;

    // SAFETY: pointers and handle are valid for call duration; owned outputs are destroyed below.
    unsafe {
        assert_eq!(vs_stitch_session_set_base_bgra(session, base_view, 1), 0);
        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                first_view,
                &mut first_result,
                &mut first_merged
            ),
            0
        );
        assert!(!first_result.accepted);
        assert!(first_merged.ptr.is_null());

        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                second_view,
                &mut second_result,
                &mut second_merged
            ),
            0
        );
        assert!(second_result.accepted);
        assert_eq!(second_result.side, VS_STITCH_SIDE_BOTTOM);
        assert!(second_result.direction_locked);
        assert_eq!(second_result.segment_count, 2);
        assert_eq!(second_merged.height as usize, height + down_shift);

        assert_eq!(
            vs_stitch_session_push_frame_and_merge_bgra(
                session,
                third_view,
                &mut third_result,
                &mut third_merged
            ),
            0
        );
        assert!(!third_result.accepted);
        assert!(third_result.direction_locked);
        assert_eq!(third_result.segment_count, 2);
        assert!(third_merged.ptr.is_null());

        assert_eq!(vs_stitch_session_get_merged_image_bgra(session, &mut merged_snapshot), 0);
        assert_eq!(merged_snapshot.width as usize, width);
        assert_eq!(merged_snapshot.height as usize, height + down_shift);

        if !second_merged.ptr.is_null() {
            vs_bgra_owned_image_destroy(&mut second_merged);
        }
        if !merged_snapshot.ptr.is_null() {
            vs_bgra_owned_image_destroy(&mut merged_snapshot);
        }
        vs_stitch_session_destroy(session);
    }
}

#[test]
fn timeline_visible_clips_reports_total_when_output_capacity_is_small() {
    let tl = vs_timeline_create(10_000, 1920, 1080);
    assert!(!tl.is_null());

    // SAFETY: timeline handle is valid and destroyed at end of test.
    unsafe {
        assert_eq!(vs_timeline_add_track(tl, 0), 0);

        let mut clip_ids = [0u32; 3];
        for (idx, start) in [0u32, 1_000, 2_000].iter().enumerate() {
            assert_eq!(
                vs_timeline_add_clip(tl, 0, *start, *start + 5_000, 0, &mut clip_ids[idx]),
                0
            );
        }

        let mut out = [zero_clip_info(); 1];
        let mut written = 0u32;
        assert_eq!(
            vs_timeline_get_visible_clips_at(
                tl,
                2_500,
                out.as_mut_ptr(),
                out.len() as u32,
                &mut written
            ),
            0
        );
        assert_eq!(written, 3);
        assert_eq!(out[0].id, clip_ids[0]);

        vs_timeline_destroy(tl);
    }
}

#[test]
fn timeline_get_clip_text_reports_full_length_with_small_buffer() {
    let tl = vs_timeline_create(8_000, 1280, 720);
    assert!(!tl.is_null());

    // SAFETY: timeline handle is valid and destroyed at end of test.
    unsafe {
        assert_eq!(vs_timeline_add_track(tl, 3), 0);
        let mut clip_id = 0u32;
        assert_eq!(vs_timeline_add_clip(tl, 0, 0, 6_000, 3, &mut clip_id), 0);

        let text = "A".repeat(8_192);
        let bytes = text.as_bytes();
        assert_eq!(
            vs_timeline_set_clip_text(tl, 0, clip_id, bytes.as_ptr(), bytes.len() as u32),
            0
        );

        let mut buffer = vec![0u8; 16];
        let mut written = 0u32;
        assert_eq!(
            vs_timeline_get_clip_text(
                tl,
                0,
                clip_id,
                buffer.as_mut_ptr(),
                buffer.len() as u32,
                &mut written
            ),
            0
        );
        assert_eq!(written as usize, bytes.len());
        assert_eq!(&buffer[..], &bytes[..buffer.len()]);

        vs_timeline_destroy(tl);
    }
}

#[test]
fn timeline_derive_export_context_counts_only_visible_tracks() {
    let tl = vs_timeline_create(9_000, 1280, 720);
    assert!(!tl.is_null());

    // SAFETY: handle is valid and destroyed at end of test.
    unsafe {
        assert_eq!(vs_timeline_add_track(tl, 0), 0); // video
        assert_eq!(vs_timeline_add_track(tl, 2), 0); // audio
        assert_eq!(vs_timeline_add_track(tl, 1), 0); // webcam
        assert_eq!(vs_timeline_add_track(tl, 3), 0); // text

        let mut clip_id = 0u32;
        assert_eq!(vs_timeline_add_clip(tl, 1, 0, 8_000, 2, &mut clip_id), 0);
        assert_eq!(vs_timeline_add_clip(tl, 2, 0, 8_000, 1, &mut clip_id), 0);
        assert_eq!(vs_timeline_add_clip(tl, 3, 0, 2_000, 3, &mut clip_id), 0);
        assert_eq!(
            vs_timeline_add_clip(tl, 3, 3_000, 5_000, 3, &mut clip_id),
            0
        );
        assert_eq!(vs_timeline_set_track_visible(tl, 2, false), 0); // webcam hidden

        let mut context = vs_video_export_context {
            source_has_audio: false,
            source_has_webcam_asset: false,
            audio_track_visible: false,
            webcam_track_visible: false,
            text_overlay_count: 0,
        };
        assert_eq!(
            vs_timeline_derive_export_context(tl, true, true, &mut context),
            0
        );
        assert!(context.source_has_audio);
        assert!(context.source_has_webcam_asset);
        assert!(context.audio_track_visible);
        assert!(!context.webcam_track_visible);
        assert_eq!(context.text_overlay_count, 2);

        vs_timeline_destroy(tl);
    }
}

#[test]
fn timeline_export_text_clip_refs_are_filtered_and_sorted() {
    let tl = vs_timeline_create(9_000, 1280, 720);
    assert!(!tl.is_null());

    // SAFETY: handle is valid and destroyed at end of test.
    unsafe {
        assert_eq!(vs_timeline_add_track(tl, 0), 0); // video
        assert_eq!(vs_timeline_add_track(tl, 1), 0); // webcam
        assert_eq!(vs_timeline_add_track(tl, 3), 0); // text

        let mut clip_id = 0u32;
        assert_eq!(vs_timeline_add_clip(tl, 1, 0, 8_000, 1, &mut clip_id), 0);
        assert_eq!(
            vs_timeline_add_clip(tl, 2, 3_000, 4_000, 3, &mut clip_id),
            0
        );
        assert_eq!(
            vs_timeline_add_clip(tl, 2, 1_000, 2_000, 3, &mut clip_id),
            0
        );

        let mut webcam_visible = false;
        assert_eq!(
            vs_timeline_is_webcam_track_visible_for_export(tl, &mut webcam_visible),
            0
        );
        assert!(webcam_visible);

        let mut written = 0u32;
        assert_eq!(
            vs_timeline_get_text_export_clips(tl, std::ptr::null_mut(), 0, &mut written),
            0
        );
        assert_eq!(written, 2);

        let mut clips = vec![vs_timeline_text_export_clip_info::default(); written as usize];
        assert_eq!(
            vs_timeline_get_text_export_clips(
                tl,
                clips.as_mut_ptr(),
                clips.len() as u32,
                &mut written
            ),
            0
        );
        assert_eq!(written, 2);
        assert_eq!(clips[0].start_ms, 1_000);
        assert_eq!(clips[1].start_ms, 3_000);

        assert_eq!(vs_timeline_set_track_visible(tl, 1, false), 0);
        webcam_visible = true;
        assert_eq!(
            vs_timeline_is_webcam_track_visible_for_export(tl, &mut webcam_visible),
            0
        );
        assert!(!webcam_visible);

        vs_timeline_destroy(tl);
    }
}

#[test]
fn video_compute_export_plan_respects_context_and_trim() {
    let context = vs_video_export_context {
        source_has_audio: true,
        source_has_webcam_asset: true,
        audio_track_visible: false,
        webcam_track_visible: true,
        text_overlay_count: 2,
    };
    let mut plan = vs_video_export_plan {
        trim_start_ms: 0,
        trim_end_ms: 0,
        key_event_count: 0,
        click_event_count: 0,
        plan_mode: 0,
        include_audio: false,
        include_webcam: false,
        text_overlay_count: 0,
        overlay_item_count: 0,
        requires_intermediate_for_gif: false,
        needs_custom_compositor: false,
    };

    // SAFETY: output pointer is valid for the duration of call.
    let status = unsafe { vs_video_compute_export_plan(120, 880, 3, 1, context, &mut plan) };
    assert_eq!(status, 0);
    assert_eq!(plan.trim_start_ms, 120);
    assert_eq!(plan.trim_end_ms, 880);
    assert_eq!(plan.key_event_count, 3);
    assert_eq!(plan.click_event_count, 1);
    assert!(!plan.include_audio);
    assert!(plan.include_webcam);
    assert_eq!(plan.text_overlay_count, 2);
    assert_eq!(plan.overlay_item_count, 5);
    assert_eq!(plan.plan_mode, VS_VIDEO_PLAN_MODE_COMPOSITE_MP4);
    assert!(plan.requires_intermediate_for_gif);
    assert!(plan.needs_custom_compositor);
}

#[test]
fn input_normalization_helpers_are_deterministic() {
    let mut token_bytes = [0u8; 64];
    let mut written = 0u32;
    let chars = b"k";

    // SAFETY: pointers are valid for the duration of each FFI call.
    unsafe {
        assert_eq!(
            vs_normalize_key_token(
                40,
                VS_KEY_MOD_COMMAND | VS_KEY_MOD_SHIFT,
                chars.as_ptr(),
                chars.len() as u32,
                token_bytes.as_mut_ptr(),
                token_bytes.len() as u32,
                &mut written,
            ),
            0
        );
    }
    let token = std::str::from_utf8(&token_bytes[..written as usize]).unwrap();
    assert_eq!(token, "⌘⇧K");

    // SAFETY: pointers are valid and lengths are bounded by local buffers.
    let duplicate = unsafe {
        vs_key_event_is_duplicate(
            7,
            token_bytes.as_ptr(),
            written,
            7,
            token_bytes.as_ptr(),
            written,
        )
    };
    assert!(duplicate);

    let mut out_x = 0.0f32;
    let mut out_y = 0.0f32;
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_normalize_click_point(-0.25, 1.25, &mut out_x, &mut out_y),
            0
        );
    }
    assert!(approx_eq(out_x, 0.0, 0.0001));
    assert!(approx_eq(out_y, 1.0, 0.0001));

    assert!(vs_click_event_is_duplicate(
        11, 0, 0.42, 0.58, 11, 0, 0.42005, 0.57995, 0.001,
    ));
}

#[test]
fn geometry_helpers_round_trip_rects_and_deltas() {
    let destination = vs_f32_rect {
        x: 100.0,
        y: 200.0,
        width: 640.0,
        height: 360.0,
    };
    let view_rect = vs_f32_rect {
        x: 180.0,
        y: 250.0,
        width: 220.0,
        height: 90.0,
    };
    let mut image_rect = vs_f32_rect::default();

    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_view_rect_to_image_rect(view_rect, destination, 1920, 1080, &mut image_rect),
            0
        );
    }
    assert!(image_rect.width > 0.0);
    assert!(image_rect.height > 0.0);

    let mut round_trip = vs_f32_rect::default();
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_image_rect_to_view_rect(image_rect, destination, 1920, 1080, &mut round_trip),
            0
        );
    }

    assert!(approx_eq(round_trip.x, view_rect.x, 1.0));
    assert!(approx_eq(round_trip.y, view_rect.y, 1.0));
    assert!(approx_eq(round_trip.width, view_rect.width, 1.0));
    assert!(approx_eq(round_trip.height, view_rect.height, 1.0));

    let mut delta_image = vs_f32_point::default();
    let mut delta_view = vs_f32_point::default();
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_view_delta_to_image_delta(12.0, -8.0, destination, 1920, 1080, &mut delta_image),
            0
        );
        assert_eq!(
            vs_image_delta_to_view_delta(
                delta_image.x,
                delta_image.y,
                destination,
                1920,
                1080,
                &mut delta_view
            ),
            0
        );
    }
    assert!(approx_eq(delta_view.x, 12.0, 0.01));
    assert!(approx_eq(delta_view.y, -8.0, 0.01));
}

#[test]
fn trim_and_gif_policy_helpers_apply_limits() {
    let mut start = 0u32;
    let mut end = 0u32;
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_normalize_trim_range(
                1_000,
                950,
                960,
                100,
                VS_TRIM_HANDLE_END,
                &mut start,
                &mut end
            ),
            0
        );
    }
    assert_eq!(start, 860);
    assert_eq!(end, 960);

    let mut plan = vs_gif_export_plan::default();
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_build_gif_export_plan(0, 1_000, 12.0, 9_999, &mut plan),
            0
        );
    }
    assert_eq!(plan.start_ms, 0);
    assert_eq!(plan.end_ms, 1_000);
    assert_eq!(plan.frame_count, 12);
    assert_eq!(plan.max_dimension, 2_048);
    assert_eq!(plan.frame_delay_ms, 83);

    let mut first_t = 0u32;
    let mut last_t = 0u32;
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(vs_gif_frame_time_ms(plan, 0, &mut first_t), 0);
        assert_eq!(
            vs_gif_frame_time_ms(plan, plan.frame_count - 1, &mut last_t),
            0
        );
    }
    assert_eq!(first_t, plan.start_ms);
    assert_eq!(last_t, plan.end_ms);
}

#[test]
fn stitch_autoscroll_policy_flips_once_after_threshold() {
    let mut state = vs_stitch_autoscroll_state::default();
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(vs_stitch_autoscroll_reset(&mut state), 0);
    }
    assert_eq!(state.direction_sign, -1);
    assert_eq!(state.no_motion_ticks, 0);
    assert!(!state.did_flip_direction);

    for _ in 0..4 {
        let mut next = vs_stitch_autoscroll_state::default();
        // SAFETY: output pointer is valid.
        unsafe {
            assert_eq!(
                vs_stitch_autoscroll_update(true, false, false, 4, state, &mut next),
                0
            );
        }
        state = next;
    }
    assert_eq!(state.direction_sign, 1);
    assert_eq!(state.no_motion_ticks, 0);
    assert!(state.did_flip_direction);
}

#[test]
fn timeline_bootstrap_and_auto_text_track_import_work() {
    let tl = vs_timeline_create(7_500, 1280, 720);
    assert!(!tl.is_null());

    // SAFETY: handle is valid and destroyed at end of test.
    unsafe {
        assert_eq!(vs_timeline_bootstrap_capture_tracks(tl, true, true), 0);

        let mut tracks = [vs_timeline_track_info {
            kind: 0,
            visible: false,
            clip_count: 0,
        }; 6];
        let mut track_written = 0u32;
        assert_eq!(
            vs_timeline_get_tracks(
                tl,
                tracks.as_mut_ptr(),
                tracks.len() as u32,
                &mut track_written
            ),
            0
        );
        assert_eq!(track_written, 3);
        assert_eq!(tracks[0].kind, 0);
        assert_eq!(tracks[1].kind, 2);
        assert_eq!(tracks[2].kind, 1);
        assert_eq!(tracks[0].clip_count, 1);

        let text = "  Hello Rust  ";
        let mut clip_id = 0u32;
        assert_eq!(
            vs_timeline_add_text_clip_auto_track(
                tl,
                500,
                1_800,
                text.as_ptr(),
                text.len() as u32,
                &mut clip_id,
            ),
            0
        );
        assert!(clip_id > 0);

        track_written = 0;
        assert_eq!(
            vs_timeline_get_tracks(
                tl,
                tracks.as_mut_ptr(),
                tracks.len() as u32,
                &mut track_written
            ),
            0
        );
        let text_track_idx = tracks
            .iter()
            .take(track_written as usize)
            .position(|track| track.kind == 3)
            .unwrap() as u32;

        let mut clip_written = 0u32;
        let mut clips = [zero_clip_info(); 4];
        assert_eq!(
            vs_timeline_get_clips(
                tl,
                text_track_idx,
                clips.as_mut_ptr(),
                clips.len() as u32,
                &mut clip_written
            ),
            0
        );
        assert_eq!(clip_written, 1);
        assert_eq!(clips[0].id, clip_id);
        assert_eq!(clips[0].start_ms, 500);
        assert_eq!(clips[0].end_ms, 1_800);

        let mut text_buffer = [0u8; 32];
        let mut text_written = 0u32;
        assert_eq!(
            vs_timeline_get_clip_text(
                tl,
                text_track_idx,
                clip_id,
                text_buffer.as_mut_ptr(),
                text_buffer.len() as u32,
                &mut text_written,
            ),
            0
        );
        let restored_text = std::str::from_utf8(&text_buffer[..text_written as usize]).unwrap();
        assert_eq!(restored_text, "Hello Rust");

        vs_timeline_destroy(tl);
    }
}
