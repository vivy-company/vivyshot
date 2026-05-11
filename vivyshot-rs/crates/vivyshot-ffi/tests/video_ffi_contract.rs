use vivyshot_core::{
    vs_click_event_is_duplicate, vs_core_abi_version, vs_key_event_is_duplicate,
    vs_normalize_click_point, vs_normalize_key_token, vs_video_best_export_preset,
    vs_video_best_save_container, vs_video_compute_export_plan,
    vs_video_compute_overlay_clip_window, vs_video_derive_export_decision, vs_video_export_context,
    vs_video_export_decision, vs_video_export_plan, vs_video_key_overlay_label_layout,
    vs_video_overlay_clip_window, vs_video_overlay_label_layout, vs_video_project_add_click_event,
    vs_video_project_add_key_event, vs_video_project_create_from_recording,
    vs_video_project_deserialize_json, vs_video_project_destroy, vs_video_project_export_options,
    vs_video_project_export_plan, vs_video_project_pro_requirement,
    vs_video_project_pro_requirement_result, vs_video_project_push_keystroke_placement,
    vs_video_project_push_webcam_placement, vs_video_project_recording_info, vs_video_project_rect,
    vs_video_project_render_item, vs_video_project_render_plan, vs_video_project_render_plan_query,
    vs_video_project_render_plan_text, vs_video_project_serialize_json,
    vs_video_project_set_keystroke_overlay, vs_video_project_set_webcam_overlay,
    vs_video_text_overlay_label_layout, VS_CORE_ABI_VERSION_MAJOR, VS_CORE_ABI_VERSION_MINOR,
    VS_CORE_ABI_VERSION_PATCH, VS_STATUS_BUFFER_TOO_SMALL, VS_STATUS_INVALID_ARGUMENT,
    VS_STATUS_NULL_POINTER, VS_VIDEO_EXPORT_TARGET_GIF, VS_VIDEO_EXPORT_TARGET_MP4,
    VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS,
};

fn blank_plan() -> vs_video_export_plan {
    vs_video_export_plan {
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
    }
}

fn blank_decision() -> vs_video_export_decision {
    vs_video_export_decision {
        use_custom_compositor: false,
        requires_intermediate_for_gif: false,
        include_audio: false,
        include_webcam: false,
    }
}

#[test]
fn core_abi_version_contract_matches_exported_constants() {
    let mut major = 0u32;
    let mut minor = 0u32;
    let mut patch = 0u32;

    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(vs_core_abi_version(&mut major, &mut minor, &mut patch), 0);
    }

    assert_eq!(major, VS_CORE_ABI_VERSION_MAJOR);
    assert_eq!(minor, VS_CORE_ABI_VERSION_MINOR);
    assert_eq!(patch, VS_CORE_ABI_VERSION_PATCH);

    // SAFETY: null pointer check should fail with stable status code.
    unsafe {
        assert_eq!(
            vs_core_abi_version(std::ptr::null_mut(), &mut minor, &mut patch),
            VS_STATUS_NULL_POINTER
        );
    }
}

#[test]
fn video_export_decision_contract_validates_target_and_pointer() {
    let mut plan = blank_plan();
    plan.plan_mode = 1;
    plan.include_audio = true;
    plan.include_webcam = true;
    let mut decision = blank_decision();

    // SAFETY: output pointer is valid for successful calls.
    unsafe {
        assert_eq!(
            vs_video_derive_export_decision(VS_VIDEO_EXPORT_TARGET_MP4, plan, &mut decision),
            0
        );
    }
    assert!(decision.use_custom_compositor);
    assert!(decision.requires_intermediate_for_gif);
    assert!(decision.include_audio);
    assert!(decision.include_webcam);

    decision = blank_decision();
    // SAFETY: output pointer is valid for successful calls.
    unsafe {
        assert_eq!(
            vs_video_derive_export_decision(VS_VIDEO_EXPORT_TARGET_GIF, plan, &mut decision),
            0
        );
    }
    assert!(decision.use_custom_compositor);
    assert!(decision.requires_intermediate_for_gif);

    // SAFETY: invalid target/null pointer checks.
    unsafe {
        assert_eq!(
            vs_video_derive_export_decision(255, plan, &mut decision),
            VS_STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            vs_video_derive_export_decision(VS_VIDEO_EXPORT_TARGET_MP4, plan, std::ptr::null_mut()),
            VS_STATUS_NULL_POINTER
        );
    }
}

#[test]
fn video_project_contract_covers_render_export_pro_and_snapshot() {
    let project = vs_video_project_create_from_recording(vs_video_project_recording_info {
        duration_ms: 5_000,
        width: 1_920,
        height: 1_080,
        frame_rate: 30,
        has_audio: true,
        has_webcam_asset: true,
        has_microphone_audio: true,
    });
    assert!(!project.is_null());

    unsafe {
        assert_eq!(
            vs_video_project_set_webcam_overlay(project, true, 1, 2, 5),
            0
        );
        assert_eq!(
            vs_video_project_push_webcam_placement(
                project,
                0,
                vs_video_project_rect {
                    x: 0.70,
                    y: 0.10,
                    width: 0.20,
                    height: 0.12,
                },
            ),
            0
        );
        assert_eq!(
            vs_video_project_set_keystroke_overlay(project, true, 1, 1),
            0
        );
        assert_eq!(
            vs_video_project_push_keystroke_placement(
                project,
                0,
                vs_video_project_rect {
                    x: 0.25,
                    y: 0.75,
                    width: 0.50,
                    height: 0.12,
                },
            ),
            0
        );
        let key = "⌘K".as_bytes();
        assert_eq!(
            vs_video_project_add_key_event(project, 1_000, key.as_ptr(), key.len() as u32),
            0
        );
        assert_eq!(
            vs_video_project_add_click_event(project, 1_000, 1.2, -1.0, 0),
            0
        );

        let query = vs_video_project_render_plan_query {
            time_ms: 1_000,
            render_width: 1_920,
            render_height: 1_080,
            target: 1,
        };
        let mut written = 0u32;
        assert_eq!(
            vs_video_project_render_plan(project, query, std::ptr::null_mut(), 0, &mut written),
            VS_STATUS_BUFFER_TOO_SMALL
        );
        assert_eq!(written, 2);
        let mut items = vec![vs_video_project_render_item::default(); written as usize];
        assert_eq!(
            vs_video_project_render_plan(
                project,
                query,
                items.as_mut_ptr(),
                items.len() as u32,
                &mut written,
            ),
            0
        );
        assert_eq!(items[0].kind, 1);
        assert!((items[0].width - items[0].height).abs() < 0.001);
        assert_eq!(items[1].kind, 2);

        let mut text_written = 0u32;
        assert_eq!(
            vs_video_project_render_plan_text(
                project,
                query,
                std::ptr::null_mut(),
                0,
                &mut text_written,
            ),
            VS_STATUS_BUFFER_TOO_SMALL
        );
        let mut text = vec![0u8; text_written as usize];
        assert_eq!(
            vs_video_project_render_plan_text(
                project,
                query,
                text.as_mut_ptr(),
                text.len() as u32,
                &mut text_written,
            ),
            0
        );
        assert_eq!(std::str::from_utf8(&text).unwrap(), "⌘K");

        let mut plan = blank_plan();
        assert_eq!(vs_video_project_export_plan(project, &mut plan), 0);
        assert!(plan.needs_custom_compositor);
        assert_eq!(plan.key_event_count, 1);
        assert_eq!(plan.click_event_count, 1);

        let mut requirement = vs_video_project_pro_requirement_result::default();
        assert_eq!(
            vs_video_project_pro_requirement(
                project,
                vs_video_project_export_options {
                    target: VS_VIDEO_EXPORT_TARGET_MP4,
                    codec: 1,
                    frame_rate: 1,
                    quality: 1,
                    bitrate: 2,
                    includes_baked_transition: false,
                },
                &mut requirement,
            ),
            0
        );
        assert_ne!(requirement.reasons_mask & (1 << 0), 0);
        assert_ne!(requirement.reasons_mask & (1 << 1), 0);
        assert_ne!(requirement.reasons_mask & (1 << 2), 0);

        let mut json_written = 0u32;
        assert_eq!(
            vs_video_project_serialize_json(project, std::ptr::null_mut(), 0, &mut json_written),
            VS_STATUS_BUFFER_TOO_SMALL
        );
        let mut json = vec![0u8; json_written as usize];
        assert_eq!(
            vs_video_project_serialize_json(
                project,
                json.as_mut_ptr(),
                json.len() as u32,
                &mut json_written,
            ),
            0
        );
        let restored = vs_video_project_deserialize_json(json.as_ptr(), json_written);
        assert!(!restored.is_null());
        vs_video_project_destroy(restored);

        assert_eq!(
            vs_video_project_set_keystroke_overlay(project, true, 255, 0),
            VS_STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            vs_video_project_export_plan(std::ptr::null(), &mut plan),
            VS_STATUS_NULL_POINTER
        );

        vs_video_project_destroy(project);
    }
}

#[test]
fn video_compute_export_plan_validates_trim_bounds() {
    let mut plan = blank_plan();

    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_video_compute_export_plan(
                900,
                100,
                2,
                1,
                vs_video_export_context {
                    source_has_audio: true,
                    source_has_webcam_asset: false,
                    audio_track_visible: true,
                    webcam_track_visible: true,
                    text_overlay_count: 0,
                },
                &mut plan,
            ),
            -2
        );

        assert_eq!(
            vs_video_compute_export_plan(
                100,
                900,
                2,
                1,
                vs_video_export_context {
                    source_has_audio: true,
                    source_has_webcam_asset: false,
                    audio_track_visible: true,
                    webcam_track_visible: true,
                    text_overlay_count: 0,
                },
                &mut plan,
            ),
            0
        );
    }
    assert_eq!(plan.key_event_count, 2);
    assert_eq!(plan.click_event_count, 1);
    assert_eq!(plan.plan_mode, 1);
}

#[test]
fn overlay_policy_ffi_contracts_are_deterministic() {
    let mut key = vs_video_overlay_label_layout::default();
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_video_key_overlay_label_layout(1920.0, 1080.0, 6, &mut key),
            0
        );
    }
    assert!((key.width - 108.0).abs() < 0.001);
    assert!((key.height - 58.0).abs() < 0.001);

    let mut text = vs_video_overlay_label_layout::default();
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_video_text_overlay_label_layout(1920.0, 1080.0, 20, &mut text),
            0
        );
    }
    assert!((text.width - 280.0).abs() < 0.001);
    assert!((text.height - 62.0).abs() < 0.001);

    let mut window = vs_video_overlay_clip_window::default();
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_video_compute_overlay_clip_window(
                3.0,
                4.0,
                1.5,
                VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS,
                &mut window
            ),
            0
        );
    }
    assert!((window.start_seconds - 1.5).abs() < 0.0001);
    assert!((window.end_seconds - 2.5).abs() < 0.0001);
    assert!((window.fade_duration_seconds - 1.0).abs() < 0.0001);
}

#[test]
fn key_and_click_normalization_helpers_are_consistent() {
    let chars = b"k";
    let mut out = [0u8; 64];
    let mut written = 0u32;

    // SAFETY: pointers are valid local buffers.
    unsafe {
        assert_eq!(
            vs_normalize_key_token(
                40,
                (1 << 0) | (1 << 1),
                chars.as_ptr(),
                chars.len() as u32,
                out.as_mut_ptr(),
                out.len() as u32,
                &mut written,
            ),
            0
        );
    }

    let token = std::str::from_utf8(&out[..written as usize]).unwrap();
    assert_eq!(token, "⌘⇧K");

    let delete_char = [0x7fu8];
    written = 0;
    // SAFETY: pointers are valid local buffers.
    unsafe {
        assert_eq!(
            vs_normalize_key_token(
                51,
                0,
                delete_char.as_ptr(),
                delete_char.len() as u32,
                out.as_mut_ptr(),
                out.len() as u32,
                &mut written,
            ),
            0
        );
    }
    let token = std::str::from_utf8(&out[..written as usize]).unwrap();
    assert_eq!(token, "⌫");

    // SAFETY: pointers are valid and lengths are bounded.
    let dup =
        unsafe { vs_key_event_is_duplicate(77, out.as_ptr(), written, 77, out.as_ptr(), written) };
    assert!(dup);

    let mut x = 0.0f32;
    let mut y = 0.0f32;
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(vs_normalize_click_point(-0.1, 1.3, &mut x, &mut y), 0);
    }
    assert_eq!(x, 0.0);
    assert_eq!(y, 1.0);

    assert!(vs_click_event_is_duplicate(
        88, 0, 0.42, 0.58, 88, 0, 0.42005, 0.57995, 0.001,
    ));
}

#[test]
fn new_video_policy_helpers_keep_safe_fallbacks() {
    let mut container = 255u8;
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_video_best_save_container(1, false, true, &mut container),
            0
        );
    }
    assert_eq!(container, 1);

    let mut preset = 255u8;
    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(vs_video_best_export_preset(1, 1, 0, &mut preset), 0);
    }
    assert_eq!(preset, 0);

    // SAFETY: invalid-argument path for no supported save container.
    unsafe {
        assert_eq!(
            vs_video_best_save_container(0, false, false, &mut container),
            VS_STATUS_INVALID_ARGUMENT
        );
    }
}
