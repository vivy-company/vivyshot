use super::*;

unsafe fn timeline_from_handle_mut<'a>(handle: *mut c_void) -> Result<&'a mut VsTimeline, i32> {
    validate_handle(&TIMELINE_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *handle.cast::<VsTimeline>() })
}

unsafe fn timeline_from_handle<'a>(handle: *const c_void) -> Result<&'a VsTimeline, i32> {
    validate_handle(&TIMELINE_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*handle.cast::<VsTimeline>() })
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_timeline_text_export_clip_info {
    pub track_index: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
}

#[derive(Clone, Copy, Default)]
pub(crate) struct TimelineTextClipExportRef {
    pub(crate) track_index: u32,
    pub(crate) clip_id: u32,
    pub(crate) start_ms: u32,
    pub(crate) end_ms: u32,
}

#[derive(Clone, Copy)]
struct ClipTransform {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    rotation: f32,
    opacity: f32,
}

impl ClipTransform {
    fn default_full() -> Self {
        ClipTransform {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
            rotation: 0.0,
            opacity: 1.0,
        }
    }

    fn to_ffi(&self) -> vs_clip_transform {
        vs_clip_transform {
            x: self.x,
            y: self.y,
            width: self.width,
            height: self.height,
            rotation: self.rotation,
            opacity: self.opacity,
        }
    }

    fn from_ffi(t: &vs_clip_transform) -> Self {
        ClipTransform {
            x: t.x,
            y: t.y,
            width: t.width,
            height: t.height,
            rotation: t.rotation,
            opacity: t.opacity,
        }
    }
}

#[derive(Clone)]
pub(crate) enum ClipData {
    Video,
    Webcam,
    Audio,
    Text {
        text: String,
        font_size: f32,
        color: u32,
        bg_color: u32,
    },
    Shape {
        fill: u32,
        border: u32,
        border_width: f32,
        corner_radius: f32,
    },
    Cursor,
    Zoom {
        scale: f32,
    },
}

#[derive(Clone)]
pub(crate) struct TimelineClip {
    pub(crate) id: u32,
    pub(crate) start_ms: u32,
    pub(crate) end_ms: u32,
    transform: ClipTransform,
    pub(crate) data: ClipData,
}

#[derive(Clone)]
pub(crate) struct TimelineTrack {
    pub(crate) kind: u8,
    pub(crate) visible: bool,
    pub(crate) clips: Vec<TimelineClip>,
}

#[derive(Clone)]
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
        old_transform: ClipTransform,
        new_transform: ClipTransform,
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
        old_font_size: f32,
        old_color: u32,
        old_bg_color: u32,
        new_font_size: f32,
        new_color: u32,
        new_bg_color: u32,
    },
    UpdateClipShapeStyle {
        track_index: usize,
        clip_id: u32,
        old_fill: u32,
        old_border: u32,
        old_border_width: f32,
        old_corner_radius: f32,
        new_fill: u32,
        new_border: u32,
        new_border_width: f32,
        new_corner_radius: f32,
    },
    SplitClip {
        track_index: usize,
        original_clip: TimelineClip,
        left_end_ms: u32,
        right_clip: TimelineClip,
    },
}

struct VsTimeline {
    video_duration_ms: u32,
    width: u32,
    height: u32,
    tracks: Vec<TimelineTrack>,
    next_clip_id: u32,
    history: Vec<TimelineAction>,
    history_cursor: usize,
}

impl VsTimeline {
    fn find_clip_mut(&mut self, track_index: usize, clip_id: u32) -> Option<&mut TimelineClip> {
        let track = self.tracks.get_mut(track_index)?;
        track.clips.iter_mut().find(|c| c.id == clip_id)
    }

    fn find_clip(&self, track_index: usize, clip_id: u32) -> Option<&TimelineClip> {
        let track = self.tracks.get(track_index)?;
        track.clips.iter().find(|c| c.id == clip_id)
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
                    track.clips.retain(|c| c.id != clip.id);
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
                    if let ClipData::Text { ref mut text, .. } = clip.data {
                        *text = new_text.clone();
                    }
                }
            }
            TimelineAction::UpdateClipTextStyle {
                track_index,
                clip_id,
                new_font_size,
                new_color,
                new_bg_color,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Text {
                        ref mut font_size,
                        ref mut color,
                        ref mut bg_color,
                        ..
                    } = clip.data
                    {
                        *font_size = *new_font_size;
                        *color = *new_color;
                        *bg_color = *new_bg_color;
                    }
                }
            }
            TimelineAction::UpdateClipShapeStyle {
                track_index,
                clip_id,
                new_fill,
                new_border,
                new_border_width,
                new_corner_radius,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Shape {
                        ref mut fill,
                        ref mut border,
                        ref mut border_width,
                        ref mut corner_radius,
                    } = clip.data
                    {
                        *fill = *new_fill;
                        *border = *new_border;
                        *border_width = *new_border_width;
                        *corner_radius = *new_corner_radius;
                    }
                }
            }
            TimelineAction::SplitClip {
                track_index,
                left_end_ms,
                right_clip,
                original_clip,
                ..
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
                    track.clips.retain(|c| c.id != clip.id);
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
                    if let ClipData::Text { ref mut text, .. } = clip.data {
                        *text = old_text.clone();
                    }
                }
            }
            TimelineAction::UpdateClipTextStyle {
                track_index,
                clip_id,
                old_font_size,
                old_color,
                old_bg_color,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Text {
                        ref mut font_size,
                        ref mut color,
                        ref mut bg_color,
                        ..
                    } = clip.data
                    {
                        *font_size = *old_font_size;
                        *color = *old_color;
                        *bg_color = *old_bg_color;
                    }
                }
            }
            TimelineAction::UpdateClipShapeStyle {
                track_index,
                clip_id,
                old_fill,
                old_border,
                old_border_width,
                old_corner_radius,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Shape {
                        ref mut fill,
                        ref mut border,
                        ref mut border_width,
                        ref mut corner_radius,
                    } = clip.data
                    {
                        *fill = *old_fill;
                        *border = *old_border;
                        *border_width = *old_border_width;
                        *corner_radius = *old_corner_radius;
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
                    track.clips.retain(|c| c.id != right_clip.id);
                }
                if let Some(clip) = self.find_clip_mut(*track_index, original_clip.id) {
                    clip.end_ms = original_clip.end_ms;
                }
            }
        }
    }
}

fn clip_data_for_kind(kind: u8) -> Option<ClipData> {
    match kind {
        0 => Some(ClipData::Video),
        1 => Some(ClipData::Webcam),
        2 => Some(ClipData::Audio),
        3 => Some(ClipData::Text {
            text: String::new(),
            font_size: 16.0,
            color: 0xFFFFFFFF,
            bg_color: 0x00000000,
        }),
        4 => Some(ClipData::Shape {
            fill: 0xFFFFFFFF,
            border: 0xFF000000,
            border_width: 2.0,
            corner_radius: 0.0,
        }),
        5 => Some(ClipData::Cursor),
        6 => Some(ClipData::Zoom { scale: 2.0 }),
        _ => None,
    }
}

fn track_kind_for_clip(data: &ClipData) -> u8 {
    match data {
        ClipData::Video => 0,
        ClipData::Webcam => 1,
        ClipData::Audio => 2,
        ClipData::Text { .. } => 3,
        ClipData::Shape { .. } => 4,
        ClipData::Cursor => 5,
        ClipData::Zoom { .. } => 6,
    }
}

fn timeline_next_clip(
    tl: &mut VsTimeline,
    start_ms: u32,
    end_ms: u32,
    data: ClipData,
) -> TimelineClip {
    let clip_id = tl.next_clip_id;
    tl.next_clip_id = tl.next_clip_id.wrapping_add(1);
    TimelineClip {
        id: clip_id,
        start_ms,
        end_ms,
        transform: ClipTransform::default_full(),
        data,
    }
}

fn timeline_full_duration_end(tl: &VsTimeline) -> u32 {
    domain_timeline_full_duration_end(tl.video_duration_ms)
}

// ---------------------------------------------------------------------------
// Timeline FFI: lifecycle
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn vs_timeline_create(duration_ms: u32, width: u32, height: u32) -> *mut c_void {
    if width == 0 || height == 0 {
        return std::ptr::null_mut();
    }

    let tl = VsTimeline {
        video_duration_ms: duration_ms,
        width,
        height,
        tracks: Vec::new(),
        next_clip_id: 1,
        history: Vec::new(),
        history_cursor: 0,
    };

    let handle = Box::into_raw(Box::new(tl)).cast();
    register_handle(&TIMELINE_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_destroy(handle: *mut c_void) {
    if !unregister_handle(&TIMELINE_HANDLES, handle) {
        return;
    }

    unsafe {
        drop(Box::from_raw(handle.cast::<VsTimeline>()));
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: tracks
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_track(handle: *mut c_void, kind: u8) -> i32 {
    if kind > 6 {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let action = TimelineAction::AddTrack { kind };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_remove_track(handle: *mut c_void, track_index: u32) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let track = tl.tracks[idx].clone();
    let action = TimelineAction::RemoveTrack {
        track_index: idx,
        track,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_reorder_track(
    handle: *mut c_void,
    from_index: u32,
    to_index: u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let from = from_index as usize;
    let to = to_index as usize;
    if from >= tl.tracks.len() || to >= tl.tracks.len() {
        return -2;
    }

    if from == to {
        return 0;
    }

    let action = TimelineAction::ReorderTrack { from, to };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_track_visible(
    handle: *mut c_void,
    track_index: u32,
    visible: bool,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let old_visible = tl.tracks[idx].visible;
    if old_visible == visible {
        return 0;
    }

    let action = TimelineAction::SetTrackVisible {
        track_index: idx,
        old_visible,
        new_visible: visible,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_tracks(
    handle: *mut c_void,
    out_ptr: *mut vs_timeline_track_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let total = tl.tracks.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for i in 0..write_count {
        let track = &tl.tracks[i];
        unsafe {
            *out_ptr.add(i) = vs_timeline_track_info {
                kind: track.kind,
                visible: track.visible,
                clip_count: track.clips.len() as u32,
            };
        }
    }

    unsafe {
        *out_written = total;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_derive_export_context(
    handle: *const c_void,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    out_context: *mut vs_video_export_context,
) -> i32 {
    if out_context.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let context =
        ffi_timeline::derive_export_context(source_has_audio, source_has_webcam_asset, &tl.tracks);

    unsafe {
        *out_context = context;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_is_webcam_track_visible_for_export(
    handle: *const c_void,
    out_visible: *mut bool,
) -> i32 {
    if out_visible.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let visible = ffi_timeline::webcam_visible_for_export(&tl.tracks);
    unsafe {
        *out_visible = visible;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_text_export_clips(
    handle: *const c_void,
    out_ptr: *mut vs_timeline_text_export_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let refs = ffi_timeline::text_export_clip_refs(&tl.tracks);
    if out_cap > 0 {
        ffi_timeline::write_text_export_clip_refs(&refs, out_ptr, out_cap);
    }
    unsafe {
        *out_written = refs.len().min(u32::MAX as usize) as u32;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_bootstrap_capture_tracks(
    handle: *mut c_void,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let full_end = timeline_full_duration_end(tl);
    let mut tracks: Vec<TimelineTrack> = Vec::new();

    let video_clip = timeline_next_clip(tl, 0, full_end, ClipData::Video);
    tracks.push(TimelineTrack {
        kind: 0,
        visible: true,
        clips: vec![video_clip],
    });

    if source_has_audio {
        let audio_clip = timeline_next_clip(tl, 0, full_end, ClipData::Audio);
        tracks.push(TimelineTrack {
            kind: 2,
            visible: true,
            clips: vec![audio_clip],
        });
    }

    if source_has_webcam_asset {
        let webcam_clip = timeline_next_clip(tl, 0, full_end, ClipData::Webcam);
        tracks.push(TimelineTrack {
            kind: 1,
            visible: true,
            clips: vec![webcam_clip],
        });
    }

    tl.tracks = tracks;
    tl.history.clear();
    tl.history_cursor = 0;
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_text_clip_auto_track(
    handle: *mut c_void,
    start_ms: u32,
    end_ms: u32,
    text_ptr: *const u8,
    text_len: u32,
    out_clip_id: *mut u32,
) -> i32 {
    if text_ptr.is_null() || text_len == 0 {
        return -1;
    }

    // SAFETY: pointer + len are validated above.
    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len as usize) };
    let raw_text = match std::str::from_utf8(text_bytes) {
        Ok(v) => v,
        Err(_) => return -2,
    };
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let (clamped_start, clamped_end) =
        domain_timeline_normalize_text_clip_range(tl.video_duration_ms, start_ms, end_ms);

    let track_index = match tl.tracks.iter().position(|track| track.kind == 3) {
        Some(idx) => idx,
        None => {
            tl.tracks.push(TimelineTrack {
                kind: 3,
                visible: true,
                clips: Vec::new(),
            });
            tl.tracks.len() - 1
        }
    };

    let clip = timeline_next_clip(
        tl,
        clamped_start,
        clamped_end,
        ClipData::Text {
            text: trimmed.to_string(),
            font_size: 16.0,
            color: 0xFFFFFFFF,
            bg_color: 0x00000000,
        },
    );
    let clip_id = clip.id;
    tl.tracks[track_index].clips.push(clip);

    if !out_clip_id.is_null() {
        unsafe {
            *out_clip_id = clip_id;
        }
    }
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: clips
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_clip(
    handle: *mut c_void,
    track_index: u32,
    start_ms: u32,
    end_ms: u32,
    kind: u8,
    out_clip_id: *mut u32,
) -> i32 {
    if end_ms <= start_ms {
        return -2;
    }

    let Some(data) = clip_data_for_kind(kind) else {
        return -2;
    };

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let clamped_end = domain_timeline_clamp_clip_end(tl.video_duration_ms, start_ms, end_ms);

    let clip_id = tl.next_clip_id;
    tl.next_clip_id = tl.next_clip_id.wrapping_add(1);

    let clip = TimelineClip {
        id: clip_id,
        start_ms,
        end_ms: clamped_end,
        transform: ClipTransform::default_full(),
        data,
    };

    let action = TimelineAction::AddClip {
        track_index: idx,
        clip,
    };
    tl.apply_action(&action);
    tl.push_action(action);

    if !out_clip_id.is_null() {
        unsafe {
            *out_clip_id = clip_id;
        }
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_remove_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c.clone(),
        None => return -2,
    };

    let action = TimelineAction::RemoveClip {
        track_index: idx,
        clip,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_move_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    new_start_ms: u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let (old_start, duration) = match tl.find_clip(idx, clip_id) {
        Some(c) => (c.start_ms, c.end_ms.saturating_sub(c.start_ms)),
        None => return -2,
    };

    let clamped_start = if tl.video_duration_ms > 0 && duration > 0 {
        new_start_ms.min(tl.video_duration_ms.saturating_sub(duration))
    } else {
        new_start_ms
    };

    if old_start == clamped_start {
        return 0;
    }

    let action = TimelineAction::MoveClip {
        track_index: idx,
        clip_id,
        old_start,
        new_start: clamped_start,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_resize_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    new_start_ms: u32,
    new_end_ms: u32,
) -> i32 {
    if new_end_ms <= new_start_ms {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clamped_end = if tl.video_duration_ms > 0 {
        new_end_ms.min(tl.video_duration_ms)
    } else {
        new_end_ms
    };
    let clamped_end = clamped_end.max(new_start_ms + 1);

    let (old_start, old_end) = match tl.find_clip(idx, clip_id) {
        Some(c) => (c.start_ms, c.end_ms),
        None => return -2,
    };

    if old_start == new_start_ms && old_end == clamped_end {
        return 0;
    }

    let action = TimelineAction::ResizeClip {
        track_index: idx,
        clip_id,
        old_start,
        old_end,
        new_start: new_start_ms,
        new_end: clamped_end,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_split_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    split_at_ms: u32,
    out_new_clip_id: *mut u32,
) -> i32 {
    if out_new_clip_id.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let original_clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c.clone(),
        None => return -2,
    };

    let split = match domain_timeline_validate_split(
        original_clip.start_ms,
        original_clip.end_ms,
        split_at_ms,
        10,
    ) {
        Some(s) => s,
        None => return -2,
    };

    let new_id = tl.next_clip_id;
    tl.next_clip_id = tl.next_clip_id.wrapping_add(1);

    let right_clip = TimelineClip {
        id: new_id,
        start_ms: split.2,
        end_ms: split.3,
        transform: original_clip.transform,
        data: original_clip.data.clone(),
    };

    let action = TimelineAction::SplitClip {
        track_index: idx,
        original_clip,
        left_end_ms: split.1,
        right_clip,
    };
    tl.apply_action(&action);
    tl.push_action(action);

    unsafe {
        *out_new_clip_id = new_id;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_update_clip_transform(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    transform: vs_clip_transform,
) -> i32 {
    if !transform.x.is_finite()
        || !transform.y.is_finite()
        || !transform.width.is_finite()
        || !transform.height.is_finite()
        || !transform.rotation.is_finite()
        || !transform.opacity.is_finite()
    {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let old_transform = match tl.find_clip(idx, clip_id) {
        Some(c) => c.transform,
        None => return -2,
    };

    let new_transform = ClipTransform::from_ffi(&transform);

    let action = TimelineAction::UpdateTransform {
        track_index: idx,
        clip_id,
        old_transform,
        new_transform,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: clip data
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_text(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    text_ptr: *const u8,
    text_len: u32,
) -> i32 {
    if text_ptr.is_null() || text_len == 0 {
        return -2;
    }

    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len as usize) };
    let new_text = match std::str::from_utf8(text_bytes) {
        Ok(v) => v.to_string(),
        Err(_) => return -2,
    };

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let old_text = match tl.find_clip(idx, clip_id) {
        Some(c) => {
            if let ClipData::Text { ref text, .. } = c.data {
                text.clone()
            } else {
                return -2;
            }
        }
        None => return -2,
    };

    let action = TimelineAction::UpdateClipText {
        track_index: idx,
        clip_id,
        old_text,
        new_text,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_text_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    font_size: f32,
    color: u32,
    bg_color: u32,
) -> i32 {
    if !font_size.is_finite() || font_size <= 0.0 {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let (old_font_size, old_color, old_bg_color) = match tl.find_clip(idx, clip_id) {
        Some(c) => {
            if let ClipData::Text {
                font_size: fs,
                color: co,
                bg_color: bg,
                ..
            } = &c.data
            {
                (*fs, *co, *bg)
            } else {
                return -2;
            }
        }
        None => return -2,
    };

    let action = TimelineAction::UpdateClipTextStyle {
        track_index: idx,
        clip_id,
        old_font_size,
        old_color,
        old_bg_color,
        new_font_size: font_size,
        new_color: color,
        new_bg_color: bg_color,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_shape_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    fill: u32,
    border: u32,
    border_width: f32,
    corner_radius: f32,
) -> i32 {
    if !border_width.is_finite() || !corner_radius.is_finite() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let (old_fill, old_border, old_border_width, old_corner_radius) =
        match tl.find_clip(idx, clip_id) {
            Some(c) => {
                if let ClipData::Shape {
                    fill: f,
                    border: b,
                    border_width: bw,
                    corner_radius: cr,
                } = &c.data
                {
                    (*f, *b, *bw, *cr)
                } else {
                    return -2;
                }
            }
            None => return -2,
        };

    let action = TimelineAction::UpdateClipShapeStyle {
        track_index: idx,
        clip_id,
        old_fill,
        old_border,
        old_border_width,
        old_corner_radius,
        new_fill: fill,
        new_border: border,
        new_border_width: border_width,
        new_corner_radius: corner_radius,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: queries
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clips(
    handle: *mut c_void,
    track_index: u32,
    out_ptr: *mut vs_timeline_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let track = &tl.tracks[idx];
    let total = track.clips.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for i in 0..write_count {
        let clip = &track.clips[i];
        unsafe {
            *out_ptr.add(i) = vs_timeline_clip_info {
                id: clip.id,
                track_index,
                start_ms: clip.start_ms,
                end_ms: clip.end_ms,
                kind: track_kind_for_clip(&clip.data),
                transform: clip.transform.to_ffi(),
            };
        }
    }

    unsafe {
        *out_written = total;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_visible_clips_at(
    handle: *mut c_void,
    time_ms: u32,
    out_ptr: *mut vs_timeline_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let mut written: u32 = 0;

    for (track_idx, track) in tl.tracks.iter().enumerate() {
        if !track.visible {
            continue;
        }

        for clip in &track.clips {
            if time_ms >= clip.start_ms && time_ms < clip.end_ms {
                if written < out_cap {
                    unsafe {
                        *out_ptr.add(written as usize) = vs_timeline_clip_info {
                            id: clip.id,
                            track_index: track_idx as u32,
                            start_ms: clip.start_ms,
                            end_ms: clip.end_ms,
                            kind: track.kind,
                            transform: clip.transform.to_ffi(),
                        };
                    }
                }
                written += 1;
            }
        }
    }

    unsafe {
        *out_written = written;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_text(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };

    let text = match &clip.data {
        ClipData::Text { text, .. } => text,
        _ => return -2,
    };

    let bytes = text.as_bytes();
    let copy_len = bytes.len().min(out_cap as usize);

    if copy_len > 0 {
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, copy_len);
        }
    }

    unsafe {
        *out_written = bytes.len() as u32;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_shape_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_fill: *mut u32,
    out_border: *mut u32,
    out_border_width: *mut f32,
    out_corner_radius: *mut f32,
) -> i32 {
    if out_fill.is_null()
        || out_border.is_null()
        || out_border_width.is_null()
        || out_corner_radius.is_null()
    {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };

    match &clip.data {
        ClipData::Shape {
            fill,
            border,
            border_width,
            corner_radius,
        } => {
            unsafe {
                *out_fill = *fill;
                *out_border = *border;
                *out_border_width = *border_width;
                *out_corner_radius = *corner_radius;
            }
            0
        }
        _ => -2,
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: undo/redo
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_undo(handle: *mut c_void) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if tl.history_cursor == 0 {
        return 1;
    }

    tl.history_cursor -= 1;
    let action = tl.history[tl.history_cursor].clone();
    tl.reverse_action(&action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_redo(handle: *mut c_void) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if tl.history_cursor >= tl.history.len() {
        return 1;
    }

    let action = tl.history[tl.history_cursor].clone();
    tl.apply_action(&action);
    tl.history_cursor += 1;
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: info and zoom scale
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_video_info(
    handle: *mut c_void,
    out_duration_ms: *mut u32,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    if !out_duration_ms.is_null() {
        unsafe {
            *out_duration_ms = tl.video_duration_ms;
        }
    }
    if !out_width.is_null() {
        unsafe {
            *out_width = tl.width;
        }
    }
    if !out_height.is_null() {
        unsafe {
            *out_height = tl.height;
        }
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_zoom_scale(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    scale: f32,
) -> i32 {
    if !scale.is_finite() || scale <= 0.0 {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };

    let old_scale = match &clip.data {
        ClipData::Zoom { scale } => *scale,
        _ => return -2,
    };

    if (old_scale - scale).abs() < f32::EPSILON {
        return 0;
    }

    let clip = match tl.find_clip_mut(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };
    if let ClipData::Zoom {
        scale: ref mut value,
    } = clip.data
    {
        *value = scale;
    } else {
        return -2;
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_zoom_scale(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_scale: *mut f32,
) -> i32 {
    if out_scale.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };
    let scale = match &clip.data {
        ClipData::Zoom { scale } => *scale,
        _ => return -2,
    };
    unsafe {
        *out_scale = scale;
    }
    0
}
