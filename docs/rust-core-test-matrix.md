# Rust Core Test Matrix

This matrix tracks contract-level coverage for `vivyshot-rs` APIs.

## Document APIs

- `vs_core_version`
- `vs_create_document_from_bgra` / `vs_destroy_document`
- `vs_add_rect` / `vs_add_ellipse` / `vs_add_path`
- `vs_list_annotations` / `vs_move_annotation` / `vs_resize_annotation` / `vs_remove_annotation`
- `vs_copy_annotations_affine`
- `vs_render_full` / `vs_render_dirty`

Coverage file: `vivyshot-rs/tests/document_ffi_contract.rs`

## Video Session + Input APIs

- `vs_video_session_create` / `vs_video_session_destroy`
- `vs_video_session_add_key_event` / `vs_video_session_add_click_event`
- `vs_video_session_set_trim` / `vs_video_session_set_export_context`
- `vs_video_compute_export_plan` / `vs_video_session_get_export_plan`
- `vs_video_session_serialize_json` / `vs_video_session_deserialize_json`
- `vs_normalize_key_token` / `vs_key_event_is_duplicate`
- `vs_normalize_click_point` / `vs_click_event_is_duplicate`

Coverage file: `vivyshot-rs/tests/video_ffi_contract.rs`

## Geometry + Policy APIs

- `vs_selection_move_rect` / `vs_selection_resize_rect`
- `vs_view_rect_to_image_rect` / `vs_image_rect_to_view_rect`
- `vs_view_delta_to_image_delta` / `vs_image_delta_to_view_delta`
- `vs_viewport_clamp_pan_offset`
- `vs_quantize_image_rect` / `vs_quantize_image_point` / `vs_quantize_rgba`
- `vs_normalize_trim_range`
- `vs_build_gif_export_plan` / `vs_gif_frame_time_ms`

Coverage files:
- `vivyshot-rs/tests/geometry_ffi_contract.rs`
- `vivyshot-rs/tests/property_geometry.rs`

## Stitch + Image APIs

- `vs_bgra_crop`
- `vs_encode_bgra_image` / `vs_encoded_bytes_destroy`
- `vs_stitch_estimate_delta_bgra`
- `vs_stitch_merge_bgra`
- `vs_stitch_session_*`
- `vs_stitch_autoscroll_reset` / `vs_stitch_autoscroll_update`

Coverage file: `vivyshot-rs/tests/stitch_ffi_contract.rs`

## Timeline APIs

- `vs_timeline_create` / `vs_timeline_destroy`
- `vs_timeline_add_track` / `vs_timeline_remove_track` / `vs_timeline_reorder_track`
- `vs_timeline_bootstrap_capture_tracks`
- `vs_timeline_add_text_clip_auto_track`
- `vs_timeline_add_clip` / `vs_timeline_move_clip` / `vs_timeline_resize_clip` / `vs_timeline_remove_clip`
- `vs_timeline_set_clip_text` / `vs_timeline_set_clip_text_style`
- `vs_timeline_set_track_visible`
- `vs_timeline_get_tracks` / `vs_timeline_get_clips` / `vs_timeline_get_visible_clips_at`
- `vs_timeline_get_clip_text`
- `vs_timeline_set_clip_zoom_scale` / `vs_timeline_get_clip_zoom_scale`
- `vs_timeline_undo` / `vs_timeline_redo`
- `vs_timeline_get_video_info`
- `vs_timeline_derive_export_context`

Coverage file: `vivyshot-rs/tests/timeline_ffi_contract.rs`
