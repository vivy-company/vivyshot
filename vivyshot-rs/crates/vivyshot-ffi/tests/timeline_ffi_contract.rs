mod common;

use common::{zero_clip_info, zero_track_info};
use vivyshot_core::{
    vs_timeline_add_clip, vs_timeline_add_text_clip_auto_track, vs_timeline_add_track,
    vs_timeline_bootstrap_capture_tracks, vs_timeline_create, vs_timeline_derive_export_context,
    vs_timeline_destroy, vs_timeline_get_clip_text, vs_timeline_get_clip_zoom_scale,
    vs_timeline_get_clips, vs_timeline_get_tracks, vs_timeline_get_video_info,
    vs_timeline_get_visible_clips_at, vs_timeline_move_clip, vs_timeline_redo,
    vs_timeline_remove_clip, vs_timeline_remove_track, vs_timeline_reorder_track,
    vs_timeline_resize_clip, vs_timeline_set_clip_text, vs_timeline_set_clip_text_style,
    vs_timeline_set_clip_zoom_scale, vs_timeline_set_track_visible, vs_timeline_split_clip,
    vs_timeline_undo, vs_video_export_context, VS_STATUS_INVALID_ARGUMENT,
};

#[test]
fn timeline_bootstrap_and_text_import_are_stable() {
    let tl = vs_timeline_create(8_000, 1280, 720);
    assert!(!tl.is_null());

    // SAFETY: handle is valid and destroyed in this scope.
    unsafe {
        assert_eq!(vs_timeline_bootstrap_capture_tracks(tl, true, true), 0);

        let mut tracks = [zero_track_info(); 8];
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

        let text = "  Portable text clip  ";
        let mut clip_id = 0u32;
        assert_eq!(
            vs_timeline_add_text_clip_auto_track(
                tl,
                500,
                2_500,
                text.as_ptr(),
                text.len() as u32,
                &mut clip_id,
            ),
            0
        );
        assert!(clip_id > 0);

        assert_eq!(
            vs_timeline_get_tracks(
                tl,
                tracks.as_mut_ptr(),
                tracks.len() as u32,
                &mut track_written
            ),
            0
        );

        let text_track = tracks
            .iter()
            .take(track_written as usize)
            .position(|track| track.kind == 3)
            .unwrap() as u32;

        let mut clips = [zero_clip_info(); 4];
        let mut clip_written = 0u32;
        assert_eq!(
            vs_timeline_get_clips(
                tl,
                text_track,
                clips.as_mut_ptr(),
                clips.len() as u32,
                &mut clip_written
            ),
            0
        );
        assert_eq!(clip_written, 1);
        assert_eq!(clips[0].id, clip_id);
        assert_eq!(clips[0].start_ms, 500);
        assert_eq!(clips[0].end_ms, 2_500);

        let mut text_buffer = [0u8; 64];
        let mut text_written = 0u32;
        assert_eq!(
            vs_timeline_get_clip_text(
                tl,
                text_track,
                clip_id,
                text_buffer.as_mut_ptr(),
                text_buffer.len() as u32,
                &mut text_written,
            ),
            0
        );
        let restored = std::str::from_utf8(&text_buffer[..text_written as usize]).unwrap();
        assert_eq!(restored, "Portable text clip");

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
        assert!(context.audio_track_visible);
        assert!(context.webcam_track_visible);
        assert_eq!(context.text_overlay_count, 1);

        vs_timeline_destroy(tl);
    }
}

#[test]
fn timeline_clip_ops_visibility_and_history_behave() {
    let tl = vs_timeline_create(12_000, 1920, 1080);
    assert!(!tl.is_null());

    // SAFETY: handle is valid and destroyed in this scope.
    unsafe {
        assert_eq!(vs_timeline_add_track(tl, 0), 0);
        assert_eq!(vs_timeline_add_track(tl, 3), 0);
        assert_eq!(vs_timeline_add_track(tl, 6), 0);

        let mut video_clip = 0u32;
        assert_eq!(
            vs_timeline_add_clip(tl, 0, 0, 10_000, 0, &mut video_clip),
            0
        );
        let mut text_clip = 0u32;
        assert_eq!(
            vs_timeline_add_clip(tl, 1, 2_000, 6_000, 3, &mut text_clip),
            0
        );
        let mut zoom_clip = 0u32;
        assert_eq!(
            vs_timeline_add_clip(tl, 2, 1_000, 9_000, 6, &mut zoom_clip),
            0
        );

        let label = "Timeline text";
        assert_eq!(
            vs_timeline_set_clip_text(tl, 1, text_clip, label.as_ptr(), label.len() as u32),
            0
        );
        assert_eq!(
            vs_timeline_set_clip_text_style(tl, 1, text_clip, 20.0, 0xFFAA33FF, 0x00000000),
            0
        );

        assert_eq!(vs_timeline_move_clip(tl, 1, text_clip, 3_000), 0);
        assert_eq!(vs_timeline_resize_clip(tl, 1, text_clip, 3_000, 7_000), 0);

        assert_eq!(vs_timeline_set_clip_zoom_scale(tl, 2, zoom_clip, 1.25), 0);
        let mut scale = 0.0f32;
        assert_eq!(
            vs_timeline_get_clip_zoom_scale(tl, 2, zoom_clip, &mut scale),
            0
        );
        assert!((scale - 1.25).abs() < 0.001);

        assert_eq!(vs_timeline_set_track_visible(tl, 1, true), 0);

        let mut visible = [zero_clip_info(); 1];
        let mut visible_written = 0u32;
        assert_eq!(
            vs_timeline_get_visible_clips_at(
                tl,
                4_000,
                visible.as_mut_ptr(),
                visible.len() as u32,
                &mut visible_written
            ),
            0
        );
        assert!(visible_written >= 2);

        assert_eq!(vs_timeline_remove_clip(tl, 1, text_clip), 0);
        assert_eq!(vs_timeline_undo(tl), 0);
        assert_eq!(vs_timeline_redo(tl), 0);

        assert_eq!(vs_timeline_reorder_track(tl, 1, 0), 0);
        assert_eq!(vs_timeline_remove_track(tl, 1), 0);

        let mut duration = 0u32;
        let mut width = 0u32;
        let mut height = 0u32;
        assert_eq!(
            vs_timeline_get_video_info(tl, &mut duration, &mut width, &mut height),
            0
        );
        assert_eq!(duration, 12_000);
        assert_eq!(width, 1920);
        assert_eq!(height, 1080);

        vs_timeline_destroy(tl);
    }
}

#[test]
fn stale_timeline_handle_is_rejected_after_destroy() {
    let tl = vs_timeline_create(2_000, 640, 480);
    assert!(!tl.is_null());

    // SAFETY: handle is valid for destroy; stale-handle call checks rejection.
    unsafe {
        vs_timeline_destroy(tl);
        assert_eq!(vs_timeline_add_track(tl, 0), VS_STATUS_INVALID_ARGUMENT);
    }
}

#[test]
fn timeline_split_clip_produces_two_clips_and_undoes() {
    let tl = vs_timeline_create(10_000, 1920, 1080);
    assert!(!tl.is_null());

    unsafe {
        assert_eq!(vs_timeline_add_track(tl, 0), 0);

        let mut clip_id = 0u32;
        assert_eq!(vs_timeline_add_clip(tl, 0, 0, 10_000, 0, &mut clip_id), 0);

        let mut new_clip_id = 0u32;
        assert_eq!(
            vs_timeline_split_clip(tl, 0, clip_id, 5_000, &mut new_clip_id),
            0
        );
        assert!(new_clip_id > 0);
        assert_ne!(new_clip_id, clip_id);

        // Should now have two clips
        let mut clips = [zero_clip_info(); 4];
        let mut clip_written = 0u32;
        assert_eq!(
            vs_timeline_get_clips(
                tl,
                0,
                clips.as_mut_ptr(),
                clips.len() as u32,
                &mut clip_written
            ),
            0
        );
        assert_eq!(clip_written, 2);

        // Find original and new clip
        let orig = clips.iter().find(|c| c.id == clip_id).unwrap();
        let split = clips.iter().find(|c| c.id == new_clip_id).unwrap();
        assert_eq!(orig.start_ms, 0);
        assert_eq!(orig.end_ms, 5_000);
        assert_eq!(split.start_ms, 5_000);
        assert_eq!(split.end_ms, 10_000);

        // Undo should restore single clip
        assert_eq!(vs_timeline_undo(tl), 0);
        clip_written = 0;
        assert_eq!(
            vs_timeline_get_clips(
                tl,
                0,
                clips.as_mut_ptr(),
                clips.len() as u32,
                &mut clip_written
            ),
            0
        );
        assert_eq!(clip_written, 1);
        assert_eq!(clips[0].id, clip_id);
        assert_eq!(clips[0].start_ms, 0);
        assert_eq!(clips[0].end_ms, 10_000);

        // Redo should re-apply split
        assert_eq!(vs_timeline_redo(tl), 0);
        clip_written = 0;
        assert_eq!(
            vs_timeline_get_clips(
                tl,
                0,
                clips.as_mut_ptr(),
                clips.len() as u32,
                &mut clip_written
            ),
            0
        );
        assert_eq!(clip_written, 2);

        vs_timeline_destroy(tl);
    }
}
