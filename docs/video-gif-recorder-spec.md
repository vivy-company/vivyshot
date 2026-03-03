# VivyShot Video/GIF Recorder Spec (Draft)

- Status: Draft
- Date: 2026-02-26
- Owner: VivyShot
- Scope: Extend current screenshot flow with a simple video recorder and basic trim editor.
- Note: This spec intentionally favors fast delivery on macOS first, while defining a Rust-core contract that stays portable.

## 1. Problem and Goals

Current app flow is screenshot-only (`CaptureCoordinator` -> `RegionSelectionOverlay` -> Rust-backed image editor). We need a second capture mode for video/GIF without losing speed.

Product goals:

1. Add a left-side capture-type panel during area capture:
   - `Screenshot` (default)
   - `Video`
2. Record selected region as video.
3. Support requested recorder features:
   - Show webcam in recordings.
   - Record microphone and macOS audio.
   - Highlight mouse clicks and keystrokes.
   - Reduce notification interruptions (best-effort, see risks).
   - Built-in trimming tool.
4. Add a new Settings tab for video capture.
5. Keep post-record editor intentionally simple.
6. Keep core logic portable through Rust-owned recording/session models.
7. Recorder flow must work with App Sandbox enabled.
8. Ship all requested recorder capabilities in one phase (no deferred feature phase).

## 2. Non-Goals (Initial Release)

1. Full nonlinear video editor (tracks, transitions, effects timeline).
2. Advanced webcam scene layouts (multiple cameras, custom masks).
3. Cloud upload/sharing pipeline.
4. Background daemon/helper process.

## 3. UX Specification

## 3.1 Capture Overlay

When capture starts:

1. Keep current area-selection experience.
2. Add a left vertical panel beside selection area:
   - Segmented control:
     - `Screenshot` (default)
     - `Video`
3. Bottom action behavior changes by mode:
   - `Screenshot`: existing behavior (enter image editor).
   - `Video`: starts recording selected region.

Panel behavior:

1. Preserves last-used mode for next capture, but first-time default is `Screenshot`.
2. Keyboard shortcuts while selecting:
   - `1` -> `Screenshot`
   - `2` -> `Video`

## 3.2 Recording HUD (Video Mode)

After clicking `Record`:

1. Show compact floating HUD near selection:
   - elapsed time
   - pause/resume
   - stop
   - mic/audio indicators
2. Keep HUD non-intrusive and outside crop region when possible.
3. `Esc` cancels if not recording; during recording, `Esc` stops and saves draft clip.

## 3.3 Post-Record Editor (Simple)

1. Open a basic clip editor immediately after recording.
2. Editor scope:
   - playback preview
   - trim in/out handles
   - duration readout
   - export action (`MP4`, `GIF`)
   - done/cancel
3. No advanced timeline or keyframe tools in this phase.
4. Screenshot editor remains unchanged.

## 4. Requested Feature Mapping

## 4.1 Webcam in Recordings

1. Optional webcam PiP overlay (bottom-right default).
2. User can enable/disable in settings.
3. User can choose camera device.
4. Shape options v1: circle or rounded-rect, fixed sizes (`Small`, `Medium`, `Large`).

## 4.2 Microphone and macOS Audio

1. Independent toggles:
   - `Record System Audio`
   - `Record Microphone`
2. Per-source level meters in settings/recording HUD.
3. Device picker for mic input.

## 4.3 Mouse Click and Keystroke Highlighting

1. Mouse click highlights:
   - use native ScreenCaptureKit click visualization where available.
2. Keystrokes:
   - capture key events and render compact key badge overlay.
   - monitor only while recording is active.
   - persist only rendered key tokens for overlay timing, not raw key log history.

## 4.4 Reduce Notification Interruptions (Best Effort)

1. Best-effort approach:
   - Pre-record prompt to enable Focus/Do Not Disturb.
   - Post-start reminder if Focus appears disabled.
2. Do not rely on private APIs.
3. Keep user-facing copy explicit: "Reduce notifications (best effort)", not "Hide all notifications."

## 4.5 Built-in Trimming

1. Trim start/end in single-track editor.
2. Export trimmed result without re-recording.
3. Preserve original recording file until user confirms export.

## 5. Technical Architecture

## 5.1 Current Baseline

Current architecture:

1. Swift host owns UI, region capture, windows, permissions.
2. Rust core owns annotation document model and rendering for images.
3. FFI boundary is explicit C ABI (`ffi/vivyshot_core.h`).

## 5.2 Proposed Recording Architecture

Keep this split for speed:

1. Swift/macOS layer (platform adapter):
   - Screen capture stream and file recording.
   - Camera/microphone permissions and device selection.
   - Live recording HUD and region control.
2. Rust core (portable layer):
   - recording session model (events, trims, export intents)
   - shared validation/state machine
   - format-agnostic metadata and settings schema
   - optional future cross-platform export worker

Rationale:

1. Capture APIs are deeply platform-specific (macOS uses ScreenCaptureKit).
2. Keeping capture in host avoids high-frequency frame copies over FFI.
3. Rust still owns portable "what to do with recording" state.

## 5.3 Data Flow (Video Mode)

1. User selects region.
2. Host creates `RecordingSessionConfig`.
3. Host starts ScreenCaptureKit stream and recording output.
4. Host records sidecar event stream (keystrokes/click metadata, webcam layout).
5. Stop recording -> finalize clip file.
6. Host sends session + clip metadata to Rust session model.
7. Trim editor updates trim range in Rust model.
8. Export command generates MP4/GIF output.

## 5.4 Timing and Sync Contract

1. Recording session uses a single monotonic timebase (`host time`) with `t0` at recording start.
2. Sidecar events (click/keystroke/webcam layout changes) are stored as nanoseconds relative to `t0`.
3. Pause/resume updates effective timeline by excluding paused spans from export-time event placement.
4. Trim/export applies deterministic remap: `t_out = t_event - trim_start - paused_before_event`.
5. Acceptance target for overlay sync error: <= 100 ms on exported media.

## 6. Rust Core Integration Plan

Add a new Rust module group under `vivyshot-rs/crates/vivyshot-core` and expose C ABI adapters from `vivyshot-rs/crates/vivyshot-ffi`:

1. `video/session.rs`: recording session state machine.
2. `video/model.rs`: serializable structs for capture settings, events, trims, export targets.
3. `video/ffi.rs`: C ABI for creating/updating/finalizing video session metadata.

Initial FFI sketch (control-plane only, no per-frame transport):

1. `vs_video_session_create(config_struct) -> handle`
2. `vs_video_session_add_key_event(handle, event_struct) -> status`
3. `vs_video_session_add_click_event(handle, event_struct) -> status`
4. `vs_video_session_set_trim(handle, start_ms, end_ms) -> status`
5. `vs_video_session_get_export_plan(handle, out_struct*) -> status`
6. `vs_video_session_destroy(handle)`

Portability strategy:

1. macOS host uses ScreenCaptureKit now.
2. Future Windows/Linux hosts can implement capture adapters and reuse same Rust video session model + FFI.

## 7. macOS Implementation Details

## 7.1 APIs and Components

1. Screen capture:
   - `SCStreamConfiguration` + `SCStream` + `SCRecordingOutput`.
2. Webcam capture:
   - `AVCaptureSession` camera pipeline captured in parallel.
3. Trim/export:
   - basic AVFoundation export flow with time ranges.
4. Input overlays:
   - mouse: native click highlight when enabled.
   - keyboard: global input monitor/event tap (requires accessibility trust).
5. Composition model (one-phase scope):
   - Record screen/audio to base file.
   - Record webcam track in parallel.
   - Export step composites webcam PiP + keystroke overlays + click overlays into final MP4/GIF.
   - Optional live webcam preview in HUD is UI-only and does not define final pixel output.

## 7.2 Required Project Changes

1. `CaptureMode.swift`
   - split capture type from area mode:
   - capture type: `screenshot | video`
   - area mode: `screen | window | selection` (existing concept)
2. `RegionSelectionOverlay.swift`
   - add left-side capture-type panel in selecting state.
3. `CaptureCoordinator.swift`
   - route to screenshot or video pipeline.
4. New files (expected):
   - `VideoCaptureCoordinator.swift`
   - `VideoRecordingSession.swift`
   - `VideoEditorWindowController.swift`
   - `VideoCaptureSettingsView.swift`
   - `VideoCompositor.swift`
   - `InputEventMonitor.swift`
5. `AppSettings.swift` + `SettingsWindowController.swift`
   - add `Video` settings section/tab.

## 8. Settings Tab Spec (Video)

Add a dedicated settings section named `Video Capture` with:

1. `Default Capture Type`: `Screenshot` or `Video`.
2. `Video Quality`: `Standard (H.264)` / `High (HEVC)`.
3. `Frame Rate`: `30` / `60`.
4. `Record System Audio` toggle.
5. `Record Microphone` toggle + device picker.
6. `Show Webcam` toggle + camera picker + size/shape.
7. `Highlight Mouse Clicks` toggle.
8. `Highlight Keystrokes` toggle.
9. `Reduce Notifications (Best Effort)` toggle.
10. `Countdown`: `Off` / `3s` / `5s`.
11. `Codec Preference`: `HEVC preferred` / `H.264 only`.
12. `Overlay Sync Debug Info` toggle (debug builds only).

## 9. Permissions and Privacy

## 9.1 Runtime Permission Requirements (TCC)

1. Screen Recording permission.
2. Microphone permission.
3. Camera permission (if webcam enabled).
4. Accessibility/Input Monitoring permission (if global keystrokes are enabled).

## 9.2 Sandbox Requirements (Hard Requirement)

The recorder must run in sandboxed builds (including App Store distribution profile). Required constraints:

1. `com.apple.security.app-sandbox = true`.
2. `com.apple.security.files.user-selected.read-write = true` for explicit user save/export targets.
3. `com.apple.security.device.audio-input = true` when microphone recording is enabled.
4. `com.apple.security.device.camera = true` when webcam overlay is enabled.
5. No private or temporary exception entitlements for recorder features.
6. Do not rely on unrestricted filesystem writes; write only to app container temp/cache and user-selected destinations.
7. Treat screen recording as TCC-driven (no dedicated entitlement); handle denial gracefully.
8. App Store/release distribution builds must always run with sandbox enabled; no unsandboxed fallback path.

## 9.3 Project Config Updates

1. Add `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` in `Info.plist`.
2. Keep entitlements file explicit and version-controlled for sandbox profile.
3. Provide clear first-run permission walkthrough.
4. Add regression check: recorder smoke test must pass with sandbox entitlements enabled.

## 9.4 App Store Compliance Requirements

1. Recorder implementation must use public APIs only.
2. Keystroke highlighting is opt-in and defaults to OFF.
3. Global input monitoring runs only while an active recording is in progress.
4. No raw keystroke history is written to disk; only overlay tokens/timestamps needed for render.
5. Feature disclosure text must be explicit during permission onboarding.

## 10. File and Format Spec

Recording outputs:

1. Working recording file: `.mp4` (default) or `.mov` intermediate when required by selected codec path.
2. Sidecar metadata: `.json` session file (trim range, overlays, devices, timestamps).
3. Export targets:
   - `MP4` (trimmed)
   - `GIF` (trimmed, max duration guardrail)

Default guardrails:

1. Max GIF length: 15s (prompt when exceeded).
2. GIF max width: 960 px by default.
3. Codec/container fallback:
   - preferred: HEVC in MP4 when available
   - fallback: H.264 in MP4
   - final fallback: MOV intermediate + re-export
4. If hardware codec is unavailable, automatically degrade to supported preset and warn in export summary.

## 11. Delivery Plan (Single Phase)

All requested recorder capabilities ship in one release milestone:

1. Left-side capture-type panel.
2. Video recording for selected region.
3. System audio + mic toggles.
4. Webcam PiP in output recording.
5. Mouse click and keystroke overlays.
6. Built-in trim editor.
7. MP4 and GIF export.
8. New `Video Capture` settings section.
9. Sandboxed/App Store-compliant distribution profile.
10. Rust video session metadata/FFI in production path.

## 12. Risks and Mitigations

1. Notification suppression is not guaranteed by public capture APIs.
   - Mitigation: explicit "best effort" wording and Focus prompt.
2. Keystroke capture needs Accessibility permission.
   - Mitigation: feature off by default until permission granted; active only during recording.
3. Mic + system audio mixing behavior can vary by configuration.
   - Mitigation: validation tests across common devices and sample rates.
4. Webcam compositing can increase CPU/GPU load.
   - Mitigation: fixed FPS presets, bounded PiP sizes, quality fallback.
5. One-phase scope increases integration risk.
   - Mitigation: strict test matrix and hard release gate criteria.

## 12.1 Release Test Matrix (Required)

1. Sandbox enabled build: record -> trim -> export (`MP4`, `GIF`) passes.
2. Permission denied scenarios: screen/mic/camera/accessibility show guidance, no crash.
3. Multi-display selection capture works with correct region bounds.
4. Pause/resume retains audio/video/event sync within target.
5. Overlay timing validation: click/keystroke sync error <= 100 ms.
6. 10-minute recording stability run has no runaway memory growth.
7. App Store packaging validation passes with release entitlements.

## 13. Acceptance Criteria

1. User can switch capture type on overlay (`Screenshot` default, `Video` secondary).
2. User can record selected region and save trimmed MP4 in one flow.
3. User can enable mic + system audio and produce playable output.
4. User can enable webcam PiP and it appears in exported output.
5. User can enable mouse click and keystroke overlays and see them in exported output.
6. Settings include a dedicated `Video Capture` section with required toggles.
7. Post-record editor is simple and trim-focused.
8. Rust core stores/validates video session metadata through explicit FFI calls.
9. Video recording, trim, and export work in a sandboxed app build.
10. No recorder path depends on private entitlements or unsandboxed filesystem access.
11. Permission-denied states (screen/mic/camera/accessibility) show clear recovery guidance and do not crash.
12. Release build passes App Store distribution validation.

## 14. Research References

Primary references used for feasibility:

1. ScreenCaptureKit Rust bindings docs (`SCStreamConfiguration`, audio/mic/cursor/click flags, recording output APIs): https://docs.rs/screencapturekit/latest/screencapturekit/shareable_content/struct.SCStreamConfiguration.html
2. `SCStream` recording output integration (`add_recording_output`, lifecycle): https://docs.rs/screencapturekit/latest/screencapturekit/stream/struct.SCStream.html
3. `SCRecordingOutput` / `SCRecordingOutputConfiguration` (recording outputs/codecs/file types): https://docs.rs/screencapturekit/latest/screencapturekit/stream/struct.SCRecordingOutput.html
4. Cross-platform capture crate option (`crabgrab`): https://docs.rs/crabgrab/latest/crabgrab/
5. Cross-platform audio I/O (`cpal`): https://docs.rs/cpal/latest/cpal/
6. Webcam capture library option (`nokhwa`): https://github.com/l1npengtul/nokhwa
7. Global input event capture (`rdev`) and macOS accessibility requirement note: https://docs.rs/rdev/latest/rdev/
8. AVFoundation export/trimming workflow references:
   - https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html
   - https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html

Notes:

1. Notification auto-hide is marked best-effort because there is no single guaranteed public API in this stack to suppress all system notifications for third-party recorders.
2. This draft intentionally separates "fast ship on macOS" from "portable Rust session model" to reduce delivery risk.
