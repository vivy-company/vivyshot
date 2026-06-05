# Rust Platform Capture Backends Spec

## Status

- Proposed
- Date: 2026-06-05
- Scope: future Rust capture crate for platform-specific capture/media execution under `vivyshot-rs/crates/`.
- Related:
  - `AGENTS.md`
  - `docs/rust-core-native-surface-video-refactor-spec.md`
  - `docs/rust-core-ffi-refactor-spec.md`
  - `docs/recording-preview-polish-spec.md`
  - `docs/smart-capture-selection-spec.md`
  - `macos/Sources/App/Features/Capture/CaptureCoordinator.swift`
  - `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlay+Stitch.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlayController.swift`
  - `vivyshot-rs/Cargo.toml`
  - `vivyshot-rs/crates/vivyshot-core/`
  - `vivyshot-rs/crates/vivyshot-ffi/`

## 1. Problem Statement

VivyShot's long-term architecture is Rust-first, multi-surface, and platform-aware:

1. `vivyshot-core` owns portable product state and decisions.
2. Native surfaces own UI, packaging, permissions UX, windows, and platform integration.
3. Platform capture/media code should be reusable by future official desktop surfaces where possible.

The current macOS app is moving in that direction, but live capture and media execution are still Swift-owned. That is acceptable for a first macOS app, but it creates a second boundary problem:

1. macOS-specific capture code is mixed into the Swift UI shell.
2. Future Windows/Linux work has no matching Rust capture crate shape to target.
3. Some logic that is not portable core logic, but is still non-UI runtime logic, has no home except `macos/`.

This spec defines a middle layer:

```text
portable Rust core != platform capture backend != Swift UI shell
```

The target is not to put `ScreenCaptureKit`, `AVFoundation`, or `VideoToolbox` in `vivyshot-core`. The target is to create a separate `vivyshot-capture` crate inside the Rust workspace, starting with an internal macOS implementation, so Swift becomes thinner without making the portable core macOS-shaped.

## 2. Decision

Add one platform-aware capture crate under `vivyshot-rs/crates/` when implementation starts.

Recommended crate layout:

```text
vivyshot-rs/crates/
  vivyshot-core/                  # portable domain/product logic only
  vivyshot-capture/               # platform-aware capture runtime and shared capture types
  vivyshot-ffi/                   # single app-facing C ABI/staticlib
```

Keep today's `vivyshot-ffi` crate as the single C ABI and staticlib crate. It can expose both `ffi/vivyshot_core.h` and `ffi/vivyshot_capture.h`, but it should not become the place where capture state machines live. The implementation state belongs in `vivyshot-capture`.

The initial implemented crate should be `vivyshot-capture`, with `cfg(target_os = "macos")` modules for Apple framework execution. Future Windows/Linux support can be added as internal modules first. Split platform crates should be introduced only if dependency pressure, build portability, or ownership makes the split pay for itself.

Short ownership rule:

```text
vivyshot-core owns product truth.
vivyshot-capture owns capture runtime, platform-neutral capture contracts, and cfg-selected platform execution.
vivyshot-ffi owns the C ABI and app staticlib.
macos/ owns UI, app lifecycle, permission UX, windows, and App Store packaging.
```

## 3. Relationship To Existing Specs

`docs/rust-core-native-surface-video-refactor-spec.md` says that refactor does not require porting `ScreenCaptureKit` or `AVFoundation` to Rust. That remains true for `vivyshot-core`.

This spec refines the target boundary:

1. `vivyshot-core` must not call Apple APIs.
2. `vivyshot-ffi` remains the single app-facing C ABI/staticlib crate.
3. Apple APIs may move from Swift into `vivyshot-capture` if the Apple code is clearly platform-scoped behind `cfg(target_os = "macos")` and hidden behind the universal capture ABI.
4. Swift may still be the caller and UI owner.

So the older line "Swift owns native capabilities and pixels" becomes:

```text
The macOS surface owns native capabilities at the product boundary.
The implementation of those capabilities may live in Swift or in vivyshot-capture.
```

## 4. Current Code Audit

### 4.1 Swift Video Recording Orchestration

`VideoCaptureCoordinator` currently owns the whole live recording workflow:

1. Reads user settings.
2. Runs countdown.
3. Ensures camera/microphone/accessibility permissions.
4. Creates webcam and keystroke overlay windows.
5. Builds `VideoRecordingConfig`.
6. Chooses one of two recording implementations:
   - `ScreenRegionRecorder`
   - `ScreenRegionSoftwareH264Recorder`
7. Starts webcam recording.
8. Starts screen recording.
9. Starts keyboard/mouse input monitoring.
10. Stops all sessions.
11. Creates a `RustVideoProjectSession` from recorded metadata and events.
12. Presents post-recording save/discard UI.

This whole class should not move into Rust. It is UI-flow orchestration and app policy. The future boundary should make this class call a Rust-backed recorder instead of constructing Apple framework sessions directly.

### 4.2 Default Screen Recording Path

`ScreenRegionRecorder` is the best first migration candidate.

Current responsibilities:

1. Resolve `SCShareableContent.current`.
2. Resolve active display for the selected screen rect.
3. Build `SCContentFilter`.
4. Exclude the VivyShot process.
5. Add overlay windows back through `exceptingWindows`.
6. Convert Cocoa screen rects into display-space `sourceRect`.
7. Build `SCStreamConfiguration`.
8. Set frame rate through `minimumFrameInterval`.
9. Configure cursor, mouse clicks, system audio, microphone, and SDR dynamic range.
10. Build `SCRecordingOutputConfiguration`.
11. Choose H.264 or HEVC.
12. Choose MP4 or fallback file type.
13. Start and stop `SCStream`.

This is platform execution, not portable product logic. It can move to `vivyshot-capture` first, under its macOS implementation module.

The Swift caller should continue to provide:

1. Selection rect in screen coordinates.
2. Desired output URL or temporary output directory.
3. Capture flags.
4. Target frame rate.
5. Encoder choice.
6. Overlay window IDs that must be included.
7. Whether the host has already completed permission UX.

The Rust backend should return:

1. Recording output URL.
2. Effective codec/container.
3. Effective frame size.
4. Started/stopped timestamps if needed for sync.
5. Structured platform error.

### 4.3 Software H.264 Recording Path

`ScreenRegionSoftwareH264Recorder` and `SoftwareH264AssetWriter` are movable, but they are not the first slice.

Current responsibilities:

1. Build the same `SCShareableContent`, `SCContentFilter`, and `SCStreamConfiguration` as the default path.
2. Add `SCStreamOutput` callbacks for screen, system audio, and microphone.
3. Receive `CMSampleBuffer` values.
4. Filter incomplete screen frames with `SCStreamFrameInfo.status`.
5. Configure `AVAssetWriter`.
6. Force software H.264 by setting `kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder` to `false`.
7. Configure AAC audio inputs.
8. Start writing on first video timestamp.
9. Append video/audio sample buffers.
10. Finish or cancel the writer.

This path touches more delegate/callback lifetime, `CMSampleBuffer`, `AVAssetWriter`, and `VideoToolbox` behavior. It should move after the default `SCRecordingOutput` path is proven in Rust.

The macOS Rust ecosystem has two plausible implementation paths:

1. Use a higher-level `screencapturekit` crate where it covers the needed recording surface.
2. Use `objc2-*` framework crates directly for `ScreenCaptureKit`, `AVFoundation`, `CoreMedia`, `CoreVideo`, and `VideoToolbox`.

The second path is likely necessary for full parity with the current software H.264 writer if higher-level crates do not expose every `AVAssetWriter` and encoder-specification control needed by VivyShot.

### 4.4 Screenshot Capture

Screenshot capture is currently Swift-owned in at least three places:

1. Main frozen capture image in `CaptureCoordinator.captureFrozenImage(...)`.
2. Region selection preview image in `RegionSelectionOverlayController.capturePreviewImage(...)`.
3. Stitch frame capture in `RegionSelectionOverlay+Stitch.captureScreenImage(...)`.

These calls use `SCScreenshotManager.captureImage(in:)`, then Swift converts, crops, displays, or passes images into Rust document/stitch sessions.

Screenshot capture can move to `vivyshot-capture`, but it should be a separate phase from video recording.

Recommended backend return shape:

```text
CapturedImage {
  width: u32,
  height: u32,
  pixel_format: Bgra8PremultipliedFirst,
  bytes_per_row: u32,
  data: owned bytes
}
```

Swift can turn that into `CGImage` for UI display. Rust document/stitch code can receive the same buffer through existing or new FFI helpers. Avoid exposing `CGImage` ownership through the portable core ABI.

### 4.5 Stitch Capture Loop

The stitch loop is mixed:

1. Swift owns overlay pass-through windows, target app activation, auto-scroll permission checks, and UI controls.
2. Rust already owns stitch session state and image merge behavior.
3. Swift currently captures each frame with `SCScreenshotManager`, crops the segment, then pushes the image into Rust.

Future target:

1. `vivyshot-capture` can own repeated frame capture through its platform implementation.
2. Swift should still own overlay pass-through and target app activation.
3. `vivyshot-core` should continue to own stitch acceptance/merge logic.

Do not move auto-scroll UI/window management into a capture backend.

### 4.6 Webcam Capture

`WebcamRecorder` currently owns `AVCaptureSession`, device selection, preview layer creation, movie recording, and output validation.

This can partially move, but it has a hard UI boundary:

1. Recording a webcam asset to a file can eventually move to `vivyshot-capture`.
2. Device enumeration can move only if Swift settings UI gets a clean device-list API.
3. `AVCaptureVideoPreviewLayer` should stay Swift/AppKit-owned because it is directly embedded into overlay UI.
4. Camera permission UX should stay Swift-owned, though the backend may expose preflight/status helpers.

Webcam capture should not be in the first migration because the current screen recording path depends on live overlay window behavior and webcam timing. Move it after screen recording is stable.

### 4.7 Keyboard And Mouse Input Monitoring

`RecordingInputMonitor` currently uses AppKit event monitors and accessibility trust:

1. `NSEvent.addGlobalMonitorForEvents`.
2. `NSEvent.addLocalMonitorForEvents`.
3. `AXIsProcessTrustedWithOptions`.
4. Swift-to-Rust key token normalization.
5. Rust-backed duplicate filtering and normalized click point validation.

This is not a capture backend priority.

The platform source of input events could eventually move into `vivyshot-capture`, but the display/token rules and event storage should remain in `vivyshot-core`. The live keystroke overlay is UI and should stay Swift-owned.

### 4.8 Post-Recording Project And Export

Post-recording project state is already partly Rust-owned through `RustVideoProjectSession`.

Rust currently owns:

1. Recording metadata model.
2. Key/click event storage.
3. Webcam and keystroke overlay state.
4. Render plans for preview/export.
5. Export plan derivation.
6. Pro requirement derivation.
7. Export container/preset/bitrate heuristics.

Swift still owns media execution:

1. `AVAssetExportSession`.
2. `AVAssetWriter`.
3. `AVAssetImageGenerator`.
4. `CGContext` drawing.
5. Save panels and file destinations.

This spec does not require moving post-recording export execution into `vivyshot-capture`. That could be a later `vivyshot-media` discussion. For now, keep this focused on capture.

## 5. What Should Move

### First Move

Move the default live screen recording implementation into `vivyshot-capture`:

1. Screen content discovery.
2. Display lookup.
3. Content filter construction.
4. Current-process exclusion.
5. Overlay-window exceptions.
6. Source rect conversion.
7. `SCStreamConfiguration`.
8. `SCRecordingOutputConfiguration`.
9. Start/stop lifecycle.
10. Structured error mapping.

Swift keeps `VideoCaptureCoordinator`, but `RecordingSession` becomes an adapter around the capture backend.

### Second Move

Move screenshot capture into `vivyshot-capture`:

1. Frozen screen capture.
2. Selection preview capture.
3. Stitch frame capture.
4. BGRA detach/copy behavior currently implemented in Swift.

This is valuable because screenshots are simpler than sample-buffer video recording and provide a good backend API test.

### Third Move

Move software H.264 recording:

1. `SCStreamOutput` screen/audio/microphone callbacks.
2. `CMSampleBuffer` readiness/status filtering.
3. Software encoder selection.
4. `AVAssetWriter` setup.
5. Writer finish/cancel lifecycle.

This should come after default recording because callback/delegate lifetime bugs are more likely here.

### Later Moves

Consider later:

1. Webcam file recording.
2. Camera device enumeration.
3. Input event source collection.
4. Platform media export execution.

Each should get its own spec update before implementation.

## 6. What Should Not Move

Do not move these into `vivyshot-capture`:

1. SwiftUI/AppKit views.
2. Overlay windows and drag interactions.
3. HUDs, toasts, panels, menus, and settings UI.
4. App Store purchase/paywall logic.
5. Save/open panels.
6. Clipboard writes.
7. App activation behavior except narrow helper calls explicitly needed by capture.
8. Localization.
9. User-facing permission explanation copy.
10. Entitlements, signing, sandbox profile, and App Store metadata.
11. Portable video project rules already owned by `vivyshot-core`.
12. Portable stitch/document/timeline logic already owned by `vivyshot-core`.

Do not move Apple APIs into `vivyshot-core`.

Do not add Apple framework dependencies to `vivyshot-core`.

Do not make `vivyshot-ffi` the place where capture state machines live. It may own opaque FFI handles, but the actual capture session behavior belongs in `vivyshot-capture`.

## 7. FFI And Linking Model

The portable C ABI in `ffi/vivyshot_core.h` should remain focused on `vivyshot-core`.

For capture, prefer one universal app-facing ABI. Platform-specific implementation should be selected inside Rust through `cfg(target_os = "...")` and backend capability detection, not by exposing `vs_macos_*`, `vs_windows_*`, or `vs_linux_*` functions to the host app.

The app should link one Rust xcframework with separate modules/headers inside it:

```text
VivyShotKit.xcframework
  Headers/
    vivyshot_core.h             # stable portable core ABI
    vivyshot_capture.h          # universal capture ABI
    module.modulemap            # exports one app module
```

This keeps Swift linked to one Rust kit while preserving a clean logical split between the stable portable core ABI and the evolving capture ABI. Separate headers are enough for the app boundary; separate FFI crates are not needed right now.

Recommended Rust package shape:

```text
vivyshot-core
vivyshot-capture
vivyshot-ffi
```

Initial implementation order:

1. Add `vivyshot-capture` as Rust-only first.
2. Keep macOS implementation under `vivyshot-capture/src/macos/` or equivalent `cfg(target_os = "macos")` modules.
3. Add capture C ABI functions to `vivyshot-ffi` only when Swift integration begins.
4. Keep the capture ABI internal/pre-1.0 until its shape is proven.
5. Split platform crates later only if the single capture crate becomes a real build or dependency problem.

Do not expose raw video frames across FFI for live recording. The first recording API should be file-based:

```text
start(config) -> session handle
stop(session handle) -> output file metadata
cancel(session handle)
```

Screenshot capture may return owned BGRA bytes because it is a bounded single image, not a long-running frame stream.

### 7.1 Crate Responsibilities

Use these crate responsibilities when implementation begins:

```text
vivyshot-core
  Owns portable document, geometry, stitch, timeline, video project, export-plan,
  render-plan, and statistics behavior. No Apple, Windows, or Linux framework dependencies.

vivyshot-capture
  Owns shared capture concepts and the cfg-selected platform runtime:
  rectangles, frame/image metadata, recording config, capture capabilities,
  device descriptors, codec/container enums, structured capture errors,
  recording sessions, screenshots, and device enumeration. Apple framework
  dependencies are allowed only behind macOS cfg gates.

vivyshot-ffi
  Owns the single app-facing C ABI and final staticlib. This is the source for
  ffi/vivyshot_core.h and, when capture is exposed to Swift, ffi/vivyshot_capture.h.
  It exposes platform-neutral handles, config structs, capabilities, devices,
  and errors, but delegates behavior to vivyshot-core and vivyshot-capture.
```

Future platform splits are optional, not the default. Add them only if internal
modules are no longer enough.

### 7.2 FFI Shape

The Swift app should see one app module from one kit:

```text
module VivyShotKit {
  header "vivyshot_core.h"
  header "vivyshot_capture.h"
  export *
}
```

Swift imports the app kit once:

```swift
import VivyShotKit
```

The capture ABI should use opaque handles and explicit lifecycle functions:

```c
typedef struct vs_capture_recording_session vs_capture_recording_session;

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
```

Use callback-based async C functions for start/stop so Swift can wrap them in `withCheckedThrowingContinuation` without requiring a Rust async runtime contract:

```c
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

void vs_capture_recording_cancel(
  vs_capture_recording_session *session
);
```

Callbacks may run off the main thread. Swift must hop to `MainActor` before touching UI.

Screenshot capture should use owned BGRA output and an explicit free function:

```c
typedef struct {
  uint32_t width;
  uint32_t height;
  uint32_t bytes_per_row;
  uint8_t pixel_format;
  const uint8_t *data;
  uint32_t data_len;
} vs_capture_captured_image;

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
```

Device enumeration should also be backend-owned:

```c
typedef struct {
  const uint8_t *stable_id_utf8;
  uint32_t stable_id_len;
  const uint8_t *display_name_utf8;
  uint32_t display_name_len;
  uint32_t capability_mask;
  bool is_available;
} vs_capture_device;

int32_t vs_capture_copy_devices(
  uint8_t device_kind,
  vs_capture_device *out_devices,
  uint32_t capacity,
  uint32_t *out_count
);
```

Any Rust-owned string/image/device buffer returned through FFI must have a matching free function or use caller-provided buffers. Do not return Swift/Objective-C object ownership through this ABI.

The implementation dispatch point lives in `vivyshot-capture`:

```rust
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub type Backend = macos::Backend;

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub type Backend = windows::Backend;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
pub type Backend = linux::Backend;
```

Unsupported platforms should compile to a backend that reports no capabilities and returns `UnsupportedPlatform` for capture operations.

### 7.3 Swift Adapter Shape

Swift should not call these C functions throughout the app. Keep one adapter layer:

```text
macos/Sources/App/Interop/Capture/
  Client.swift
  RecordingSession.swift
  Types.swift
```

Then `VideoCaptureCoordinator` talks to a Swift protocol:

```swift
protocol RecordingSession: AnyObject {
  func start() async throws
  func stop() async throws -> URL
}
```

The backend-backed implementation should satisfy that protocol. This keeps the rest of the Swift app as UI shell/orchestration instead of making C ABI calls leak into feature code.

### 7.4 Naming Rule

Use short capability names at the app boundary:

1. Prefer `Capture`, `Recording`, `Screenshot`, `Device`, `Client`, `Session`, and `Types`.
2. Do not prefix Swift-facing names with `Rust`, `Mac`, `Macos`, `Platform`, or `Backend`.
3. Do not prefix universal C ABI names with platform names.
4. Keep `vs_` and crate/package prefixes because C symbols and Cargo packages need global namespace protection.
5. Keep platform names only inside implementation details, such as `vivyshot-capture/src/macos/`. If future split crates are introduced, platform names are acceptable there too.

## 8. Proposed Rust API Shape

The `vivyshot-capture` crate should define platform-neutral data contracts. Do not make async traits the public cross-crate contract yet. They are awkward across FFI, harder to keep object-safe, and do not map cleanly to Swift's call boundary.

Use concrete backend/session structs in platform modules, with methods that can be async internally. The FFI should expose opaque handles and explicit lifecycle calls.

Example shared data shape:

```rust
use std::path::PathBuf;

pub struct CaptureRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

pub enum RecordingEncoder {
    StandardH264,
    SmallerFileHevc,
    SoftwareH264,
}

pub struct RecordingConfig {
    pub selection_rect_screen: CaptureRect,
    pub output_path: PathBuf,
    pub frame_rate: u32,
    pub encoder: RecordingEncoder,
    pub capture_system_audio: bool,
    pub capture_microphone: bool,
    pub show_cursor: bool,
    pub highlight_mouse_clicks: bool,
    pub include_window_ids: Vec<u32>,
    pub exclude_current_process: bool,
}

pub struct RecordingOutput {
    pub output_path: PathBuf,
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub codec: RecordingCodec,
    pub container: RecordingContainer,
}
```

Example implementation shape:

```rust
pub struct Backend;
pub struct RecordingSession;

impl Backend {
    pub async fn start_recording(
        &self,
        config: RecordingConfig,
    ) -> Result<RecordingSession, CaptureError> {
        todo!()
    }
}

impl RecordingSession {
    pub async fn stop(self) -> Result<RecordingOutput, CaptureError> {
        todo!()
    }

    pub fn cancel(self) {
        todo!()
    }
}
```

The exact method shape can change. The important rule is that the shared contract contains VivyShot concepts, not `SCStream`, `SCWindow`, `CMSampleBuffer`, `AVAssetWriter`, or AppKit types.

## 9. macOS Backend Dependency Candidates

Current viable Rust options as of 2026-06-05:

1. `screencapturekit` 7.0.0:
   - Docs: `https://docs.rs/screencapturekit/latest/screencapturekit/`
   - Provides safe Rust bindings for Apple's ScreenCaptureKit.
   - Documents screen/window/app capture, audio capture, callbacks, async support, screenshots, and direct-to-file recording.
2. `objc2-screen-capture-kit`:
   - Docs: `https://docs.rs/objc2-screen-capture-kit/`
   - Generated ScreenCaptureKit framework bindings.
   - Useful if high-level crates do not expose a needed API exactly.
3. `objc2-video-toolbox`:
   - Docs: `https://docs.rs/objc2-video-toolbox/latest/objc2_video_toolbox/`
   - Exposes `VTCompressionSession` and VideoToolbox constants/functions.
   - Relevant for encoder selection and software H.264 parity.
4. `videotoolbox`:
   - Docs: `https://docs.rs/videotoolbox/latest/videotoolbox/`
   - Higher-level VideoToolbox bindings.
   - Experimental according to its own docs, so validate before making it foundational.
5. Other `objc2-*` framework crates:
   - `objc2-av-foundation`
   - `objc2-core-media`
   - `objc2-core-video`
   - `objc2-core-graphics`
   - `objc2-foundation`

Selection rule:

1. Prefer a safe high-level crate where it covers VivyShot's exact behavior.
2. Drop to `objc2-*` generated bindings for missing framework surface.
3. Avoid custom bindgen unless the maintained crates cannot represent a required public API.
4. Do not use private Apple APIs.

Decision for the default recording path:

1. Use `screencapturekit` as the primary dependency for the first macOS capture spike.
2. It documents `SCStream`, `SCContentFilter`, `SCStreamConfiguration`, screenshots, audio, microphone, and direct-to-file `SCRecordingOutput`.
3. It also documents examples for direct recording and exclusion of app windows.
4. VivyShot's exact current path uses `excludingApplications` plus `exceptingWindows` to exclude VivyShot while allowing specific overlay windows. If the high-level crate does not expose that constructor with enough precision, use `objc2-screen-capture-kit` for filter construction only and keep the rest on `screencapturekit`.
5. Do not let this choice leak into the public `vivyshot-capture` API; it is a macOS module implementation detail.

Decision for software H.264:

1. Preserve the current `AVAssetWriter` architecture first.
2. Implement it through `objc2-av-foundation`/`avassetwriter`-level bindings if possible.
3. Keep using Apple's encoder specification key to disable hardware H.264.
4. Use lower-level `VTCompressionSession` only if `AVAssetWriter` bindings cannot express the required software-encoder behavior or if we later need frame-level rate-control that `AVAssetWriter` cannot provide.
5. Avoid building a custom muxer in the first migration; audio/video timing and container writing are already solved by `AVAssetWriter`.

## 10. Build System Impact

Current workspace members are only:

1. `crates/vivyshot-core`
2. `crates/vivyshot-ffi`

Current build scripts package only `vivyshot-ffi` into `VivyShotKit.xcframework`.

When adding capture support:

1. Add `crates/vivyshot-capture` as a new workspace member under `vivyshot-rs/Cargo.toml`.
2. Gate macOS implementation code with `cfg(target_os = "macos")`.
3. Do not require macOS-only crates for Linux/Windows `cargo test -p vivyshot-core`.
4. Keep `scripts/build-rust.sh` focused on the existing app staticlib until Swift uses capture.
5. Extend the existing xcframework packaging entry point when capture is exposed through `vivyshot-ffi`.
6. Do not collapse `vivyshot_core.h` and `vivyshot_capture.h` into one header; they may ship in the same xcframework, but they represent different ABI contracts.

Potential package shape:

```text
scripts/build-xcframework.sh
VivyShotKit.xcframework/
ffi/vivyshot_capture.h
```

If the existing `scripts/build-xcframework.sh` remains the entry point, it should grow from "build core FFI" to "build the app Rust kit" while still keeping the portable `vivyshot_core.h` contract separate from platform headers.

## 11. Migration Plan

### Phase 0: Spec And Spike Only

1. Land this spec.
2. Do not change app behavior.
3. Do not add dependencies yet unless doing a contained compile spike.

### Phase 1: Create Capture Crate Without Swift Integration

1. Add `vivyshot-capture`.
2. Add `cfg(target_os = "macos")` implementation modules inside it.
3. Add config/output/error types.
4. Add backend tests for pure config mapping.
5. Confirm `cargo test -p vivyshot-core` is unaffected.
6. Confirm `cargo test -p vivyshot-capture` works where supported.
7. Confirm the macOS implementation compiles on Apple targets.

### Phase 2: Default Screen Recording Behind A Swift Adapter

1. Add capture ABI functions to `vivyshot-ffi`.
2. Build a Swift `RecordingSession` adapter that calls the capture ABI.
3. Keep old Swift `ScreenRegionRecorder` behind a temporary compile/runtime switch during validation.
4. Compare H.264, HEVC fallback, audio, microphone, cursor, mouse clicks, overlay-window exception, and frame-rate behavior.
5. Remove the Swift default recorder only after parity is verified.

### Phase 3: Screenshot Capture

1. Add single-frame capture API.
2. Return owned BGRA bytes plus image metadata from Rust.
3. Rewire frozen capture, preview capture, and stitch frame capture one at a time.
4. Keep cropping either in Swift UI code or Rust core, but not in the platform backend unless it is purely capture-rect clipping.
5. Convert BGRA output to `CGImage` only at the Swift UI display boundary.

### Phase 4: Software H.264

1. Move sample-buffer recording to Rust.
2. Preserve software encoder behavior.
3. Preserve AAC audio behavior.
4. Validate no-frame, early-stop, cancellation, and writer-failure cases.
5. Validate App Store sandbox release behavior.

### Phase 5: Optional Webcam Capture

1. Move camera device enumeration into the capture backend.
2. Return stable device IDs, localized display names, availability, and capability flags.
3. Let Swift settings render the list and persist the selected stable device ID.
4. Add webcam recording-to-file API.
5. Keep overlay UI in Swift.
6. Prefer backend-owned preview-session setup with Swift only hosting a native preview layer/handle if that proves tractable; otherwise keep preview-layer creation in Swift as a temporary UI boundary.
7. Revalidate timing offset between screen and webcam assets.

### Phase 6: Optional Input Sources

1. Consider Rust-owned event monitor sources only if Swift input collection becomes a maintenance burden.
2. Keep portable key/click normalization and event storage in `vivyshot-core`.
3. Keep live overlay display in Swift.

### Phase 7: Future Platforms

Add matching internal platform modules first:

1. Windows module for Windows Graphics Capture / Media Foundation.
2. Linux module for PipeWire, xdg-desktop-portal, Wayland/X11-specific capture paths.

These modules should implement the same `vivyshot-capture` concepts where possible, but they may expose platform capability differences through typed capability reports. Split them into separate crates only if the single-crate model becomes painful.

## 12. Capability Model

Do not assume every platform supports every option.

The shared capture layer should expose capabilities such as:

1. Region recording.
2. Window recording.
3. Display recording.
4. System audio.
5. Microphone audio.
6. Cursor capture.
7. Mouse click visualization.
8. Direct-to-file recording.
9. H.264.
10. HEVC.
11. Software H.264.
12. Screenshot capture.
13. Overlay-window include/exclude behavior.

The UI can then map unsupported capabilities to disabled controls, fallback choices, or explanatory copy.

The backend, not Swift settings UI, should be the source of truth for device and capture capability enumeration. Swift should render capabilities, not infer them from platform APIs itself.

## 13. Error Model

Use structured errors at the Rust boundary.

Minimum categories:

1. PermissionDenied.
2. PermissionNotDetermined.
3. UnsupportedOSVersion.
4. NoDisplayForSelection.
5. SelectionTooSmall.
6. UnsupportedCodec.
7. UnsupportedContainer.
8. StreamStartFailed.
9. StreamStoppedWithError.
10. RecordingOutputFailed.
11. NoFramesCaptured.
12. OutputFileUnavailable.
13. Cancelled.
14. InternalPlatformError.

Swift should decide user-facing copy. The backend should return machine-readable status and optional diagnostic strings.

## 14. Permission Boundary

The macOS app must remain the owner of permission UX because:

1. Entitlements live in `macos/Config/VivyShot.entitlements`.
2. App Store review and sandbox behavior are app-level concerns.
3. The welcome/settings flows currently explain screen recording, camera, microphone, and accessibility access.
4. Some APIs trigger system prompts in app context regardless of whether Swift or Rust calls them.

The macOS implementation may expose:

1. `screen_capture_permission_status`.
2. `camera_permission_status`.
3. `microphone_permission_status`.
4. `accessibility_trusted_status`.
5. Narrow prompt helpers only if the app explicitly calls them.

It should not own user-facing permission copy.

## 15. Testing And Validation

Required before replacing a Swift recorder:

1. `cargo test -p vivyshot-core`
2. `cargo test -p vivyshot-capture`
3. macOS-target compile for the `vivyshot-capture` macOS implementation
4. FFI contract tests for any capture header
5. `./scripts/gen-ffi.sh` only if portable core header changes
6. `xcodebuild -project macos/VivyShot.xcodeproj -scheme VivyShot -configuration Debug -destination 'platform=macOS' build`
7. Manual screen recording smoke with:
   - H.264
   - HEVC
   - software H.264
   - 30/60/120 fps
   - system audio
   - microphone audio
   - cursor
   - mouse click highlights
   - webcam overlay visible and movable
   - keystroke overlay visible
   - overlay windows captured when expected
   - app windows excluded when expected
8. Sandboxed release smoke before shipping.

## 16. Risks

1. Rust Objective-C delegate lifetimes can be easier to get subtly wrong than Swift delegates.
2. Async callback ownership must not require a global Tokio runtime unless the app deliberately adopts one.
3. `CMSampleBuffer`, `CVPixelBuffer`, and `IOSurface` lifetime mistakes can cause crashes or corrupted frames.
4. OS-version availability must match the app's supported macOS range.
5. App Store sandbox behavior may differ from local debug behavior.
6. Third-party crate API coverage may lag new Apple SDK features.
7. Debugging media callbacks may become harder across Swift/Rust boundaries.
8. Additional headers/modules inside the app Rust kit increase release packaging complexity.
9. Moving too much at once can obscure whether regressions are from capture, encoding, permissions, or UI orchestration.

## 17. Resolved Design Questions

### 17.1 Capture ABI Packaging

Decision: link the universal capture ABI into the existing app Rust xcframework, but keep separate headers/modules.

Reasoning:

1. Swift should depend on one Rust kit for app integration.
2. One FFI crate keeps packaging simple and matches the current workspace.
3. Separate headers keep the portable core ABI stable while letting capture evolve as its own universal ABI.
4. A separate xcframework remains available later if signing, App Store packaging, or release cadence demands it.

### 17.2 Shared Capture API Form

Decision: `vivyshot-capture` should define shared data types, capability models, errors, and concrete backend/session structs. Do not make async traits the primary public contract.

Reasoning:

1. Swift integration wants opaque handles and lifecycle calls.
2. Concrete Rust structs are easier to evolve during pre-1.0.
3. Async traits add object-safety and runtime questions before they solve a real integration problem.
4. The backend can still use async internally.

### 17.3 `screencapturekit` Coverage

Decision: use `screencapturekit` first for default screen recording and screenshots, with `objc2-screen-capture-kit` reserved for missing exact API surface.

Reasoning:

1. The crate covers `SCStream`, `SCContentFilter`, `SCStreamConfiguration`, screenshots, audio/microphone capture, and direct-to-file `SCRecordingOutput`.
2. That matches most of VivyShot's default `ScreenRegionRecorder` path.
3. The one must-prove detail is VivyShot's `excludingApplications` plus `exceptingWindows` filter shape.
4. If the high-level crate does not expose that exact constructor, the macOS backend should construct the filter through `objc2-screen-capture-kit` and keep the rest high-level.

### 17.4 Software H.264 Implementation

Decision: port the current `AVAssetWriter` design first. Do not start with raw `VTCompressionSession` plus custom muxing.

Reasoning:

1. The current Swift path already records `CMSampleBuffer` video/audio into `AVAssetWriter`.
2. It already forces software H.264 through the VideoToolbox encoder-specification key.
3. Keeping `AVAssetWriter` preserves audio muxing, timing, file finalization, and failure semantics.
4. `VTCompressionSession` is useful later for lower-level encoder control, but it expands scope because VivyShot would also need muxing and tighter timestamp handling.

### 17.5 Screenshot Return Type

Decision: return owned BGRA bytes plus metadata.

Reasoning:

1. BGRA matches the app's current detached image/canvas path.
2. It keeps screenshots usable by both Swift UI and Rust document/stitch logic.
3. It avoids temp-file lifecycle and avoids encoding/decoding PNG just to hand pixels back to the app.
4. PNG should be a save/export format, not the capture interchange format.

### 17.6 Device Enumeration Ownership

Decision: backend owns device enumeration and capability reporting; Swift settings owns presentation and persistence of the selected device ID.

Reasoning:

1. Camera/microphone availability is platform capability, not UI policy.
2. Future Windows/Linux shells should not reimplement device discovery rules.
3. Swift still needs localized UI and settings storage.
4. Preview-layer hosting can remain a temporary Swift boundary, but recording-device selection should come from the backend.

### 17.7 Export Backend Ownership

Decision: future Rust platform code should own media export execution too, but not inside `vivyshot-capture`. Create a separate media crate when we move export execution.

Recommended later shape:

```text
vivyshot-media/
```

Reasoning:

1. Capture and export have different lifecycles, permissions, failure modes, and dependencies.
2. Swift should eventually ask Rust to execute exports instead of driving `AVAssetExportSession` and `AVAssetWriter` directly.
3. `vivyshot-core` should continue to own export decisions and render plans.
4. `vivyshot-media` can use the same internal `cfg(target_os = "...")` module model as `vivyshot-capture`.

## 18. Acceptance Criteria For This Architecture

The architecture is working when:

1. `vivyshot-core` remains free of Apple framework dependencies.
2. The macOS UI shell no longer directly constructs `SCStream` for default recording.
3. Swift still owns the user-visible recording flow.
4. Capture capabilities are represented in portable Rust types.
5. The macOS capture implementation can be tested independently of Swift UI.
6. Future Windows/Linux modules can implement the same capture concepts without inheriting Swift or Apple-specific API shapes.
7. The stable portable C ABI remains focused on core/product logic.
8. The capture ABI stays universal and platform-neutral, even though its implementation is platform-specific.
