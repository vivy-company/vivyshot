use vivyshot_core::{
    vs_click_event_is_duplicate, vs_core_abi_version, vs_key_event_is_duplicate,
    vs_normalize_click_point, vs_normalize_key_token, vs_video_click_event,
    vs_video_compute_export_plan, vs_video_derive_export_decision, vs_video_export_context,
    vs_video_export_decision, vs_video_export_plan, vs_video_key_event,
    vs_video_session_add_click_event, vs_video_session_add_key_event, vs_video_session_config,
    vs_video_session_create, vs_video_session_deserialize_json, vs_video_session_destroy,
    vs_video_session_get_export_plan, vs_video_session_serialize_json,
    vs_video_session_set_export_context, vs_video_session_set_trim, VS_CORE_ABI_VERSION_MAJOR,
    VS_CORE_ABI_VERSION_MINOR, VS_CORE_ABI_VERSION_PATCH, VS_STATUS_INVALID_ARGUMENT,
    VS_STATUS_NULL_POINTER, VS_VIDEO_EXPORT_TARGET_GIF, VS_VIDEO_EXPORT_TARGET_MP4,
};

fn sample_config() -> vs_video_session_config {
    vs_video_session_config {
        frame_rate: 60,
        capture_system_audio: true,
        capture_microphone: false,
        show_webcam: true,
        highlight_mouse_clicks: true,
        highlight_keystrokes: true,
    }
}

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
fn video_session_serialization_roundtrip_preserves_plan() {
    let session = vs_video_session_create(sample_config());
    assert!(!session.is_null());

    let key = b"CmdK";
    // SAFETY: pointers remain valid during calls and session handle is valid.
    unsafe {
        assert_eq!(
            vs_video_session_add_key_event(
                session,
                vs_video_key_event {
                    timestamp_ns: 10,
                    token_ptr: key.as_ptr(),
                    token_len: key.len(),
                },
            ),
            0
        );

        assert_eq!(
            vs_video_session_add_click_event(
                session,
                vs_video_click_event {
                    timestamp_ns: 22,
                    normalized_x: 0.35,
                    normalized_y: 0.65,
                    button: 1,
                },
            ),
            0
        );

        assert_eq!(vs_video_session_set_trim(session, 120, 980), 0);
        assert_eq!(
            vs_video_session_set_export_context(
                session,
                vs_video_export_context {
                    source_has_audio: true,
                    source_has_webcam_asset: true,
                    audio_track_visible: false,
                    webcam_track_visible: true,
                    text_overlay_count: 2,
                },
            ),
            0
        );

        let mut expected = blank_plan();
        assert_eq!(vs_video_session_get_export_plan(session, &mut expected), 0);
        assert_eq!(expected.key_event_count, 1);
        assert_eq!(expected.click_event_count, 1);
        assert_eq!(expected.overlay_item_count, 3);
        assert!(expected.needs_custom_compositor);

        let mut json = vec![0u8; 4096];
        let mut written = 0u32;
        assert_eq!(
            vs_video_session_serialize_json(
                session,
                json.as_mut_ptr(),
                json.len() as u32,
                &mut written,
            ),
            0
        );
        assert!(written > 0);

        let restored = vs_video_session_deserialize_json(json.as_ptr(), written);
        assert!(!restored.is_null());

        let mut restored_plan = blank_plan();
        assert_eq!(
            vs_video_session_get_export_plan(restored, &mut restored_plan),
            0
        );
        assert_eq!(restored_plan.trim_start_ms, expected.trim_start_ms);
        assert_eq!(restored_plan.trim_end_ms, expected.trim_end_ms);
        assert_eq!(
            restored_plan.overlay_item_count,
            expected.overlay_item_count
        );
        assert_eq!(restored_plan.plan_mode, expected.plan_mode);

        vs_video_session_destroy(restored);
        vs_video_session_destroy(session);
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
