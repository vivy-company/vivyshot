use crate::types::{
    TimelineClip, TimelineClipData, TimelineClipTransform, TimelineShapeStyle,
    TimelineTextClipExportInput, TimelineTextClipExportRef, TimelineTextStyle, TimelineTrack,
    TimelineTrackSummary,
};
use crate::VideoExportContext;

pub const TIMELINE_TRACK_VIDEO: u8 = 0;
pub const TIMELINE_TRACK_WEBCAM: u8 = 1;
pub const TIMELINE_TRACK_AUDIO: u8 = 2;
pub const TIMELINE_TRACK_TEXT: u8 = 3;
pub const TIMELINE_TRACK_SHAPE: u8 = 4;
pub const TIMELINE_TRACK_CURSOR: u8 = 5;
pub const TIMELINE_TRACK_ZOOM: u8 = 6;

const TIMELINE_MIN_SPLIT_CLIP_MS: u32 = 10;

impl TimelineClipTransform {
    pub fn default_full() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
            rotation: 0.0,
            opacity: 1.0,
        }
    }

    pub fn is_valid(self) -> bool {
        self.x.is_finite()
            && self.y.is_finite()
            && self.width.is_finite()
            && self.height.is_finite()
            && self.rotation.is_finite()
            && self.opacity.is_finite()
    }
}

impl TimelineClipData {
    pub fn for_kind(kind: u8) -> Option<Self> {
        Self::from_kind(kind)
    }

    pub fn text(&self) -> Option<&str> {
        match self {
            Self::Text { text, .. } => Some(text.as_str()),
            _ => None,
        }
    }

    pub fn text_style(&self) -> Option<TimelineTextStyle> {
        match self {
            Self::Text { style, .. } => Some(*style),
            _ => None,
        }
    }

    pub fn shape_style(&self) -> Option<TimelineShapeStyle> {
        match self {
            Self::Shape { style } => Some(*style),
            _ => None,
        }
    }

    pub fn zoom_scale(&self) -> Option<f32> {
        match self {
            Self::Zoom { scale } => Some(*scale),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
enum TimelineAction {
    AddClip {
        track_index: usize,
        clip: TimelineClip,
    },
    RemoveClip {
        track_index: usize,
        clip: TimelineClip,
    },
    MoveClip {
        track_index: usize,
        clip_id: u32,
        old_start: u32,
        new_start: u32,
    },
    ResizeClip {
        track_index: usize,
        clip_id: u32,
        old_start: u32,
        old_end: u32,
        new_start: u32,
        new_end: u32,
    },
    UpdateTransform {
        track_index: usize,
        clip_id: u32,
        old_transform: TimelineClipTransform,
        new_transform: TimelineClipTransform,
    },
    SetTrackVisible {
        track_index: usize,
        old_visible: bool,
        new_visible: bool,
    },
    AddTrack {
        kind: u8,
    },
    RemoveTrack {
        track_index: usize,
        track: TimelineTrack,
    },
    ReorderTrack {
        from: usize,
        to: usize,
    },
    UpdateClipText {
        track_index: usize,
        clip_id: u32,
        old_text: String,
        new_text: String,
    },
    UpdateClipTextStyle {
        track_index: usize,
        clip_id: u32,
        old_style: TimelineTextStyle,
        new_style: TimelineTextStyle,
    },
    UpdateClipShapeStyle {
        track_index: usize,
        clip_id: u32,
        old_style: TimelineShapeStyle,
        new_style: TimelineShapeStyle,
    },
    SplitClip {
        track_index: usize,
        original_clip: TimelineClip,
        left_end_ms: u32,
        right_clip: TimelineClip,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TimelineError {
    InvalidArgument,
    NotFound,
    NoChange,
}

pub struct Timeline {
    video_duration_ms: u32,
    width: u32,
    height: u32,
    tracks: Vec<TimelineTrack>,
    next_clip_id: u32,
    history: Vec<TimelineAction>,
    history_cursor: usize,
}

impl Timeline {
    pub fn new(video_duration_ms: u32, width: u32, height: u32) -> Option<Self> {
        if width == 0 || height == 0 {
            return None;
        }

        Some(Self {
            video_duration_ms,
            width,
            height,
            tracks: Vec::new(),
            next_clip_id: 1,
            history: Vec::new(),
            history_cursor: 0,
        })
    }

    pub fn video_duration_ms(&self) -> u32 {
        self.video_duration_ms
    }

    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn height(&self) -> u32 {
        self.height
    }

    pub fn tracks(&self) -> &[TimelineTrack] {
        &self.tracks
    }

    pub fn add_track(&mut self, kind: u8) -> Result<(), TimelineError> {
        if TimelineClipData::for_kind(kind).is_none() {
            return Err(TimelineError::InvalidArgument);
        }

        let action = TimelineAction::AddTrack { kind };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn remove_track(&mut self, track_index: usize) -> Result<(), TimelineError> {
        let Some(track) = self.tracks.get(track_index).cloned() else {
            return Err(TimelineError::InvalidArgument);
        };

        let action = TimelineAction::RemoveTrack { track_index, track };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn reorder_track(&mut self, from: usize, to: usize) -> Result<(), TimelineError> {
        if from >= self.tracks.len() || to >= self.tracks.len() {
            return Err(TimelineError::InvalidArgument);
        }

        if from == to {
            return Ok(());
        }

        let action = TimelineAction::ReorderTrack { from, to };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn set_track_visible(
        &mut self,
        track_index: usize,
        visible: bool,
    ) -> Result<(), TimelineError> {
        let Some(track) = self.tracks.get(track_index) else {
            return Err(TimelineError::InvalidArgument);
        };

        if track.visible == visible {
            return Ok(());
        }

        let action = TimelineAction::SetTrackVisible {
            track_index,
            old_visible: track.visible,
            new_visible: visible,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn bootstrap_capture_tracks(
        &mut self,
        source_has_audio: bool,
        source_has_webcam_asset: bool,
    ) {
        let full_end = timeline_full_duration_end(self.video_duration_ms);
        let mut tracks = Vec::new();

        tracks.push(TimelineTrack {
            kind: TIMELINE_TRACK_VIDEO,
            visible: true,
            clips: vec![self.next_clip(0, full_end, TimelineClipData::Video)],
        });

        if source_has_audio {
            tracks.push(TimelineTrack {
                kind: TIMELINE_TRACK_AUDIO,
                visible: true,
                clips: vec![self.next_clip(0, full_end, TimelineClipData::Audio)],
            });
        }

        if source_has_webcam_asset {
            tracks.push(TimelineTrack {
                kind: TIMELINE_TRACK_WEBCAM,
                visible: true,
                clips: vec![self.next_clip(0, full_end, TimelineClipData::Webcam)],
            });
        }

        self.tracks = tracks;
        self.history.clear();
        self.history_cursor = 0;
    }

    pub fn add_text_clip_auto_track(
        &mut self,
        start_ms: u32,
        end_ms: u32,
        raw_text: &str,
    ) -> Result<u32, TimelineError> {
        let trimmed = raw_text.trim();
        if trimmed.is_empty() {
            return Err(TimelineError::InvalidArgument);
        }

        let (clamped_start, clamped_end) =
            timeline_normalize_text_clip_range(self.video_duration_ms, start_ms, end_ms);

        let track_index = match self
            .tracks
            .iter()
            .position(|track| track.kind == TIMELINE_TRACK_TEXT)
        {
            Some(index) => index,
            None => {
                self.tracks.push(TimelineTrack {
                    kind: TIMELINE_TRACK_TEXT,
                    visible: true,
                    clips: Vec::new(),
                });
                self.tracks.len() - 1
            }
        };

        let clip = self.next_clip(
            clamped_start,
            clamped_end,
            TimelineClipData::Text {
                text: trimmed.to_string(),
                style: TimelineTextStyle::default(),
            },
        );
        let clip_id = clip.id;
        self.tracks[track_index].clips.push(clip);
        Ok(clip_id)
    }

    pub fn add_clip(
        &mut self,
        track_index: usize,
        start_ms: u32,
        end_ms: u32,
        kind: u8,
    ) -> Result<u32, TimelineError> {
        if end_ms <= start_ms {
            return Err(TimelineError::InvalidArgument);
        }

        let Some(data) = TimelineClipData::for_kind(kind) else {
            return Err(TimelineError::InvalidArgument);
        };

        if track_index >= self.tracks.len() {
            return Err(TimelineError::InvalidArgument);
        }

        let clip = TimelineClip {
            id: self.next_clip_id,
            start_ms,
            end_ms: timeline_clamp_clip_end(self.video_duration_ms, start_ms, end_ms),
            transform: TimelineClipTransform::default_full(),
            data,
        };
        self.next_clip_id = self.next_clip_id.wrapping_add(1);
        let clip_id = clip.id;

        let action = TimelineAction::AddClip { track_index, clip };
        self.apply_action(&action);
        self.push_action(action);
        Ok(clip_id)
    }

    pub fn remove_clip(&mut self, track_index: usize, clip_id: u32) -> Result<(), TimelineError> {
        let clip = self
            .find_clip(track_index, clip_id)
            .cloned()
            .ok_or(TimelineError::InvalidArgument)?;

        let action = TimelineAction::RemoveClip { track_index, clip };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn move_clip(
        &mut self,
        track_index: usize,
        clip_id: u32,
        new_start_ms: u32,
    ) -> Result<(), TimelineError> {
        let Some(clip) = self.find_clip(track_index, clip_id) else {
            return Err(TimelineError::InvalidArgument);
        };

        let old_start = clip.start_ms;
        let duration = clip.end_ms.saturating_sub(clip.start_ms);
        let clamped_start = if self.video_duration_ms > 0 && duration > 0 {
            new_start_ms.min(self.video_duration_ms.saturating_sub(duration))
        } else {
            new_start_ms
        };

        if old_start == clamped_start {
            return Ok(());
        }

        let action = TimelineAction::MoveClip {
            track_index,
            clip_id,
            old_start,
            new_start: clamped_start,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn resize_clip(
        &mut self,
        track_index: usize,
        clip_id: u32,
        new_start_ms: u32,
        new_end_ms: u32,
    ) -> Result<(), TimelineError> {
        if new_end_ms <= new_start_ms {
            return Err(TimelineError::InvalidArgument);
        }

        let Some(clip) = self.find_clip(track_index, clip_id) else {
            return Err(TimelineError::InvalidArgument);
        };

        let mut clamped_end = if self.video_duration_ms > 0 {
            new_end_ms.min(self.video_duration_ms)
        } else {
            new_end_ms
        };
        clamped_end = clamped_end.max(new_start_ms.saturating_add(1));

        if clip.start_ms == new_start_ms && clip.end_ms == clamped_end {
            return Ok(());
        }

        let action = TimelineAction::ResizeClip {
            track_index,
            clip_id,
            old_start: clip.start_ms,
            old_end: clip.end_ms,
            new_start: new_start_ms,
            new_end: clamped_end,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn split_clip(
        &mut self,
        track_index: usize,
        clip_id: u32,
        split_at_ms: u32,
    ) -> Result<u32, TimelineError> {
        let original_clip = self
            .find_clip(track_index, clip_id)
            .cloned()
            .ok_or(TimelineError::InvalidArgument)?;

        let Some(split) = timeline_validate_split(
            original_clip.start_ms,
            original_clip.end_ms,
            split_at_ms,
            TIMELINE_MIN_SPLIT_CLIP_MS,
        ) else {
            return Err(TimelineError::InvalidArgument);
        };

        let right_clip = TimelineClip {
            id: self.next_clip_id,
            start_ms: split.2,
            end_ms: split.3,
            transform: original_clip.transform,
            data: original_clip.data.clone(),
        };
        self.next_clip_id = self.next_clip_id.wrapping_add(1);
        let new_clip_id = right_clip.id;

        let action = TimelineAction::SplitClip {
            track_index,
            original_clip,
            left_end_ms: split.1,
            right_clip,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(new_clip_id)
    }

    pub fn update_clip_transform(
        &mut self,
        track_index: usize,
        clip_id: u32,
        transform: TimelineClipTransform,
    ) -> Result<(), TimelineError> {
        if !transform.is_valid() {
            return Err(TimelineError::InvalidArgument);
        }

        let Some(old_transform) = self
            .find_clip(track_index, clip_id)
            .map(|clip| clip.transform)
        else {
            return Err(TimelineError::InvalidArgument);
        };

        let action = TimelineAction::UpdateTransform {
            track_index,
            clip_id,
            old_transform,
            new_transform: transform,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn set_clip_text(
        &mut self,
        track_index: usize,
        clip_id: u32,
        new_text: String,
    ) -> Result<(), TimelineError> {
        let old_text = match self.find_clip(track_index, clip_id) {
            Some(clip) => clip
                .data
                .text()
                .map(str::to_owned)
                .ok_or(TimelineError::InvalidArgument)?,
            None => return Err(TimelineError::InvalidArgument),
        };

        let action = TimelineAction::UpdateClipText {
            track_index,
            clip_id,
            old_text,
            new_text,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn set_clip_text_style(
        &mut self,
        track_index: usize,
        clip_id: u32,
        new_style: TimelineTextStyle,
    ) -> Result<(), TimelineError> {
        if !new_style.font_size.is_finite() || new_style.font_size <= 0.0 {
            return Err(TimelineError::InvalidArgument);
        }

        let old_style = match self.find_clip(track_index, clip_id) {
            Some(clip) => clip
                .data
                .text_style()
                .ok_or(TimelineError::InvalidArgument)?,
            None => return Err(TimelineError::InvalidArgument),
        };

        let action = TimelineAction::UpdateClipTextStyle {
            track_index,
            clip_id,
            old_style,
            new_style,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn set_clip_shape_style(
        &mut self,
        track_index: usize,
        clip_id: u32,
        new_style: TimelineShapeStyle,
    ) -> Result<(), TimelineError> {
        if !new_style.border_width.is_finite() || !new_style.corner_radius.is_finite() {
            return Err(TimelineError::InvalidArgument);
        }

        let old_style = match self.find_clip(track_index, clip_id) {
            Some(clip) => clip
                .data
                .shape_style()
                .ok_or(TimelineError::InvalidArgument)?,
            None => return Err(TimelineError::InvalidArgument),
        };

        let action = TimelineAction::UpdateClipShapeStyle {
            track_index,
            clip_id,
            old_style,
            new_style,
        };
        self.apply_action(&action);
        self.push_action(action);
        Ok(())
    }

    pub fn clip_text(&self, track_index: usize, clip_id: u32) -> Result<&str, TimelineError> {
        let Some(clip) = self.find_clip(track_index, clip_id) else {
            return Err(TimelineError::InvalidArgument);
        };

        clip.data.text().ok_or(TimelineError::InvalidArgument)
    }

    pub fn clip_shape_style(
        &self,
        track_index: usize,
        clip_id: u32,
    ) -> Result<TimelineShapeStyle, TimelineError> {
        let Some(clip) = self.find_clip(track_index, clip_id) else {
            return Err(TimelineError::InvalidArgument);
        };

        clip.data
            .shape_style()
            .ok_or(TimelineError::InvalidArgument)
    }

    pub fn set_clip_zoom_scale(
        &mut self,
        track_index: usize,
        clip_id: u32,
        scale: f32,
    ) -> Result<(), TimelineError> {
        if !scale.is_finite() || scale <= 0.0 {
            return Err(TimelineError::InvalidArgument);
        }

        let Some(old_scale) = self
            .find_clip(track_index, clip_id)
            .and_then(|clip| clip.data.zoom_scale())
        else {
            return Err(TimelineError::InvalidArgument);
        };

        if (old_scale - scale).abs() < f32::EPSILON {
            return Ok(());
        }

        let Some(clip) = self.find_clip_mut(track_index, clip_id) else {
            return Err(TimelineError::InvalidArgument);
        };
        let TimelineClipData::Zoom { scale: value } = &mut clip.data else {
            return Err(TimelineError::InvalidArgument);
        };
        *value = scale;
        Ok(())
    }

    pub fn clip_zoom_scale(&self, track_index: usize, clip_id: u32) -> Result<f32, TimelineError> {
        let Some(clip) = self.find_clip(track_index, clip_id) else {
            return Err(TimelineError::InvalidArgument);
        };

        clip.data.zoom_scale().ok_or(TimelineError::InvalidArgument)
    }

    pub fn clips(&self, track_index: usize) -> Result<&[TimelineClip], TimelineError> {
        self.tracks
            .get(track_index)
            .map(|track| track.clips.as_slice())
            .ok_or(TimelineError::InvalidArgument)
    }

    pub fn undo(&mut self) -> Result<(), TimelineError> {
        if self.history_cursor == 0 {
            return Err(TimelineError::NoChange);
        }

        self.history_cursor -= 1;
        let action = self.history[self.history_cursor].clone();
        self.reverse_action(&action);
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), TimelineError> {
        if self.history_cursor >= self.history.len() {
            return Err(TimelineError::NoChange);
        }

        let action = self.history[self.history_cursor].clone();
        self.apply_action(&action);
        self.history_cursor += 1;
        Ok(())
    }

    pub fn export_context(
        &self,
        source_has_audio: bool,
        source_has_webcam_asset: bool,
    ) -> VideoExportContext {
        crate::video::derive_video_export_context(
            source_has_audio,
            source_has_webcam_asset,
            &self.track_summaries(),
        )
    }

    pub fn webcam_visible_for_export(&self) -> bool {
        timeline_webcam_visible_for_export(&self.track_summaries())
    }

    pub fn text_export_clips(&self) -> Vec<TimelineTextClipExportRef> {
        timeline_collect_text_export_clips(&self.text_export_inputs())
    }

    fn track_summaries(&self) -> Vec<TimelineTrackSummary> {
        self.tracks
            .iter()
            .map(|track| TimelineTrackSummary {
                kind: track.kind,
                visible: track.visible,
                clip_count: track.clips.len().min(u32::MAX as usize) as u32,
            })
            .collect()
    }

    fn text_export_inputs(&self) -> Vec<TimelineTextClipExportInput> {
        self.tracks
            .iter()
            .enumerate()
            .flat_map(|(track_order, track)| {
                track.clips.iter().filter_map(move |clip| {
                    if track.kind != TIMELINE_TRACK_TEXT {
                        return None;
                    }
                    if !matches!(clip.data, TimelineClipData::Text { .. }) {
                        return None;
                    }
                    Some(TimelineTextClipExportInput {
                        track_index: track_order.min(u32::MAX as usize) as u32,
                        track_order: track_order.min(u32::MAX as usize) as u32,
                        clip_id: clip.id,
                        start_ms: clip.start_ms,
                        end_ms: clip.end_ms,
                        track_visible: track.visible,
                    })
                })
            })
            .collect()
    }

    fn find_clip_mut(&mut self, track_index: usize, clip_id: u32) -> Option<&mut TimelineClip> {
        self.tracks
            .get_mut(track_index)?
            .clips
            .iter_mut()
            .find(|clip| clip.id == clip_id)
    }

    fn find_clip(&self, track_index: usize, clip_id: u32) -> Option<&TimelineClip> {
        self.tracks
            .get(track_index)?
            .clips
            .iter()
            .find(|clip| clip.id == clip_id)
    }

    fn push_action(&mut self, action: TimelineAction) {
        self.history.truncate(self.history_cursor);
        self.history.push(action);
        self.history_cursor = self.history.len();
    }

    fn apply_action(&mut self, action: &TimelineAction) {
        match action {
            TimelineAction::AddClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.push(clip.clone());
                }
            }
            TimelineAction::RemoveClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.retain(|candidate| candidate.id != clip.id);
                }
            }
            TimelineAction::MoveClip {
                track_index,
                clip_id,
                new_start,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    let duration = clip.end_ms.saturating_sub(clip.start_ms);
                    clip.start_ms = *new_start;
                    clip.end_ms = new_start.saturating_add(duration);
                }
            }
            TimelineAction::ResizeClip {
                track_index,
                clip_id,
                new_start,
                new_end,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.start_ms = *new_start;
                    clip.end_ms = *new_end;
                }
            }
            TimelineAction::UpdateTransform {
                track_index,
                clip_id,
                new_transform,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.transform = *new_transform;
                }
            }
            TimelineAction::SetTrackVisible {
                track_index,
                new_visible,
                ..
            } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.visible = *new_visible;
                }
            }
            TimelineAction::AddTrack { kind } => {
                self.tracks.push(TimelineTrack {
                    kind: *kind,
                    visible: true,
                    clips: Vec::new(),
                });
            }
            TimelineAction::RemoveTrack { track_index, .. } => {
                if *track_index < self.tracks.len() {
                    self.tracks.remove(*track_index);
                }
            }
            TimelineAction::ReorderTrack { from, to } => {
                if *from < self.tracks.len() && *to < self.tracks.len() {
                    let track = self.tracks.remove(*from);
                    self.tracks.insert(*to, track);
                }
            }
            TimelineAction::UpdateClipText {
                track_index,
                clip_id,
                new_text,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let TimelineClipData::Text { text, .. } = &mut clip.data {
                        *text = new_text.clone();
                    }
                }
            }
            TimelineAction::UpdateClipTextStyle {
                track_index,
                clip_id,
                new_style,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let TimelineClipData::Text { style, .. } = &mut clip.data {
                        *style = *new_style;
                    }
                }
            }
            TimelineAction::UpdateClipShapeStyle {
                track_index,
                clip_id,
                new_style,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let TimelineClipData::Shape { style } = &mut clip.data {
                        *style = *new_style;
                    }
                }
            }
            TimelineAction::SplitClip {
                track_index,
                original_clip,
                left_end_ms,
                right_clip,
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, original_clip.id) {
                    clip.end_ms = *left_end_ms;
                }
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.push(right_clip.clone());
                }
            }
        }
    }

    fn reverse_action(&mut self, action: &TimelineAction) {
        match action {
            TimelineAction::AddClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.retain(|candidate| candidate.id != clip.id);
                }
            }
            TimelineAction::RemoveClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.push(clip.clone());
                }
            }
            TimelineAction::MoveClip {
                track_index,
                clip_id,
                old_start,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    let duration = clip.end_ms.saturating_sub(clip.start_ms);
                    clip.start_ms = *old_start;
                    clip.end_ms = old_start.saturating_add(duration);
                }
            }
            TimelineAction::ResizeClip {
                track_index,
                clip_id,
                old_start,
                old_end,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.start_ms = *old_start;
                    clip.end_ms = *old_end;
                }
            }
            TimelineAction::UpdateTransform {
                track_index,
                clip_id,
                old_transform,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.transform = *old_transform;
                }
            }
            TimelineAction::SetTrackVisible {
                track_index,
                old_visible,
                ..
            } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.visible = *old_visible;
                }
            }
            TimelineAction::AddTrack { .. } => {
                if !self.tracks.is_empty() {
                    self.tracks.pop();
                }
            }
            TimelineAction::RemoveTrack { track_index, track } => {
                if *track_index <= self.tracks.len() {
                    self.tracks.insert(*track_index, track.clone());
                }
            }
            TimelineAction::ReorderTrack { from, to } => {
                if *to < self.tracks.len() && *from <= self.tracks.len() {
                    let track = self.tracks.remove(*to);
                    self.tracks.insert(*from, track);
                }
            }
            TimelineAction::UpdateClipText {
                track_index,
                clip_id,
                old_text,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let TimelineClipData::Text { text, .. } = &mut clip.data {
                        *text = old_text.clone();
                    }
                }
            }
            TimelineAction::UpdateClipTextStyle {
                track_index,
                clip_id,
                old_style,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let TimelineClipData::Text { style, .. } = &mut clip.data {
                        *style = *old_style;
                    }
                }
            }
            TimelineAction::UpdateClipShapeStyle {
                track_index,
                clip_id,
                old_style,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let TimelineClipData::Shape { style } = &mut clip.data {
                        *style = *old_style;
                    }
                }
            }
            TimelineAction::SplitClip {
                track_index,
                original_clip,
                right_clip,
                ..
            } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.retain(|clip| clip.id != right_clip.id);
                }
                if let Some(clip) = self.find_clip_mut(*track_index, original_clip.id) {
                    clip.end_ms = original_clip.end_ms;
                }
            }
        }
    }

    fn next_clip(&mut self, start_ms: u32, end_ms: u32, data: TimelineClipData) -> TimelineClip {
        let clip = TimelineClip {
            id: self.next_clip_id,
            start_ms,
            end_ms,
            transform: TimelineClipTransform::default_full(),
            data,
        };
        self.next_clip_id = self.next_clip_id.wrapping_add(1);
        clip
    }
}

pub fn timeline_webcam_visible_for_export(tracks: &[TimelineTrackSummary]) -> bool {
    tracks
        .iter()
        .any(|track| track.kind == TIMELINE_TRACK_WEBCAM && track.visible && track.clip_count > 0)
}

pub fn timeline_collect_text_export_clips(
    clips: &[TimelineTextClipExportInput],
) -> Vec<TimelineTextClipExportRef> {
    let mut visible = clips
        .iter()
        .copied()
        .filter(|clip| clip.track_visible && clip.end_ms > clip.start_ms)
        .collect::<Vec<_>>();
    visible.sort_by_key(|clip| (clip.track_order, clip.start_ms, clip.clip_id));

    visible
        .into_iter()
        .map(|clip| TimelineTextClipExportRef {
            track_index: clip.track_index,
            clip_id: clip.clip_id,
            start_ms: clip.start_ms,
            end_ms: clip.end_ms,
        })
        .collect()
}

pub fn timeline_full_duration_end(video_duration_ms: u32) -> u32 {
    if video_duration_ms == 0 {
        1
    } else {
        video_duration_ms.max(1)
    }
}

pub fn timeline_clamp_clip_end(video_duration_ms: u32, start_ms: u32, end_ms: u32) -> u32 {
    let clamped_end = if video_duration_ms > 0 {
        end_ms.min(video_duration_ms)
    } else {
        end_ms
    };
    clamped_end.max(start_ms.saturating_add(1))
}

pub fn timeline_normalize_text_clip_range(
    video_duration_ms: u32,
    start_ms: u32,
    end_ms: u32,
) -> (u32, u32) {
    let duration = timeline_full_duration_end(video_duration_ms);
    let mut clamped_start = start_ms.min(duration.saturating_sub(1));
    let mut clamped_end = end_ms.min(duration);
    if clamped_end <= clamped_start {
        clamped_end = clamped_start.saturating_add(1).min(duration);
    }
    if clamped_end <= clamped_start {
        clamped_start = clamped_end.saturating_sub(1);
    }
    (clamped_start, clamped_end)
}

pub fn timeline_validate_split(
    clip_start_ms: u32,
    clip_end_ms: u32,
    split_at_ms: u32,
    min_clip_ms: u32,
) -> Option<(u32, u32, u32, u32)> {
    if split_at_ms <= clip_start_ms.saturating_add(min_clip_ms) {
        return None;
    }
    if split_at_ms >= clip_end_ms.saturating_sub(min_clip_ms) {
        return None;
    }
    Some((clip_start_ms, split_at_ms, split_at_ms, clip_end_ms))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timeline_bootstrap_and_text_import_live_in_core() {
        let mut timeline = Timeline::new(8_000, 1280, 720).unwrap();
        timeline.bootstrap_capture_tracks(true, true);

        assert_eq!(timeline.tracks.len(), 3);
        assert_eq!(timeline.tracks[0].kind, TIMELINE_TRACK_VIDEO);
        assert_eq!(timeline.tracks[1].kind, TIMELINE_TRACK_AUDIO);
        assert_eq!(timeline.tracks[2].kind, TIMELINE_TRACK_WEBCAM);

        let clip_id = timeline
            .add_text_clip_auto_track(500, 2_500, "  Portable text clip  ")
            .unwrap();
        assert!(clip_id > 0);

        let refs = timeline.text_export_clips();
        assert_eq!(refs.len(), 1);
        assert_eq!(refs[0].clip_id, clip_id);

        let context = timeline.export_context(true, true);
        assert!(context.audio_track_visible);
        assert!(context.webcam_track_visible);
        assert_eq!(context.text_overlay_count, 1);
    }

    #[test]
    fn timeline_clip_ops_and_history_live_in_core() {
        let mut timeline = Timeline::new(12_000, 1920, 1080).unwrap();
        timeline.add_track(TIMELINE_TRACK_VIDEO).unwrap();
        timeline.add_track(TIMELINE_TRACK_TEXT).unwrap();
        timeline.add_track(TIMELINE_TRACK_ZOOM).unwrap();

        let video_clip = timeline
            .add_clip(0, 0, 10_000, TIMELINE_TRACK_VIDEO)
            .unwrap();
        let text_clip = timeline
            .add_clip(1, 2_000, 6_000, TIMELINE_TRACK_TEXT)
            .unwrap();
        let zoom_clip = timeline
            .add_clip(2, 1_000, 9_000, TIMELINE_TRACK_ZOOM)
            .unwrap();

        assert!(video_clip > 0);
        timeline
            .set_clip_text(1, text_clip, "Timeline text".to_string())
            .unwrap();
        timeline
            .set_clip_text_style(
                1,
                text_clip,
                TimelineTextStyle {
                    font_size: 20.0,
                    color: 0xFFAA_33FF,
                    bg_color: 0x0000_0000,
                },
            )
            .unwrap();
        timeline.move_clip(1, text_clip, 3_000).unwrap();
        timeline.resize_clip(1, text_clip, 3_000, 7_000).unwrap();
        timeline.set_clip_zoom_scale(2, zoom_clip, 1.25).unwrap();
        assert!((timeline.clip_zoom_scale(2, zoom_clip).unwrap() - 1.25).abs() < 0.001);

        timeline.remove_clip(1, text_clip).unwrap();
        timeline.undo().unwrap();
        timeline.redo().unwrap();
    }
}
