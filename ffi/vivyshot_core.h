#ifndef VIVYSHOT_CORE_H
#define VIVYSHOT_CORE_H

#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

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

const char *vs_core_version(void);

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

#endif  /* VIVYSHOT_CORE_H */
