#ifndef VIVYSHOT_CORE_H
#define VIVYSHOT_CORE_H

#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define VS_VIDEO_EXPORT_TARGET_MP4 0

#define VS_VIDEO_EXPORT_TARGET_GIF 1

#define VS_STATS_EVENT_SCREENSHOT_CAPTURED DOMAIN_STATS_EVENT_SCREENSHOT_CAPTURED

#define VS_STATS_EVENT_SCREENSHOT_SESSION_COMPLETED DOMAIN_STATS_EVENT_SCREENSHOT_SESSION_COMPLETED

#define VS_STATS_EVENT_RECORDING_COMPLETED DOMAIN_STATS_EVENT_RECORDING_COMPLETED

#define VS_CORE_ABI_VERSION_MAJOR 1

#define VS_CORE_ABI_VERSION_MINOR 1

#define VS_CORE_ABI_VERSION_PATCH 0

#define VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS 0.05

#define VS_VIDEO_TEXT_MIN_FADE_DURATION_SECONDS 0.10

#define VS_VIDEO_KEY_FADE_DURATION_SECONDS 0.95

#define VS_VIDEO_KEY_FADE_IN_KEYTIME 0.10

#define VS_VIDEO_KEY_FADE_HOLD_KEYTIME 0.78

#define VS_VIDEO_TEXT_FADE_IN_KEYTIME 0.08

#define VS_VIDEO_TEXT_FADE_HOLD_KEYTIME 0.92

#define VS_STATUS_OK 0

#define VS_STATUS_NO_CHANGE 1

#define VS_STATUS_NULL_POINTER -1

#define VS_STATUS_INVALID_ARGUMENT -2

#define VS_STATUS_REJECTED -3

#define VS_STATUS_BUFFER_TOO_SMALL -4

#define VS_STATUS_NOT_FOUND -5

typedef struct vs_rect_command {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  uint32_t stroke_width;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_rect_command;

typedef struct vs_ellipse_command {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  uint32_t stroke_width;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_ellipse_command;

typedef struct vs_line_command {
  int32_t x0;
  int32_t y0;
  int32_t x1;
  int32_t y1;
  uint32_t stroke_width;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_line_command;

typedef struct vs_point_i32 {
  int32_t x;
  int32_t y;
} vs_point_i32;

typedef struct vs_path_style {
  uint32_t stroke_width;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_path_style;

typedef struct vs_arrow_command {
  int32_t x0;
  int32_t y0;
  int32_t x1;
  int32_t y1;
  uint32_t stroke_width;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_arrow_command;

typedef struct vs_text_command {
  int32_t x;
  int32_t y;
  uint32_t font_px;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_text_command;

typedef struct vs_pixelate_rect_command {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  uint32_t block_size;
} vs_pixelate_rect_command;

typedef struct vs_blur_rect_command {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  uint32_t radius;
} vs_blur_rect_command;

typedef struct vs_annotation_info {
  uint32_t index;
  uint32_t kind;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
} vs_annotation_info;

typedef struct vs_dirty_rect {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
} vs_dirty_rect;

typedef struct vs_video_session_config {
  uint32_t frame_rate;
  bool capture_system_audio;
  bool capture_microphone;
  bool show_webcam;
  bool highlight_mouse_clicks;
  bool highlight_keystrokes;
} vs_video_session_config;

typedef struct vs_video_key_event {
  uint64_t timestamp_ns;
  const uint8_t *token_ptr;
  uintptr_t token_len;
} vs_video_key_event;

typedef struct vs_video_click_event {
  uint64_t timestamp_ns;
  float normalized_x;
  float normalized_y;
  uint32_t button;
} vs_video_click_event;

typedef struct vs_video_export_context {
  bool source_has_audio;
  bool source_has_webcam_asset;
  bool audio_track_visible;
  bool webcam_track_visible;
  uint32_t text_overlay_count;
} vs_video_export_context;

typedef struct vs_video_export_plan {
  uint32_t trim_start_ms;
  uint32_t trim_end_ms;
  uint32_t key_event_count;
  uint32_t click_event_count;
  uint8_t plan_mode;
  bool include_audio;
  bool include_webcam;
  uint32_t text_overlay_count;
  uint32_t overlay_item_count;
  bool requires_intermediate_for_gif;
  bool needs_custom_compositor;
} vs_video_export_plan;

typedef struct vs_video_export_decision {
  bool use_custom_compositor;
  bool requires_intermediate_for_gif;
  bool include_audio;
  bool include_webcam;
} vs_video_export_decision;

typedef struct vs_video_overlay_label_layout {
  float width;
  float height;
  float y;
  float font_size;
} vs_video_overlay_label_layout;

typedef struct vs_video_overlay_clip_window {
  double start_seconds;
  double end_seconds;
  double fade_duration_seconds;
} vs_video_overlay_clip_window;

typedef struct vs_stats_event {
  uint8_t event_type;
  uint8_t reserved0[3];
  int32_t timezone_offset_minutes;
  int64_t occurred_at_ms;
  int64_t bytes_produced;
  int64_t duration_ms;
  int64_t screenshot_completion_duration_ms;
  const uint8_t *event_key_ptr;
  uintptr_t event_key_len;
  const uint8_t *capture_id_ptr;
  uintptr_t capture_id_len;
} vs_stats_event;

typedef struct vs_stats_day_key {
  int32_t year;
  uint8_t month;
  uint8_t day;
  uint8_t reserved;
} vs_stats_day_key;

typedef struct vs_stats_summary {
  int64_t total_screenshots_captured;
  int64_t total_recordings_completed;
  int64_t total_recorded_duration_ms;
  int64_t total_screenshot_completion_duration_ms;
  int64_t completed_screenshot_session_count;
  int64_t average_screenshot_editor_completion_duration_ms;
  int64_t total_capture_bytes_produced;
  int32_t current_capture_streak_days;
  int32_t best_capture_streak_days;
  int32_t active_capture_days;
  struct vs_stats_day_key first_capture_day;
  bool has_first_capture_day;
  struct vs_stats_day_key last_capture_day;
  bool has_last_capture_day;
  struct vs_stats_day_key most_active_day;
  bool has_most_active_day;
  int64_t most_active_day_score;
} vs_stats_summary;

typedef struct vs_stats_daily_bucket {
  struct vs_stats_day_key day;
  int32_t screenshot_count;
  int32_t recording_count;
  int64_t recorded_duration_ms;
  int64_t capture_bytes_produced;
  int64_t first_capture_at_ms;
  bool has_first_capture_at_ms;
  int64_t last_capture_at_ms;
  bool has_last_capture_at_ms;
} vs_stats_daily_bucket;

typedef struct vs_gif_export_plan {
  uint32_t start_ms;
  uint32_t end_ms;
  float frame_rate;
  uint32_t frame_count;
  uint32_t max_dimension;
  uint32_t frame_delay_ms;
} vs_gif_export_plan;

typedef struct vs_stitch_autoscroll_state {
  int32_t direction_sign;
  uint32_t no_motion_ticks;
  bool did_flip_direction;
} vs_stitch_autoscroll_state;

typedef struct vs_bgra_image_view {
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  const uint8_t *ptr;
  uintptr_t len;
} vs_bgra_image_view;

typedef struct vs_bgra_owned_image {
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  uint8_t *ptr;
  uintptr_t len;
} vs_bgra_owned_image;

typedef struct vs_stitch_session_result {
  bool accepted;
  uint32_t rows;
  uint8_t side;
  float score;
  bool direction_locked;
  uint32_t expected_rows;
  uint32_t segment_count;
  int32_t scroll_direction_sign;
} vs_stitch_session_result;

typedef struct vs_stitch_delta {
  uint32_t rows;
  uint8_t side;
  float score;
} vs_stitch_delta;

typedef struct vs_f32_rect {
  float x;
  float y;
  float width;
  float height;
} vs_f32_rect;

typedef struct vs_f32_point {
  float x;
  float y;
} vs_f32_point;

typedef struct vs_i32_rect {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
} vs_i32_rect;

typedef struct vs_rgba8 {
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} vs_rgba8;

typedef struct vs_encoded_bytes {
  uint8_t *ptr;
  uintptr_t len;
} vs_encoded_bytes;

typedef struct vs_timeline_track_info {
  uint8_t kind;
  bool visible;
  uint32_t clip_count;
} vs_timeline_track_info;

typedef struct vs_timeline_text_export_clip_info {
  uint32_t track_index;
  uint32_t clip_id;
  uint32_t start_ms;
  uint32_t end_ms;
} vs_timeline_text_export_clip_info;

typedef struct vs_clip_transform {
  float x;
  float y;
  float width;
  float height;
  float rotation;
  float opacity;
} vs_clip_transform;

typedef struct vs_timeline_clip_info {
  uint32_t id;
  uint32_t track_index;
  uint32_t start_ms;
  uint32_t end_ms;
  uint8_t kind;
  struct vs_clip_transform transform;
} vs_timeline_clip_info;

const char *vs_core_version(void);

int32_t vs_core_abi_version(uint32_t *out_major, uint32_t *out_minor, uint32_t *out_patch);

void *vs_create_document_from_bgra(uint32_t width,
                                   uint32_t height,
                                   uint32_t stride,
                                   const uint8_t *ptr,
                                   uintptr_t len);

void vs_destroy_document(void *doc);

int32_t vs_add_rect(void *doc, struct vs_rect_command cmd);

int32_t vs_add_filled_rect(void *doc, struct vs_rect_command cmd);

int32_t vs_add_ellipse(void *doc, struct vs_ellipse_command cmd);

int32_t vs_add_filled_ellipse(void *doc, struct vs_ellipse_command cmd);

int32_t vs_add_line(void *doc, struct vs_line_command cmd);

int32_t vs_add_path(void *doc,
                    const struct vs_point_i32 *points_ptr,
                    uintptr_t points_len,
                    struct vs_path_style style);

int32_t vs_add_arrow(void *doc, struct vs_arrow_command cmd);

int32_t vs_add_text(void *doc,
                    const uint8_t *text_ptr,
                    uintptr_t text_len,
                    struct vs_text_command cmd);

int32_t vs_add_pixelate_rect(void *doc, struct vs_pixelate_rect_command cmd);

int32_t vs_add_blur_rect(void *doc, struct vs_blur_rect_command cmd);

int32_t vs_undo(void *doc);

int32_t vs_redo(void *doc);

int32_t vs_list_annotations(void *doc,
                            struct vs_annotation_info *out_ptr,
                            uintptr_t out_cap,
                            uintptr_t *out_written_ptr);

int32_t vs_move_annotation(void *doc, uint32_t index, int32_t dx, int32_t dy);

int32_t vs_remove_annotation(void *doc, uint32_t index);

int32_t vs_resize_annotation(void *doc,
                             uint32_t index,
                             int32_t x,
                             int32_t y,
                             int32_t width,
                             int32_t height);

int32_t vs_copy_annotations_affine(void *dst_doc,
                                   const void *src_doc,
                                   float scale_x,
                                   float scale_y,
                                   float translate_x,
                                   float translate_y);

int32_t vs_render_full(void *doc, uint8_t *out_ptr, uintptr_t out_len);

int32_t vs_render_dirty(void *doc,
                        uint8_t *out_ptr,
                        uintptr_t out_len,
                        struct vs_dirty_rect *dirty_rects_ptr,
                        uintptr_t dirty_rects_cap,
                        uintptr_t *dirty_rects_written_ptr);

void *vs_video_session_create(struct vs_video_session_config config);

int32_t vs_video_session_add_key_event(void *session, struct vs_video_key_event event);

int32_t vs_video_session_add_click_event(void *session, struct vs_video_click_event event);

int32_t vs_video_session_set_trim(void *session, uint32_t start_ms, uint32_t end_ms);

int32_t vs_video_session_set_export_context(void *session, struct vs_video_export_context context);

int32_t vs_video_compute_export_plan(uint32_t trim_start_ms,
                                     uint32_t trim_end_ms,
                                     uint32_t key_event_count,
                                     uint32_t click_event_count,
                                     struct vs_video_export_context context,
                                     struct vs_video_export_plan *out_plan);

int32_t vs_video_derive_export_decision(uint8_t target,
                                        struct vs_video_export_plan plan,
                                        struct vs_video_export_decision *out_decision);

int32_t vs_video_key_overlay_label_layout(float render_width,
                                          float render_height,
                                          uint32_t char_count,
                                          struct vs_video_overlay_label_layout *out_layout);

int32_t vs_video_text_overlay_label_layout(float render_width,
                                           float render_height,
                                           uint32_t char_count,
                                           struct vs_video_overlay_label_layout *out_layout);

int32_t vs_video_compute_overlay_clip_window(double clip_start_seconds,
                                             double clip_end_seconds,
                                             double trim_start_seconds,
                                             double min_visible_seconds,
                                             struct vs_video_overlay_clip_window *out_window);

int32_t vs_video_session_get_export_plan(void *session, struct vs_video_export_plan *out_plan);

void vs_video_session_destroy(void *session);

int32_t vs_normalize_key_token(uint16_t key_code,
                               uint32_t modifiers,
                               const uint8_t *chars_ptr,
                               uint32_t chars_len,
                               uint8_t *out_ptr,
                               uint32_t out_cap,
                               uint32_t *out_written);

bool vs_key_event_is_duplicate(uint64_t last_timestamp_ns,
                               const uint8_t *last_token_ptr,
                               uint32_t last_token_len,
                               uint64_t timestamp_ns,
                               const uint8_t *token_ptr,
                               uint32_t token_len);

int32_t vs_normalize_click_point(float normalized_x,
                                 float normalized_y,
                                 float *out_x,
                                 float *out_y);

bool vs_click_event_is_duplicate(uint64_t last_timestamp_ns,
                                 uint32_t last_button,
                                 float last_x,
                                 float last_y,
                                 uint64_t timestamp_ns,
                                 uint32_t button,
                                 float x,
                                 float y,
                                 float epsilon);

int32_t vs_video_session_serialize_json(const void *session,
                                        uint8_t *out_ptr,
                                        uint32_t out_cap,
                                        uint32_t *out_written);

void *vs_video_session_deserialize_json(const uint8_t *json_ptr, uint32_t json_len);

void *vs_stats_session_create(void);

void vs_stats_session_destroy(void *handle);

int32_t vs_stats_session_ingest_event(void *handle, struct vs_stats_event event, bool *out_applied);

int32_t vs_stats_session_get_summary(const void *handle, struct vs_stats_summary *out_summary);

int32_t vs_stats_session_get_recent_daily_buckets(const void *handle,
                                                  uint32_t day_count,
                                                  struct vs_stats_daily_bucket *out_ptr,
                                                  uint32_t out_cap,
                                                  uint32_t *out_written);

int32_t vs_stats_session_get_all_daily_buckets(const void *handle,
                                               struct vs_stats_daily_bucket *out_ptr,
                                               uint32_t out_cap,
                                               uint32_t *out_written);

int32_t vs_stats_session_reset(void *handle);

int32_t vs_stats_session_serialize_json(const void *handle,
                                        uint8_t *out_ptr,
                                        uint32_t out_len,
                                        uint32_t *out_written);

void *vs_stats_session_deserialize_json(const uint8_t *json_ptr, uint32_t json_len);

void *vs_stitch_session_create(void);

void vs_stitch_session_destroy(void *session);

int32_t vs_stitch_session_reset(void *session, uint32_t base_segment_count);

int32_t vs_normalize_trim_range(uint32_t duration_ms,
                                uint32_t start_ms,
                                uint32_t end_ms,
                                uint32_t min_gap_ms,
                                uint8_t active_handle,
                                uint32_t *out_start_ms,
                                uint32_t *out_end_ms);

int32_t vs_build_gif_export_plan(uint32_t start_ms,
                                 uint32_t end_ms,
                                 float preferred_fps,
                                 uint32_t max_dimension,
                                 struct vs_gif_export_plan *out_plan);

int32_t vs_gif_frame_time_ms(struct vs_gif_export_plan plan, uint32_t index, uint32_t *out_time_ms);

int32_t vs_stitch_autoscroll_reset(struct vs_stitch_autoscroll_state *out_state);

int32_t vs_stitch_autoscroll_update(bool enabled,
                                    bool direction_locked,
                                    bool did_merge,
                                    uint32_t threshold_ticks,
                                    struct vs_stitch_autoscroll_state state,
                                    struct vs_stitch_autoscroll_state *out_state);

int32_t vs_stitch_session_set_base_bgra(void *session,
                                        struct vs_bgra_image_view base,
                                        uint32_t base_segment_count);

int32_t vs_stitch_session_get_merged_image_bgra(void *session,
                                                struct vs_bgra_owned_image *out_image);

int32_t vs_stitch_session_push_frame_bgra(void *session,
                                          struct vs_bgra_image_view frame,
                                          struct vs_stitch_session_result *out_result);

int32_t vs_stitch_session_push_frame_and_merge_bgra(void *session,
                                                    struct vs_bgra_image_view frame,
                                                    struct vs_stitch_session_result *out_result,
                                                    struct vs_bgra_owned_image *out_image);

int32_t vs_stitch_estimate_delta_bgra(struct vs_bgra_image_view previous,
                                      struct vs_bgra_image_view current,
                                      int32_t preferred_side,
                                      uint32_t expected_rows,
                                      bool has_expected_rows,
                                      bool relaxed,
                                      struct vs_stitch_delta *out_delta);

int32_t vs_stitch_merge_bgra(struct vs_bgra_image_view base,
                             struct vs_bgra_image_view segment,
                             uint8_t side,
                             struct vs_bgra_owned_image *out_image);

int32_t vs_bgra_crop(struct vs_bgra_image_view source,
                     uint32_t x,
                     uint32_t y,
                     uint32_t width,
                     uint32_t height,
                     struct vs_bgra_owned_image *out_image);

int32_t vs_view_rect_to_image_rect(struct vs_f32_rect view_rect,
                                   struct vs_f32_rect destination_rect,
                                   uint32_t image_width,
                                   uint32_t image_height,
                                   struct vs_f32_rect *out_rect);

int32_t vs_image_rect_to_view_rect(struct vs_f32_rect image_rect,
                                   struct vs_f32_rect destination_rect,
                                   uint32_t image_width,
                                   uint32_t image_height,
                                   struct vs_f32_rect *out_rect);

int32_t vs_view_delta_to_image_delta(float delta_x,
                                     float delta_y,
                                     struct vs_f32_rect destination_rect,
                                     uint32_t image_width,
                                     uint32_t image_height,
                                     struct vs_f32_point *out_point);

int32_t vs_image_delta_to_view_delta(float delta_x,
                                     float delta_y,
                                     struct vs_f32_rect destination_rect,
                                     uint32_t image_width,
                                     uint32_t image_height,
                                     struct vs_f32_point *out_point);

int32_t vs_viewport_clamp_pan_offset(float bounds_width,
                                     float bounds_height,
                                     uint32_t image_width,
                                     uint32_t image_height,
                                     float zoom_scale,
                                     float overscroll,
                                     float candidate_x,
                                     float candidate_y,
                                     struct vs_f32_point *out_point);

int32_t vs_quantize_image_rect(uint32_t image_width,
                               uint32_t image_height,
                               struct vs_f32_rect rect,
                               struct vs_i32_rect *out_rect);

int32_t vs_quantize_image_point(uint32_t image_width,
                                uint32_t image_height,
                                float x,
                                float y,
                                int32_t *out_x,
                                int32_t *out_y);

int32_t vs_quantize_rgba(float r, float g, float b, float a, struct vs_rgba8 *out_color);

int32_t vs_selection_move_rect(struct vs_f32_rect current,
                               struct vs_f32_rect bounds,
                               float delta_x,
                               float delta_y,
                               struct vs_f32_rect *out_rect);

int32_t vs_selection_resize_rect(struct vs_f32_rect start,
                                 struct vs_f32_rect bounds,
                                 uint8_t corner,
                                 float delta_x,
                                 float delta_y,
                                 float min_width,
                                 float min_height,
                                 struct vs_f32_rect *out_rect);

int32_t vs_encode_bgra_image(struct vs_bgra_image_view source,
                             uint8_t format,
                             uint8_t jpeg_quality,
                             struct vs_encoded_bytes *out_bytes);

void vs_encoded_bytes_destroy(struct vs_encoded_bytes *bytes);

void vs_bgra_owned_image_destroy(struct vs_bgra_owned_image *image);

void *vs_timeline_create(uint32_t duration_ms, uint32_t width, uint32_t height);

void vs_timeline_destroy(void *handle);

int32_t vs_timeline_add_track(void *handle, uint8_t kind);

int32_t vs_timeline_remove_track(void *handle, uint32_t track_index);

int32_t vs_timeline_reorder_track(void *handle, uint32_t from_index, uint32_t to_index);

int32_t vs_timeline_set_track_visible(void *handle, uint32_t track_index, bool visible);

int32_t vs_timeline_get_tracks(void *handle,
                               struct vs_timeline_track_info *out_ptr,
                               uint32_t out_cap,
                               uint32_t *out_written);

int32_t vs_timeline_derive_export_context(const void *handle,
                                          bool source_has_audio,
                                          bool source_has_webcam_asset,
                                          struct vs_video_export_context *out_context);

int32_t vs_timeline_is_webcam_track_visible_for_export(const void *handle, bool *out_visible);

int32_t vs_timeline_get_text_export_clips(const void *handle,
                                          struct vs_timeline_text_export_clip_info *out_ptr,
                                          uint32_t out_cap,
                                          uint32_t *out_written);

int32_t vs_timeline_bootstrap_capture_tracks(void *handle,
                                             bool source_has_audio,
                                             bool source_has_webcam_asset);

int32_t vs_timeline_add_text_clip_auto_track(void *handle,
                                             uint32_t start_ms,
                                             uint32_t end_ms,
                                             const uint8_t *text_ptr,
                                             uint32_t text_len,
                                             uint32_t *out_clip_id);

int32_t vs_timeline_add_clip(void *handle,
                             uint32_t track_index,
                             uint32_t start_ms,
                             uint32_t end_ms,
                             uint8_t kind,
                             uint32_t *out_clip_id);

int32_t vs_timeline_remove_clip(void *handle, uint32_t track_index, uint32_t clip_id);

int32_t vs_timeline_move_clip(void *handle,
                              uint32_t track_index,
                              uint32_t clip_id,
                              uint32_t new_start_ms);

int32_t vs_timeline_resize_clip(void *handle,
                                uint32_t track_index,
                                uint32_t clip_id,
                                uint32_t new_start_ms,
                                uint32_t new_end_ms);

int32_t vs_timeline_split_clip(void *handle,
                               uint32_t track_index,
                               uint32_t clip_id,
                               uint32_t split_at_ms,
                               uint32_t *out_new_clip_id);

int32_t vs_timeline_update_clip_transform(void *handle,
                                          uint32_t track_index,
                                          uint32_t clip_id,
                                          struct vs_clip_transform transform);

int32_t vs_timeline_set_clip_text(void *handle,
                                  uint32_t track_index,
                                  uint32_t clip_id,
                                  const uint8_t *text_ptr,
                                  uint32_t text_len);

int32_t vs_timeline_set_clip_text_style(void *handle,
                                        uint32_t track_index,
                                        uint32_t clip_id,
                                        float font_size,
                                        uint32_t color,
                                        uint32_t bg_color);

int32_t vs_timeline_set_clip_shape_style(void *handle,
                                         uint32_t track_index,
                                         uint32_t clip_id,
                                         uint32_t fill,
                                         uint32_t border,
                                         float border_width,
                                         float corner_radius);

int32_t vs_timeline_get_clips(void *handle,
                              uint32_t track_index,
                              struct vs_timeline_clip_info *out_ptr,
                              uint32_t out_cap,
                              uint32_t *out_written);

int32_t vs_timeline_get_visible_clips_at(void *handle,
                                         uint32_t time_ms,
                                         struct vs_timeline_clip_info *out_ptr,
                                         uint32_t out_cap,
                                         uint32_t *out_written);

int32_t vs_timeline_get_clip_text(void *handle,
                                  uint32_t track_index,
                                  uint32_t clip_id,
                                  uint8_t *out_ptr,
                                  uint32_t out_cap,
                                  uint32_t *out_written);

int32_t vs_timeline_get_clip_shape_style(void *handle,
                                         uint32_t track_index,
                                         uint32_t clip_id,
                                         uint32_t *out_fill,
                                         uint32_t *out_border,
                                         float *out_border_width,
                                         float *out_corner_radius);

int32_t vs_timeline_undo(void *handle);

int32_t vs_timeline_redo(void *handle);

int32_t vs_timeline_get_video_info(void *handle,
                                   uint32_t *out_duration_ms,
                                   uint32_t *out_width,
                                   uint32_t *out_height);

int32_t vs_timeline_set_clip_zoom_scale(void *handle,
                                        uint32_t track_index,
                                        uint32_t clip_id,
                                        float scale);

int32_t vs_timeline_get_clip_zoom_scale(void *handle,
                                        uint32_t track_index,
                                        uint32_t clip_id,
                                        float *out_scale);

#endif  /* VIVYSHOT_CORE_H */
