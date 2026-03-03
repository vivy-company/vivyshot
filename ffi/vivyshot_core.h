#ifndef VIVYSHOT_CORE_H
#define VIVYSHOT_CORE_H

#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

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

typedef struct vs_video_export_context {
  bool source_has_audio;
  bool source_has_webcam_asset;
  bool audio_track_visible;
  bool webcam_track_visible;
  uint32_t text_overlay_count;
} vs_video_export_context;

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

typedef struct vs_stitch_delta {
  uint32_t rows;
  uint8_t side;
  float score;
} vs_stitch_delta;

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

typedef struct vs_overlay_key_event_input {
  uint64_t timestamp_ns;
  uint32_t token_len;
} vs_overlay_key_event_input;

typedef struct vs_overlay_text_clip_input {
  uint32_t start_ms;
  uint32_t end_ms;
  uint32_t text_len;
} vs_overlay_text_clip_input;

typedef struct vs_overlay_plan_item {
  uint8_t kind;
  uint32_t source_index;
  uint32_t start_ms;
  uint32_t duration_ms;
  float x_norm;
  float y_norm;
  float width_norm;
  float height_norm;
  float font_size_px;
  float corner_radius_norm;
  float fade_in_frac;
  float hold_frac;
} vs_overlay_plan_item;

typedef struct vs_f32_rect {
  float x;
  float y;
  float width;
  float height;
} vs_f32_rect;

typedef struct vs_i32_rect {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
} vs_i32_rect;

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

typedef struct vs_timeline_track_info {
  uint8_t kind;
  bool visible;
  uint32_t clip_count;
} vs_timeline_track_info;

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

void *vs_create_document_from_bgra(uint32_t width,
                                   uint32_t height,
                                   uint32_t stride,
                                   const uint8_t *ptr,
                                   uintptr_t len);

void vs_destroy_document(void *doc);

void *vs_video_session_create(struct vs_video_session_config config);

int32_t vs_video_session_add_key_event(void *session, struct vs_video_key_event event);

int32_t vs_video_session_add_click_event(void *session, struct vs_video_click_event event);

int32_t vs_video_session_set_trim(void *session, uint32_t start_ms, uint32_t end_ms);

int32_t vs_video_session_set_export_context(void *session, struct vs_video_export_context context);

int32_t vs_video_session_get_export_plan(void *session, struct vs_video_export_plan *out_plan);

int32_t vs_video_session_serialize_json(void *session,
                                        uint8_t *out_ptr,
                                        uint32_t out_cap,
                                        uint32_t *out_written);

void *vs_video_session_deserialize_json(const uint8_t *json_ptr, uint32_t json_len);

void vs_video_session_destroy(void *session);

void *vs_stitch_session_create(void);

void vs_stitch_session_destroy(void *session);

int32_t vs_stitch_session_reset(void *session, uint32_t base_segment_count);

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

void vs_bgra_owned_image_destroy(struct vs_bgra_owned_image *image);

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
