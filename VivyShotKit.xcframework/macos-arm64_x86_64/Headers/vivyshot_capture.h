#ifndef VIVYSHOT_CAPTURE_H
#define VIVYSHOT_CAPTURE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct vs_capture_recording_session vs_capture_recording_session;
typedef struct vs_capture_webcam_recording_session vs_capture_webcam_recording_session;

enum {
  VS_CAPTURE_STATUS_OK = 0,
  VS_CAPTURE_STATUS_NULL_POINTER = -1,
  VS_CAPTURE_STATUS_INVALID_ARGUMENT = -2,
  VS_CAPTURE_STATUS_BUFFER_TOO_SMALL = -3,
  VS_CAPTURE_STATUS_PERMISSION_DENIED = -100,
  VS_CAPTURE_STATUS_PERMISSION_NOT_DETERMINED = -101,
  VS_CAPTURE_STATUS_UNSUPPORTED_OS_VERSION = -102,
  VS_CAPTURE_STATUS_NO_DISPLAY_FOR_SELECTION = -103,
  VS_CAPTURE_STATUS_SELECTION_TOO_SMALL = -104,
  VS_CAPTURE_STATUS_UNSUPPORTED_CODEC = -105,
  VS_CAPTURE_STATUS_UNSUPPORTED_CONTAINER = -106,
  VS_CAPTURE_STATUS_STREAM_START_FAILED = -107,
  VS_CAPTURE_STATUS_STREAM_STOPPED_WITH_ERROR = -108,
  VS_CAPTURE_STATUS_RECORDING_OUTPUT_FAILED = -109,
  VS_CAPTURE_STATUS_NO_FRAMES_CAPTURED = -110,
  VS_CAPTURE_STATUS_OUTPUT_FILE_UNAVAILABLE = -111,
  VS_CAPTURE_STATUS_CANCELLED = -112,
  VS_CAPTURE_STATUS_INTERNAL_PLATFORM_ERROR = -113,
  VS_CAPTURE_STATUS_UNSUPPORTED_PLATFORM = -114,
};

enum {
  VS_CAPTURE_ENCODER_STANDARD_H264 = 0,
  VS_CAPTURE_ENCODER_SMALLER_FILE_HEVC = 1,
  VS_CAPTURE_ENCODER_SOFTWARE_H264 = 2,
};

enum {
  VS_CAPTURE_CODEC_H264 = 0,
  VS_CAPTURE_CODEC_HEVC = 1,
};

enum {
  VS_CAPTURE_CONTAINER_MP4 = 0,
  VS_CAPTURE_CONTAINER_MOV = 1,
};

enum {
  VS_CAPTURE_DEVICE_KIND_DISPLAY = 0,
  VS_CAPTURE_DEVICE_KIND_MICROPHONE = 1,
};

enum {
  VS_CAPTURE_DEVICE_CAPABILITY_DISPLAY_RECORDING = 1u << 0,
  VS_CAPTURE_DEVICE_CAPABILITY_REGION_RECORDING = 1u << 1,
  VS_CAPTURE_DEVICE_CAPABILITY_SCREENSHOT_CAPTURE = 1u << 2,
  VS_CAPTURE_DEVICE_CAPABILITY_MICROPHONE_AUDIO = 1u << 3,
  VS_CAPTURE_DEVICE_CAPABILITY_WEBCAM_RECORDING = 1u << 4,
};

enum {
  VS_CAPTURE_PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST = 0,
};

typedef struct {
  double x;
  double y;
  double width;
  double height;
} vs_capture_rect;

typedef struct {
  const uint8_t *path_utf8;
  uint32_t path_len;
} vs_capture_path;

typedef struct {
  vs_capture_rect selection_rect_screen;
  vs_capture_path output_path;
  uint32_t frame_rate;
  uint8_t encoder;
  bool capture_system_audio;
  bool capture_microphone;
  bool show_cursor;
  bool highlight_mouse_clicks;
  const uint32_t *include_window_ids;
  uint32_t include_window_id_count;
  bool exclude_current_process;
} vs_capture_recording_config;

typedef struct {
  vs_capture_path output_path;
  uint32_t width;
  uint32_t height;
  uint32_t frame_rate;
  uint8_t codec;
  uint8_t container;
} vs_capture_recording_output;

typedef struct {
  vs_capture_path output_path;
  const uint8_t *preferred_device_id_utf8;
  uint32_t preferred_device_id_len;
} vs_capture_webcam_recording_config;

typedef struct {
  vs_capture_path output_path;
  double recording_start_uptime_seconds;
} vs_capture_webcam_recording_output;

typedef struct {
  bool region_recording;
  bool window_recording;
  bool display_recording;
  bool system_audio;
  bool microphone_audio;
  bool cursor_capture;
  bool mouse_click_visualization;
  bool direct_to_file_recording;
  bool h264;
  bool hevc;
  bool software_h264;
  bool screenshot_capture;
  bool overlay_window_exceptions;
} vs_capture_capabilities;

typedef struct {
  const uint8_t *stable_id_utf8;
  uint32_t stable_id_len;
  const uint8_t *display_name_utf8;
  uint32_t display_name_len;
  uint32_t capability_mask;
  bool is_available;
} vs_capture_device;

typedef struct {
  const uint8_t *stable_id_utf8;
  uint32_t stable_id_len;
  const uint8_t *display_name_utf8;
  uint32_t display_name_len;
  uint32_t capability_mask;
  bool is_available;
} vs_capture_webcam_device;

typedef struct {
  uint32_t width;
  uint32_t height;
  uint32_t bytes_per_row;
  uint8_t pixel_format;
  const uint8_t *data;
  uint32_t data_len;
} vs_capture_captured_image;

typedef void (*vs_capture_recording_start_callback)(
  void *user_data,
  int32_t status,
  vs_capture_recording_session *session
);

typedef void (*vs_capture_recording_stop_callback)(
  void *user_data,
  int32_t status,
  vs_capture_recording_output output
);

typedef void (*vs_capture_webcam_recording_start_callback)(
  void *user_data,
  int32_t status
);

typedef void (*vs_capture_webcam_recording_stop_callback)(
  void *user_data,
  int32_t status,
  vs_capture_webcam_recording_output output
);

typedef void (*vs_capture_screenshot_callback)(
  void *user_data,
  int32_t status,
  vs_capture_captured_image image
);

void vs_capture_screenshot(
  vs_capture_rect rect_screen,
  void *user_data,
  vs_capture_screenshot_callback callback
);

void vs_capture_captured_image_free(vs_capture_captured_image image);

void vs_capture_recording_start(
  const vs_capture_recording_config *config,
  void *user_data,
  vs_capture_recording_start_callback callback
);

void vs_capture_recording_stop(
  vs_capture_recording_session *session,
  void *user_data,
  vs_capture_recording_stop_callback callback
);

void vs_capture_recording_cancel(vs_capture_recording_session *session);

void vs_capture_recording_output_free(vs_capture_recording_output output);

int32_t vs_capture_webcam_recording_create(
  const vs_capture_webcam_recording_config *config,
  vs_capture_webcam_recording_session **out_session
);

void *vs_capture_webcam_recording_preview_session(
  vs_capture_webcam_recording_session *session
);

void vs_capture_webcam_recording_start(
  vs_capture_webcam_recording_session *session,
  void *user_data,
  vs_capture_webcam_recording_start_callback callback
);

void vs_capture_webcam_recording_stop(
  vs_capture_webcam_recording_session *session,
  void *user_data,
  vs_capture_webcam_recording_stop_callback callback
);

void vs_capture_webcam_recording_cancel(vs_capture_webcam_recording_session *session);

void vs_capture_webcam_recording_output_free(vs_capture_webcam_recording_output output);

int32_t vs_capture_copy_capabilities(vs_capture_capabilities *out_capabilities);

int32_t vs_capture_copy_devices(
  uint8_t device_kind,
  vs_capture_device *out_devices,
  uint32_t capacity,
  uint32_t *out_count
);

void vs_capture_devices_free(vs_capture_device *devices, uint32_t count);

int32_t vs_capture_copy_webcam_devices(
  vs_capture_webcam_device *out_devices,
  uint32_t capacity,
  uint32_t *out_count
);

void vs_capture_webcam_devices_free(vs_capture_webcam_device *devices, uint32_t count);

#endif
