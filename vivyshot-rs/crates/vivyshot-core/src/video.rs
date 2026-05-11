use crate::timeline::Timeline;
use crate::types::{
    AffineTransform, TimelineTrackSummary, VideoExportBitratePreset, VideoExportCodec,
    VideoExportContainer, VideoExportFrameRate, VideoExportPreset, VideoExportQuality,
    VideoExportScale, VideoPostRecordingCompositionPlan,
};
use serde::{Deserialize, Serialize};

pub use crate::types::{
    VideoExportContext, VideoExportDecision, VideoExportPlan, VideoOverlayClipWindow,
    VideoOverlayLabelLayout, VIDEO_EXPORT_TARGET_GIF, VIDEO_EXPORT_TARGET_MP4,
    VIDEO_KEY_OVERLAY_FADE_DURATION_SECONDS, VIDEO_KEY_OVERLAY_FADE_HOLD_KEYTIME,
    VIDEO_KEY_OVERLAY_FADE_IN_KEYTIME, VIDEO_PLAN_MODE_COMPOSITE_MP4, VIDEO_PLAN_MODE_PASSTHROUGH,
    VIDEO_TEXT_OVERLAY_FADE_HOLD_KEYTIME, VIDEO_TEXT_OVERLAY_FADE_IN_KEYTIME,
    VIDEO_TEXT_OVERLAY_MIN_FADE_DURATION_SECONDS, VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS,
};

pub const VIDEO_PROJECT_SNAPSHOT_VERSION: u32 = 1;
pub const VIDEO_RENDER_TARGET_PREVIEW: u8 = 0;
pub const VIDEO_RENDER_TARGET_EXPORT: u8 = 1;
pub const VIDEO_RENDER_ITEM_WEBCAM: u8 = 1;
pub const VIDEO_RENDER_ITEM_KEYSTROKE: u8 = 2;
pub const VIDEO_WEBCAM_SHAPE_ROUNDED_RECT: u8 = 0;
pub const VIDEO_WEBCAM_SHAPE_CIRCLE: u8 = 1;
pub const VIDEO_WEBCAM_ASPECT_SQUARE: u8 = 0;
pub const VIDEO_WEBCAM_ASPECT_FOUR_THREE: u8 = 1;
pub const VIDEO_WEBCAM_ASPECT_SIXTEEN_NINE: u8 = 2;
pub const VIDEO_KEYSTROKE_STYLE_COMPACT: u8 = 0;
pub const VIDEO_KEYSTROKE_STYLE_GLASS: u8 = 1;
pub const VIDEO_KEYSTROKE_SIZE_SMALL: u8 = 0;
pub const VIDEO_KEYSTROKE_SIZE_MEDIUM: u8 = 1;
pub const VIDEO_KEYSTROKE_SIZE_LARGE: u8 = 2;
pub const VIDEO_PRO_REASON_WEBCAM_OVERLAY: u32 = 1 << 0;
pub const VIDEO_PRO_REASON_KEYSTROKE_OVERLAY: u32 = 1 << 1;
pub const VIDEO_PRO_REASON_MICROPHONE_AUDIO: u32 = 1 << 2;
pub const VIDEO_PRO_REASON_GIF_EXPORT: u32 = 1 << 3;
pub const VIDEO_PRO_REASON_HEVC_EXPORT: u32 = 1 << 4;
pub const VIDEO_PRO_REASON_SIXTY_FPS: u32 = 1 << 5;
pub const VIDEO_PRO_REASON_HIGH_QUALITY: u32 = 1 << 6;
pub const VIDEO_PRO_REASON_HIGH_BITRATE: u32 = 1 << 7;
pub const VIDEO_PRO_REASON_BAKED_TRANSITION: u32 = 1 << 8;

const VIDEO_KEYSTROKE_VISIBLE_WINDOW_MS: u32 = 1_350;
const VIDEO_KEYSTROKE_VISIBLE_LIMIT: usize = 3;

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct VideoNormalizedRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VideoSourceMetadata {
    pub duration_ms: u32,
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub has_audio: bool,
    pub has_webcam_asset: bool,
    pub has_microphone_audio: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VideoKeyOverlayEvent {
    pub timestamp_ms: u32,
    pub token: String,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct VideoClickOverlayEvent {
    pub timestamp_ms: u32,
    pub normalized_x: f32,
    pub normalized_y: f32,
    pub button: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct VideoOverlayPlacementKeyframe {
    pub timestamp_ms: u32,
    pub frame: VideoNormalizedRect,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct VideoWebcamOverlay {
    pub enabled: bool,
    pub shape: u8,
    pub aspect_ratio: u8,
    pub asset_id: u32,
    pub placement: Vec<VideoOverlayPlacementKeyframe>,
}

impl Default for VideoWebcamOverlay {
    fn default() -> Self {
        Self {
            enabled: false,
            shape: VIDEO_WEBCAM_SHAPE_ROUNDED_RECT,
            aspect_ratio: VIDEO_WEBCAM_ASPECT_SQUARE,
            asset_id: 1,
            placement: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct VideoKeystrokeOverlay {
    pub enabled: bool,
    pub style: u8,
    pub size: u8,
    pub placement: Vec<VideoOverlayPlacementKeyframe>,
}

impl Default for VideoKeystrokeOverlay {
    fn default() -> Self {
        Self {
            enabled: false,
            style: VIDEO_KEYSTROKE_STYLE_COMPACT,
            size: VIDEO_KEYSTROKE_SIZE_MEDIUM,
            placement: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct VideoOverlaySet {
    pub key_events: Vec<VideoKeyOverlayEvent>,
    pub click_events: Vec<VideoClickOverlayEvent>,
    pub webcam: VideoWebcamOverlay,
    pub keystroke: VideoKeystrokeOverlay,
    pub text_overlay_count: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoRenderPlanQuery {
    pub time_ms: u32,
    pub render_width: u32,
    pub render_height: u32,
    pub target: u8,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct VideoRenderItem {
    pub kind: u8,
    /// Pixel-space rectangle in render target coordinates, with x/y measured from the top-left.
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub opacity: f32,
    pub style_flags: u32,
    pub text_offset: u32,
    pub text_len: u32,
    pub asset_id: u32,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct VideoRenderPlan {
    pub items: Vec<VideoRenderItem>,
    pub text_bytes: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoProjectExportOptions {
    pub target: u8,
    pub codec: u8,
    pub frame_rate: u8,
    pub quality: u8,
    pub bitrate: u8,
    pub includes_baked_transition: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoProjectProRequirement {
    pub reasons_mask: u32,
}

pub struct VideoProject {
    source: VideoSourceMetadata,
    timeline: Timeline,
    overlays: VideoOverlaySet,
}

#[derive(Serialize, Deserialize)]
struct VideoProjectSnapshot {
    version: u32,
    source: VideoSourceMetadata,
    overlays: VideoOverlaySet,
}

impl VideoProject {
    pub fn new(source: VideoSourceMetadata) -> Option<Self> {
        if source.duration_ms == 0 || source.width == 0 || source.height == 0 {
            return None;
        }
        let mut timeline = Timeline::new(source.duration_ms, source.width, source.height)?;
        timeline.bootstrap_capture_tracks(source.has_audio, source.has_webcam_asset);
        Some(Self {
            source,
            timeline,
            overlays: VideoOverlaySet::default(),
        })
    }

    pub fn source(&self) -> VideoSourceMetadata {
        self.source
    }

    pub fn overlays(&self) -> &VideoOverlaySet {
        &self.overlays
    }

    pub fn set_webcam_overlay(
        &mut self,
        enabled: bool,
        shape: u8,
        aspect_ratio: u8,
        asset_id: u32,
    ) -> bool {
        if !matches!(
            shape,
            VIDEO_WEBCAM_SHAPE_ROUNDED_RECT | VIDEO_WEBCAM_SHAPE_CIRCLE
        ) || !matches!(
            aspect_ratio,
            VIDEO_WEBCAM_ASPECT_SQUARE
                | VIDEO_WEBCAM_ASPECT_FOUR_THREE
                | VIDEO_WEBCAM_ASPECT_SIXTEEN_NINE
        ) {
            return false;
        }
        self.overlays.webcam.enabled = enabled;
        self.overlays.webcam.shape = shape;
        self.overlays.webcam.aspect_ratio = aspect_ratio;
        self.overlays.webcam.asset_id = asset_id;
        true
    }

    pub fn set_keystroke_overlay(&mut self, enabled: bool, style: u8, size: u8) -> bool {
        if !matches!(
            style,
            VIDEO_KEYSTROKE_STYLE_COMPACT | VIDEO_KEYSTROKE_STYLE_GLASS
        ) || !matches!(
            size,
            VIDEO_KEYSTROKE_SIZE_SMALL | VIDEO_KEYSTROKE_SIZE_MEDIUM | VIDEO_KEYSTROKE_SIZE_LARGE
        ) {
            return false;
        }
        self.overlays.keystroke.enabled = enabled;
        self.overlays.keystroke.style = style;
        self.overlays.keystroke.size = size;
        true
    }

    pub fn push_webcam_placement(&mut self, timestamp_ms: u32, frame: VideoNormalizedRect) {
        push_placement(
            &mut self.overlays.webcam.placement,
            timestamp_ms,
            normalize_video_rect(frame),
        );
    }

    pub fn push_keystroke_placement(&mut self, timestamp_ms: u32, frame: VideoNormalizedRect) {
        push_placement(
            &mut self.overlays.keystroke.placement,
            timestamp_ms,
            normalize_video_rect(frame),
        );
    }

    pub fn add_key_event(&mut self, timestamp_ms: u32, token: &str) -> bool {
        let trimmed = token.trim();
        if trimmed.is_empty() {
            return false;
        }
        let token: String = trimmed.chars().take(64).collect();
        self.overlays.key_events.push(VideoKeyOverlayEvent {
            timestamp_ms,
            token,
        });
        self.overlays
            .key_events
            .sort_by_key(|event| event.timestamp_ms);
        true
    }

    pub fn add_click_event(
        &mut self,
        timestamp_ms: u32,
        normalized_x: f32,
        normalized_y: f32,
        button: u32,
    ) -> bool {
        let Some((x, y)) = normalize_click_point(normalized_x, normalized_y) else {
            return false;
        };
        if let Some(last) = self.overlays.click_events.last() {
            if click_event_is_duplicate(
                last.timestamp_ms as u64,
                last.button,
                last.normalized_x,
                last.normalized_y,
                timestamp_ms as u64,
                button,
                x,
                y,
                0.0001,
            ) {
                return false;
            }
        }
        self.overlays.click_events.push(VideoClickOverlayEvent {
            timestamp_ms,
            normalized_x: x,
            normalized_y: y,
            button,
        });
        true
    }

    pub fn export_plan(&self) -> Option<VideoExportPlan> {
        let key_count = if self.overlays.keystroke.enabled {
            self.overlays.key_events.len().max(1).min(u32::MAX as usize) as u32
        } else {
            0
        };
        let click_count = self.overlays.click_events.len().min(u32::MAX as usize) as u32;
        compute_video_export_plan(
            0,
            self.source.duration_ms,
            key_count,
            click_count,
            self.export_context(),
        )
    }

    pub fn render_plan(&self, query: VideoRenderPlanQuery) -> Option<VideoRenderPlan> {
        if query.render_width == 0 || query.render_height == 0 {
            return None;
        }
        if !matches!(
            query.target,
            VIDEO_RENDER_TARGET_PREVIEW | VIDEO_RENDER_TARGET_EXPORT
        ) {
            return None;
        }

        let mut plan = VideoRenderPlan::default();
        let render_width = query.render_width as f32;
        let render_height = query.render_height as f32;

        if self.source.has_webcam_asset && self.overlays.webcam.enabled {
            let placement = placement_at(
                &self.overlays.webcam.placement,
                query.time_ms,
                VideoNormalizedRect {
                    x: 0.72,
                    y: 0.07,
                    width: 0.22,
                    height: 0.22,
                },
            );
            let rect = constrain_webcam_rect(
                denormalize_rect(placement, render_width, render_height),
                render_width,
                render_height,
                self.overlays.webcam.shape,
                self.overlays.webcam.aspect_ratio,
                2.0,
                2.0,
            );
            if rect.width > 0.0 && rect.height > 0.0 {
                plan.items.push(VideoRenderItem {
                    kind: VIDEO_RENDER_ITEM_WEBCAM,
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height,
                    opacity: 1.0,
                    style_flags: webcam_style_flags(
                        self.overlays.webcam.shape,
                        self.overlays.webcam.aspect_ratio,
                    ),
                    text_offset: 0,
                    text_len: 0,
                    asset_id: self.overlays.webcam.asset_id,
                });
            }
        }

        if self.overlays.keystroke.enabled {
            let text = self.visible_keystroke_text(query.time_ms);
            let placement = placement_at(
                &self.overlays.keystroke.placement,
                query.time_ms,
                VideoNormalizedRect {
                    x: 0.30,
                    y: 0.07,
                    width: 0.40,
                    height: 0.12,
                },
            );
            let mut rect = denormalize_rect(placement, render_width, render_height);
            if rect.width <= 4.0 || rect.height <= 4.0 {
                if let Some(layout) = derive_key_overlay_label_layout(
                    render_width,
                    render_height,
                    text.chars().count() as u32,
                ) {
                    rect = VideoPixelRect {
                        x: (render_width - layout.width) * 0.5,
                        y: layout.y,
                        width: layout.width,
                        height: layout.height,
                    };
                }
            }
            if rect.width > 0.0 && rect.height > 0.0 {
                let offset = plan.text_bytes.len().min(u32::MAX as usize) as u32;
                plan.text_bytes.extend_from_slice(text.as_bytes());
                let len = text.len().min(u32::MAX as usize) as u32;
                plan.items.push(VideoRenderItem {
                    kind: VIDEO_RENDER_ITEM_KEYSTROKE,
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height,
                    opacity: 1.0,
                    style_flags: keystroke_style_flags(
                        self.overlays.keystroke.style,
                        self.overlays.keystroke.size,
                    ),
                    text_offset: offset,
                    text_len: len,
                    asset_id: 0,
                });
            }
        }

        Some(plan)
    }

    pub fn pro_requirement(
        &self,
        options: VideoProjectExportOptions,
    ) -> Option<VideoProjectProRequirement> {
        if !matches!(
            options.target,
            VIDEO_EXPORT_TARGET_MP4 | VIDEO_EXPORT_TARGET_GIF
        ) {
            return None;
        }
        let mut mask = 0u32;
        if self.source.has_webcam_asset && self.overlays.webcam.enabled {
            mask |= VIDEO_PRO_REASON_WEBCAM_OVERLAY;
        }
        if self.overlays.keystroke.enabled {
            mask |= VIDEO_PRO_REASON_KEYSTROKE_OVERLAY;
        }
        if options.target == VIDEO_EXPORT_TARGET_MP4 && self.source.has_microphone_audio {
            mask |= VIDEO_PRO_REASON_MICROPHONE_AUDIO;
        }
        if options.target == VIDEO_EXPORT_TARGET_GIF {
            mask |= VIDEO_PRO_REASON_GIF_EXPORT;
        }
        if options.target == VIDEO_EXPORT_TARGET_MP4 {
            if options.codec == 1 {
                mask |= VIDEO_PRO_REASON_HEVC_EXPORT;
            }
            if options.frame_rate != 0 {
                mask |= VIDEO_PRO_REASON_SIXTY_FPS;
            }
            if options.quality != 0 {
                mask |= VIDEO_PRO_REASON_HIGH_QUALITY;
            }
            if options.bitrate != 0 {
                mask |= VIDEO_PRO_REASON_HIGH_BITRATE;
            }
        }
        if options.includes_baked_transition {
            mask |= VIDEO_PRO_REASON_BAKED_TRANSITION;
        }
        Some(VideoProjectProRequirement { reasons_mask: mask })
    }

    pub fn serialize_snapshot_json(&self) -> Result<Vec<u8>, serde_json::Error> {
        let snapshot = VideoProjectSnapshot {
            version: VIDEO_PROJECT_SNAPSHOT_VERSION,
            source: self.source,
            overlays: self.overlays.clone(),
        };
        serde_json::to_vec(&snapshot)
    }

    pub fn deserialize_snapshot_json(json: &[u8]) -> Option<Self> {
        let snapshot: VideoProjectSnapshot = serde_json::from_slice(json).ok()?;
        if snapshot.version != VIDEO_PROJECT_SNAPSHOT_VERSION {
            return None;
        }
        let mut project = Self::new(snapshot.source)?;
        project.overlays = snapshot.overlays;
        Some(project)
    }

    fn export_context(&self) -> VideoExportContext {
        let summaries: Vec<TimelineTrackSummary> = self
            .timeline
            .tracks()
            .iter()
            .map(|track| TimelineTrackSummary {
                kind: track.kind,
                visible: track.visible,
                clip_count: track.clips.len().min(u32::MAX as usize) as u32,
            })
            .collect();
        derive_video_export_context(
            self.source.has_audio,
            self.source.has_webcam_asset && self.overlays.webcam.enabled,
            &summaries,
        )
    }

    fn visible_keystroke_text(&self, time_ms: u32) -> String {
        let visible: Vec<&VideoKeyOverlayEvent> = self
            .overlays
            .key_events
            .iter()
            .filter(|event| {
                event.timestamp_ms <= time_ms
                    && time_ms.saturating_sub(event.timestamp_ms)
                        <= VIDEO_KEYSTROKE_VISIBLE_WINDOW_MS
            })
            .rev()
            .take(VIDEO_KEYSTROKE_VISIBLE_LIMIT)
            .collect();
        if visible.is_empty() {
            return "⌘K".to_string();
        }
        visible
            .into_iter()
            .rev()
            .map(|event| event.token.as_str())
            .collect::<Vec<_>>()
            .join("  ")
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct VideoPixelRect {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

pub fn normalize_video_rect(frame: VideoNormalizedRect) -> VideoNormalizedRect {
    let source = if !frame.x.is_finite()
        || !frame.y.is_finite()
        || !frame.width.is_finite()
        || !frame.height.is_finite()
        || frame.width <= 0.0
        || frame.height <= 0.0
    {
        VideoNormalizedRect {
            x: 0.0,
            y: 0.0,
            width: 0.2,
            height: 0.2,
        }
    } else {
        frame
    };
    let width = source.width.clamp(0.04, 1.0);
    let height = source.height.clamp(0.04, 1.0);
    let x = source.x.clamp(0.0, 1.0 - width);
    let y = source.y.clamp(0.0, 1.0 - height);
    VideoNormalizedRect {
        x,
        y,
        width,
        height,
    }
}

fn push_placement(
    placements: &mut Vec<VideoOverlayPlacementKeyframe>,
    timestamp_ms: u32,
    frame: VideoNormalizedRect,
) {
    let entry = VideoOverlayPlacementKeyframe {
        timestamp_ms,
        frame,
    };
    placements.push(entry);
    placements.sort_by_key(|placement| placement.timestamp_ms);
    placements.dedup_by(|left, right| {
        left.timestamp_ms == right.timestamp_ms && left.frame == right.frame
    });
}

fn placement_at(
    placements: &[VideoOverlayPlacementKeyframe],
    time_ms: u32,
    fallback: VideoNormalizedRect,
) -> VideoNormalizedRect {
    let mut frame = normalize_video_rect(fallback);
    for placement in placements {
        if placement.timestamp_ms <= time_ms {
            frame = normalize_video_rect(placement.frame);
        } else {
            break;
        }
    }
    frame
}

fn denormalize_rect(
    rect: VideoNormalizedRect,
    render_width: f32,
    render_height: f32,
) -> VideoPixelRect {
    let top_y = (1.0 - rect.y - rect.height).clamp(0.0, 1.0);
    VideoPixelRect {
        x: rect.x * render_width,
        y: top_y * render_height,
        width: rect.width * render_width,
        height: rect.height * render_height,
    }
}

fn constrain_webcam_rect(
    source: VideoPixelRect,
    render_width: f32,
    render_height: f32,
    shape: u8,
    aspect_ratio: u8,
    min_width: f32,
    min_height: f32,
) -> VideoPixelRect {
    if render_width <= 0.0 || render_height <= 0.0 {
        return VideoPixelRect::default();
    }

    let ratio = if shape == VIDEO_WEBCAM_SHAPE_CIRCLE {
        1.0
    } else {
        webcam_aspect_ratio_value(aspect_ratio)
    };
    let min_width = min_width.clamp(1.0, render_width);
    let min_height = min_height.clamp(1.0, render_height);
    let mut width = source.width.clamp(min_width, render_width);
    let mut height = width / ratio;

    if height < min_height {
        height = min_height;
        width = height * ratio;
    }
    if height > render_height {
        height = render_height;
        width = height * ratio;
    }
    if width > render_width {
        width = render_width;
        height = width / ratio;
    }

    let source_mid_x = source.x + source.width * 0.5;
    let source_mid_y = source.y + source.height * 0.5;
    let x = (source_mid_x - width * 0.5).clamp(0.0, render_width - width);
    let y = (source_mid_y - height * 0.5).clamp(0.0, render_height - height);

    VideoPixelRect {
        x,
        y,
        width,
        height,
    }
}

fn webcam_aspect_ratio_value(aspect_ratio: u8) -> f32 {
    match aspect_ratio {
        VIDEO_WEBCAM_ASPECT_FOUR_THREE => 4.0 / 3.0,
        VIDEO_WEBCAM_ASPECT_SIXTEEN_NINE => 16.0 / 9.0,
        _ => 1.0,
    }
}

fn webcam_style_flags(shape: u8, aspect_ratio: u8) -> u32 {
    shape as u32 | ((aspect_ratio as u32) << 8)
}

fn keystroke_style_flags(style: u8, size: u8) -> u32 {
    style as u32 | ((size as u32) << 8)
}

pub fn compute_video_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: VideoExportContext,
) -> Option<VideoExportPlan> {
    if trim_end_ms < trim_start_ms {
        return None;
    }

    let include_audio = context.source_has_audio && context.audio_track_visible;
    let include_webcam = context.source_has_webcam_asset && context.webcam_track_visible;
    let has_text_overlays = context.text_overlay_count > 0;
    let has_key_overlays = key_event_count > 0;
    let overlay_item_count = context.text_overlay_count.saturating_add(key_event_count);
    let needs_custom_compositor = include_webcam
        || has_text_overlays
        || has_key_overlays
        || (context.source_has_audio && !include_audio);
    let plan_mode = if needs_custom_compositor {
        VIDEO_PLAN_MODE_COMPOSITE_MP4
    } else {
        VIDEO_PLAN_MODE_PASSTHROUGH
    };

    Some(VideoExportPlan {
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        plan_mode,
        include_audio,
        include_webcam,
        text_overlay_count: context.text_overlay_count,
        overlay_item_count,
        requires_intermediate_for_gif: needs_custom_compositor,
        needs_custom_compositor,
    })
}

pub fn derive_video_export_context(
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    tracks: &[TimelineTrackSummary],
) -> VideoExportContext {
    let mut audio_track_visible = false;
    let mut webcam_track_visible = false;
    let mut text_overlay_count = 0u32;

    for track in tracks {
        if !track.visible || track.clip_count == 0 {
            continue;
        }

        match track.kind {
            2 => audio_track_visible = true,
            1 => webcam_track_visible = true,
            3 => {
                text_overlay_count = text_overlay_count.saturating_add(track.clip_count);
            }
            _ => {}
        }
    }

    VideoExportContext {
        source_has_audio,
        source_has_webcam_asset,
        audio_track_visible,
        webcam_track_visible,
        text_overlay_count,
    }
}

pub fn derive_video_export_decision(
    target: u8,
    plan: VideoExportPlan,
) -> Option<VideoExportDecision> {
    let is_composite =
        plan.plan_mode == VIDEO_PLAN_MODE_COMPOSITE_MP4 || plan.needs_custom_compositor;
    let requires_intermediate_for_gif = plan.requires_intermediate_for_gif || is_composite;
    let use_custom_compositor = match target {
        VIDEO_EXPORT_TARGET_MP4 => is_composite,
        VIDEO_EXPORT_TARGET_GIF => requires_intermediate_for_gif,
        _ => return None,
    };

    Some(VideoExportDecision {
        use_custom_compositor,
        requires_intermediate_for_gif,
        include_audio: plan.include_audio,
        include_webcam: plan.include_webcam,
    })
}

pub fn preferred_video_export_container(codec: VideoExportCodec) -> VideoExportContainer {
    match codec {
        VideoExportCodec::H264 => VideoExportContainer::Mp4,
        VideoExportCodec::Hevc => VideoExportContainer::Mov,
    }
}

pub fn allowed_video_export_containers(
    codec: VideoExportCodec,
) -> (VideoExportContainer, VideoExportContainer) {
    match codec {
        VideoExportCodec::H264 => (VideoExportContainer::Mp4, VideoExportContainer::Mov),
        VideoExportCodec::Hevc => (VideoExportContainer::Mov, VideoExportContainer::Mp4),
    }
}

pub fn best_video_export_container(
    codec: VideoExportCodec,
    supports_mp4: bool,
    supports_mov: bool,
) -> Option<VideoExportContainer> {
    let (preferred, fallback) = allowed_video_export_containers(codec);
    match preferred {
        VideoExportContainer::Mp4 if supports_mp4 => Some(VideoExportContainer::Mp4),
        VideoExportContainer::Mov if supports_mov => Some(VideoExportContainer::Mov),
        _ => match fallback {
            VideoExportContainer::Mp4 if supports_mp4 => Some(VideoExportContainer::Mp4),
            VideoExportContainer::Mov if supports_mov => Some(VideoExportContainer::Mov),
            _ => None,
        },
    }
}

pub fn best_video_export_preset(
    codec: VideoExportCodec,
    quality: VideoExportQuality,
    compatible_mask: u32,
) -> Option<VideoExportPreset> {
    let candidates: &[VideoExportPreset] = match (codec, quality) {
        (VideoExportCodec::H264, VideoExportQuality::Standard) => &[
            VideoExportPreset::Resolution1920x1080,
            VideoExportPreset::Resolution1280x720,
            VideoExportPreset::MediumQuality,
            VideoExportPreset::HighestQuality,
        ],
        (VideoExportCodec::H264, VideoExportQuality::High) => &[
            VideoExportPreset::HighestQuality,
            VideoExportPreset::Resolution1920x1080,
            VideoExportPreset::Resolution1280x720,
        ],
        (VideoExportCodec::Hevc, VideoExportQuality::Standard) => &[
            VideoExportPreset::HevcResolution1920x1080,
            VideoExportPreset::HevcHighestQuality,
            VideoExportPreset::HighestQuality,
        ],
        (VideoExportCodec::Hevc, VideoExportQuality::High) => &[
            VideoExportPreset::HevcHighestQuality,
            VideoExportPreset::HevcResolution1920x1080,
            VideoExportPreset::HighestQuality,
        ],
    };

    candidates
        .iter()
        .copied()
        .find(|preset| compatible_mask & preset_compatibility_bit(*preset) != 0)
        .or(Some(VideoExportPreset::HighestQuality))
}

pub fn estimated_video_file_length_limit(
    duration_seconds: f64,
    codec: VideoExportCodec,
    frame_rate: VideoExportFrameRate,
    quality: VideoExportQuality,
    scale: VideoExportScale,
    bitrate: VideoExportBitratePreset,
) -> Option<i64> {
    if !duration_seconds.is_finite() || duration_seconds <= 0.0 {
        return None;
    }

    let mut video_bitrate = bitrate.base_bits_per_second();
    video_bitrate *= quality.multiplier();
    video_bitrate *= frame_rate.multiplier();
    video_bitrate *= scale.multiplier();
    video_bitrate *= codec.compression_multiplier();

    let total_bits_per_second = video_bitrate.round().max(2_000_000.0);
    let bytes = (duration_seconds * total_bits_per_second) / 8.0;
    Some(bytes.ceil() as i64)
}

pub fn post_recording_video_composition_plan(
    natural_width: f32,
    natural_height: f32,
    preferred_transform: AffineTransform,
    scale: VideoExportScale,
) -> Option<VideoPostRecordingCompositionPlan> {
    if !natural_width.is_finite()
        || !natural_height.is_finite()
        || natural_width <= 0.0
        || natural_height <= 0.0
        || !preferred_transform.a.is_finite()
        || !preferred_transform.b.is_finite()
        || !preferred_transform.c.is_finite()
        || !preferred_transform.d.is_finite()
        || !preferred_transform.tx.is_finite()
        || !preferred_transform.ty.is_finite()
    {
        return None;
    }

    let scale_factor = scale.factor() as f32;
    let scaled = AffineTransform {
        a: preferred_transform.a * scale_factor,
        b: preferred_transform.b * scale_factor,
        c: preferred_transform.c * scale_factor,
        d: preferred_transform.d * scale_factor,
        tx: preferred_transform.tx,
        ty: preferred_transform.ty,
    };

    let corners = [
        transform_point(scaled, 0.0, 0.0),
        transform_point(scaled, natural_width, 0.0),
        transform_point(scaled, 0.0, natural_height),
        transform_point(scaled, natural_width, natural_height),
    ];
    let (min_x, max_x) = corners
        .iter()
        .map(|(x, _)| *x)
        .fold((f32::INFINITY, f32::NEG_INFINITY), |(min, max), value| {
            (min.min(value), max.max(value))
        });
    let (min_y, max_y) = corners
        .iter()
        .map(|(_, y)| *y)
        .fold((f32::INFINITY, f32::NEG_INFINITY), |(min, max), value| {
            (min.min(value), max.max(value))
        });

    let render_width = u32::max(2, rounded_even_dimension(max_x - min_x));
    let render_height = u32::max(2, rounded_even_dimension(max_y - min_y));
    let translated = concatenate(
        scaled,
        AffineTransform {
            a: 1.0,
            b: 0.0,
            c: 0.0,
            d: 1.0,
            tx: -min_x,
            ty: -min_y,
        },
    );

    Some(VideoPostRecordingCompositionPlan {
        render_width,
        render_height,
        transform: translated,
    })
}

pub fn derive_key_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
) -> Option<VideoOverlayLabelLayout> {
    if !render_width.is_finite()
        || !render_height.is_finite()
        || render_width <= 0.0
        || render_height <= 0.0
    {
        return None;
    }

    let height = (render_height * 0.085).clamp(34.0, 58.0);
    let max_width = render_width * 0.72;
    let width = (char_count.saturating_mul(18).max(84) as f32).min(max_width);
    let y = (render_height * 0.07).max(18.0);
    let font_size = (height * 0.46).max(16.0);
    Some(VideoOverlayLabelLayout {
        width: width.max(1.0),
        height,
        y,
        font_size,
    })
}

pub fn derive_text_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
) -> Option<VideoOverlayLabelLayout> {
    if !render_width.is_finite()
        || !render_height.is_finite()
        || render_width <= 0.0
        || render_height <= 0.0
    {
        return None;
    }

    let height = (render_height * 0.09).clamp(34.0, 62.0);
    let max_width = render_width * 0.78;
    let width = (char_count.saturating_mul(14).max(90) as f32).min(max_width);
    let y = (render_height * 0.12).max(20.0);
    let font_size = (height * 0.42).max(15.0);
    Some(VideoOverlayLabelLayout {
        width: width.max(1.0),
        height,
        y,
        font_size,
    })
}

pub fn derive_overlay_clip_window(
    clip_start_seconds: f64,
    clip_end_seconds: f64,
    trim_start_seconds: f64,
    min_visible_seconds: f64,
) -> Option<VideoOverlayClipWindow> {
    if !clip_start_seconds.is_finite()
        || !clip_end_seconds.is_finite()
        || !trim_start_seconds.is_finite()
        || !min_visible_seconds.is_finite()
    {
        return None;
    }

    let start = clip_start_seconds - trim_start_seconds;
    let end = clip_end_seconds - trim_start_seconds;
    let display_start = start.max(0.0);
    let display_end = end.max(display_start);
    if display_end - display_start < min_visible_seconds.max(0.0) {
        return None;
    }

    Some(VideoOverlayClipWindow {
        start_seconds: display_start,
        end_seconds: display_end,
    })
}

pub fn overlay_fade_duration_seconds(
    window: VideoOverlayClipWindow,
    min_duration_seconds: f64,
) -> Option<f64> {
    if !window.start_seconds.is_finite()
        || !window.end_seconds.is_finite()
        || !min_duration_seconds.is_finite()
    {
        return None;
    }
    if window.end_seconds < window.start_seconds {
        return None;
    }

    Some((window.end_seconds - window.start_seconds).max(min_duration_seconds.max(0.0)))
}

pub fn normalize_click_point(normalized_x: f32, normalized_y: f32) -> Option<(f32, f32)> {
    if !normalized_x.is_finite() || !normalized_y.is_finite() {
        return None;
    }
    Some((normalized_x.clamp(0.0, 1.0), normalized_y.clamp(0.0, 1.0)))
}

#[allow(clippy::too_many_arguments)]
pub fn click_event_is_duplicate(
    last_timestamp_ns: u64,
    last_button: u32,
    last_x: f32,
    last_y: f32,
    timestamp_ns: u64,
    button: u32,
    x: f32,
    y: f32,
    epsilon: f32,
) -> bool {
    if !last_x.is_finite() || !last_y.is_finite() || !x.is_finite() || !y.is_finite() {
        return false;
    }
    if last_timestamp_ns != timestamp_ns || last_button != button {
        return false;
    }

    let eps = if epsilon.is_finite() {
        epsilon.max(0.000_001)
    } else {
        0.0001
    };

    (last_x - x).abs() <= eps && (last_y - y).abs() <= eps
}

fn preset_compatibility_bit(preset: VideoExportPreset) -> u32 {
    match preset {
        VideoExportPreset::HighestQuality => 1 << 0,
        VideoExportPreset::Resolution1920x1080 => 1 << 1,
        VideoExportPreset::Resolution1280x720 => 1 << 2,
        VideoExportPreset::MediumQuality => 1 << 3,
        VideoExportPreset::HevcResolution1920x1080 => 1 << 4,
        VideoExportPreset::HevcHighestQuality => 1 << 5,
    }
}

fn transform_point(transform: AffineTransform, x: f32, y: f32) -> (f32, f32) {
    (
        (transform.a * x) + (transform.c * y) + transform.tx,
        (transform.b * x) + (transform.d * y) + transform.ty,
    )
}

fn concatenate(left: AffineTransform, right: AffineTransform) -> AffineTransform {
    AffineTransform {
        a: left.a * right.a + left.b * right.c,
        b: left.a * right.b + left.b * right.d,
        c: left.c * right.a + left.d * right.c,
        d: left.c * right.b + left.d * right.d,
        tx: left.tx * right.a + left.ty * right.c + right.tx,
        ty: left.tx * right.b + left.ty * right.d + right.ty,
    }
}

fn rounded_even_dimension(value: f32) -> u32 {
    if !value.is_finite() {
        return 2;
    }
    let rounded = value.abs().round().max(2.0) as u32;
    rounded & !1
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_project() -> VideoProject {
        let mut project = VideoProject::new(VideoSourceMetadata {
            duration_ms: 5_000,
            width: 1_920,
            height: 1_080,
            frame_rate: 30,
            has_audio: true,
            has_webcam_asset: true,
            has_microphone_audio: true,
        })
        .unwrap();
        assert!(project.set_webcam_overlay(
            true,
            VIDEO_WEBCAM_SHAPE_CIRCLE,
            VIDEO_WEBCAM_ASPECT_SIXTEEN_NINE,
            7
        ));
        project.push_webcam_placement(
            0,
            VideoNormalizedRect {
                x: 0.70,
                y: 0.10,
                width: 0.20,
                height: 0.12,
            },
        );
        assert!(project.set_keystroke_overlay(
            true,
            VIDEO_KEYSTROKE_STYLE_GLASS,
            VIDEO_KEYSTROKE_SIZE_MEDIUM
        ));
        project.push_keystroke_placement(
            0,
            VideoNormalizedRect {
                x: 0.25,
                y: 0.75,
                width: 0.50,
                height: 0.12,
            },
        );
        assert!(project.add_key_event(900, "⌘K"));
        assert!(project.add_key_event(1_700, "A"));
        assert!(project.add_click_event(1_000, 1.2, -1.0, 0));
        project
    }

    #[test]
    fn video_project_normalizes_overlay_frames() {
        let rect = normalize_video_rect(VideoNormalizedRect {
            x: 2.0,
            y: -1.0,
            width: f32::NAN,
            height: 0.0,
        });
        assert_eq!(
            rect,
            VideoNormalizedRect {
                x: 0.0,
                y: 0.0,
                width: 0.2,
                height: 0.2,
            }
        );
    }

    #[test]
    fn video_project_render_plan_is_shape_aware_and_time_based() {
        let project = sample_project();
        let plan = project
            .render_plan(VideoRenderPlanQuery {
                time_ms: 1_700,
                render_width: 1_920,
                render_height: 1_080,
                target: VIDEO_RENDER_TARGET_EXPORT,
            })
            .unwrap();
        assert_eq!(plan.items.len(), 2);
        let webcam = &plan.items[0];
        assert_eq!(webcam.kind, VIDEO_RENDER_ITEM_WEBCAM);
        assert_eq!(webcam.asset_id, 7);
        assert!((webcam.width - webcam.height).abs() < 0.001);
        assert!((webcam.x - 1_344.0).abs() < 0.001);
        assert!((webcam.y - 696.0).abs() < 0.001);

        let key = &plan.items[1];
        assert_eq!(key.kind, VIDEO_RENDER_ITEM_KEYSTROKE);
        assert!((key.x - 480.0).abs() < 0.001);
        assert!((key.y - 140.4).abs() < 0.001);
        assert!((key.width - 960.0).abs() < 0.001);
        assert!((key.height - 129.6).abs() < 0.001);
        let text = std::str::from_utf8(
            &plan.text_bytes[key.text_offset as usize..(key.text_offset + key.text_len) as usize],
        )
        .unwrap();
        assert_eq!(text, "⌘K  A");
    }

    #[test]
    fn video_project_export_and_pro_requirement_are_core_owned() {
        let project = sample_project();
        let plan = project.export_plan().unwrap();
        assert!(plan.needs_custom_compositor);
        assert!(plan.include_webcam);
        assert_eq!(plan.key_event_count, 2);
        assert_eq!(plan.click_event_count, 1);

        let requirement = project
            .pro_requirement(VideoProjectExportOptions {
                target: VIDEO_EXPORT_TARGET_MP4,
                codec: 1,
                frame_rate: 1,
                quality: 1,
                bitrate: 2,
                includes_baked_transition: false,
            })
            .unwrap();
        assert_ne!(
            requirement.reasons_mask & VIDEO_PRO_REASON_WEBCAM_OVERLAY,
            0
        );
        assert_ne!(
            requirement.reasons_mask & VIDEO_PRO_REASON_KEYSTROKE_OVERLAY,
            0
        );
        assert_ne!(
            requirement.reasons_mask & VIDEO_PRO_REASON_MICROPHONE_AUDIO,
            0
        );
        assert_ne!(requirement.reasons_mask & VIDEO_PRO_REASON_HEVC_EXPORT, 0);
        assert_ne!(requirement.reasons_mask & VIDEO_PRO_REASON_SIXTY_FPS, 0);
        assert_ne!(requirement.reasons_mask & VIDEO_PRO_REASON_HIGH_QUALITY, 0);
        assert_ne!(requirement.reasons_mask & VIDEO_PRO_REASON_HIGH_BITRATE, 0);
    }

    #[test]
    fn video_project_snapshot_round_trips() {
        let project = sample_project();
        let json = project.serialize_snapshot_json().unwrap();
        let restored = VideoProject::deserialize_snapshot_json(&json).unwrap();
        assert_eq!(restored.source(), project.source());
        assert_eq!(restored.overlays(), project.overlays());
        assert!(VideoProject::deserialize_snapshot_json(b"{\"version\":999}").is_none());
    }
}
