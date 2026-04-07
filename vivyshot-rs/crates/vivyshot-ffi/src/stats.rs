use super::*;

#[repr(C)]
struct vs_stats_session {
    state: DomainCaptureStatisticsState,
}

#[derive(Serialize, Deserialize)]
struct VsStatsSessionSnapshot {
    version: u32,
    state: VsStatsStateSnapshot,
}

#[derive(Serialize, Deserialize)]
struct VsStatsStateSnapshot {
    total_screenshots_captured: i64,
    total_recordings_completed: i64,
    total_recorded_duration_ms: i64,
    total_screenshot_completion_duration_ms: i64,
    completed_screenshot_session_count: i64,
    total_capture_bytes_produced: i64,
    current_capture_streak_days: i32,
    best_capture_streak_days: i32,
    first_capture_day_key: Option<DomainStatsDayKey>,
    last_capture_day_key: Option<DomainStatsDayKey>,
    daily_capture: Vec<DailyCaptureStats>,
    ingested_event_keys: Vec<String>,
}

impl From<&DomainCaptureStatisticsState> for VsStatsStateSnapshot {
    fn from(state: &DomainCaptureStatisticsState) -> Self {
        let mut ingested_event_keys = state.ingested_event_keys.iter().cloned().collect::<Vec<_>>();
        ingested_event_keys.sort();

        Self {
            total_screenshots_captured: state.total_screenshots_captured,
            total_recordings_completed: state.total_recordings_completed,
            total_recorded_duration_ms: state.total_recorded_duration_ms,
            total_screenshot_completion_duration_ms: state.total_screenshot_completion_duration_ms,
            completed_screenshot_session_count: state.completed_screenshot_session_count,
            total_capture_bytes_produced: state.total_capture_bytes_produced,
            current_capture_streak_days: state.current_capture_streak_days,
            best_capture_streak_days: state.best_capture_streak_days,
            first_capture_day_key: state.first_capture_day_key,
            last_capture_day_key: state.last_capture_day_key,
            daily_capture: state.daily_capture.values().cloned().collect(),
            ingested_event_keys,
        }
    }
}

impl From<VsStatsStateSnapshot> for DomainCaptureStatisticsState {
    fn from(snapshot: VsStatsStateSnapshot) -> Self {
        let daily_capture = snapshot
            .daily_capture
            .into_iter()
            .map(|bucket| (bucket.day_key, bucket))
            .collect();
        let ingested_event_keys = snapshot.ingested_event_keys.into_iter().collect();

        Self {
            total_screenshots_captured: snapshot.total_screenshots_captured,
            total_recordings_completed: snapshot.total_recordings_completed,
            total_recorded_duration_ms: snapshot.total_recorded_duration_ms,
            total_screenshot_completion_duration_ms: snapshot.total_screenshot_completion_duration_ms,
            completed_screenshot_session_count: snapshot.completed_screenshot_session_count,
            total_capture_bytes_produced: snapshot.total_capture_bytes_produced,
            current_capture_streak_days: snapshot.current_capture_streak_days,
            best_capture_streak_days: snapshot.best_capture_streak_days,
            first_capture_day_key: snapshot.first_capture_day_key,
            last_capture_day_key: snapshot.last_capture_day_key,
            daily_capture,
            ingested_event_keys,
        }
    }
}

unsafe fn stats_session_from_handle_mut<'a>(
    handle: *mut c_void,
) -> Result<&'a mut vs_stats_session, i32> {
    validate_handle(&STATS_SESSION_HANDLES, handle)?;
    Ok(unsafe { &mut *handle.cast::<vs_stats_session>() })
}

unsafe fn stats_session_from_handle<'a>(handle: *const c_void) -> Result<&'a vs_stats_session, i32> {
    validate_handle(&STATS_SESSION_HANDLES, handle)?;
    Ok(unsafe { &*handle.cast::<vs_stats_session>() })
}

#[no_mangle]
pub extern "C" fn vs_stats_session_create() -> *mut c_void {
    let session = vs_stats_session {
        state: domain_capture_statistics_reset(),
    };
    let handle = Box::into_raw(Box::new(session)).cast();
    register_handle(&STATS_SESSION_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_destroy(handle: *mut c_void) {
    if !unregister_handle(&STATS_SESSION_HANDLES, handle) {
        return;
    }

    unsafe {
        drop(Box::from_raw(handle.cast::<vs_stats_session>()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_ingest_event(
    handle: *mut c_void,
    event: vs_stats_event,
    out_applied: *mut bool,
) -> i32 {
    if out_applied.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let session = match unsafe { stats_session_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    let domain_event = match to_domain_stats_event(event) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let applied = match domain_capture_statistics_ingest_event(&mut session.state, &domain_event) {
        Ok(value) => value,
        Err(_) => return VS_STATUS_INVALID_ARGUMENT,
    };

    unsafe {
        *out_applied = applied;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_get_summary(
    handle: *const c_void,
    out_summary: *mut vs_stats_summary,
) -> i32 {
    if out_summary.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let session = match unsafe { stats_session_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let summary = domain_capture_statistics_summary(&session.state);
    unsafe {
        *out_summary = to_ffi_summary(summary);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_get_recent_daily_buckets(
    handle: *const c_void,
    day_count: u32,
    out_ptr: *mut vs_stats_daily_bucket,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let session = match unsafe { stats_session_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let buckets =
        domain_capture_statistics_recent_daily_buckets(&session.state, day_count as usize);
    write_daily_buckets(buckets, out_ptr, out_cap, out_written)
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_get_all_daily_buckets(
    handle: *const c_void,
    out_ptr: *mut vs_stats_daily_bucket,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let session = match unsafe { stats_session_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let buckets = domain_capture_statistics_daily_buckets(&session.state);
    write_daily_buckets(buckets, out_ptr, out_cap, out_written)
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_reset(handle: *mut c_void) -> i32 {
    let session = match unsafe { stats_session_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    session.state = domain_capture_statistics_reset();
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_serialize_json(
    handle: *const c_void,
    out_ptr: *mut u8,
    out_len: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let session = match unsafe { stats_session_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let snapshot = VsStatsSessionSnapshot {
        version: VS_STATS_SESSION_SNAPSHOT_VERSION,
        state: VsStatsStateSnapshot::from(&session.state),
    };

    let json = match serde_json::to_vec(&snapshot) {
        Ok(value) => value,
        Err(_) => return VS_STATUS_REJECTED,
    };
    let required = json.len().min(u32::MAX as usize) as u32;
    unsafe {
        *out_written = required;
    }
    if required > out_len {
        return VS_STATUS_BUFFER_TOO_SMALL;
    }
    if required == 0 {
        return VS_STATUS_OK;
    }
    if out_ptr.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(json.as_ptr(), out_ptr, required as usize);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_stats_session_deserialize_json(
    json_ptr: *const u8,
    json_len: u32,
) -> *mut c_void {
    if json_ptr.is_null() || json_len == 0 {
        return std::ptr::null_mut();
    }

    let json = unsafe { slice::from_raw_parts(json_ptr, json_len as usize) };
    let snapshot: VsStatsSessionSnapshot = match serde_json::from_slice(json) {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    if snapshot.version != VS_STATS_SESSION_SNAPSHOT_VERSION {
        return std::ptr::null_mut();
    }

    let session = vs_stats_session {
        state: DomainCaptureStatisticsState::from(snapshot.state),
    };
    let handle = Box::into_raw(Box::new(session)).cast();
    register_handle(&STATS_SESSION_HANDLES, handle);
    handle
}

fn write_daily_buckets(
    buckets: Vec<DailyCaptureStats>,
    out_ptr: *mut vs_stats_daily_bucket,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    let total = buckets.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for (index, bucket) in buckets.iter().take(write_count).enumerate() {
        unsafe {
            *out_ptr.add(index) = to_ffi_daily_bucket(bucket);
        }
    }

    unsafe {
        *out_written = total;
    }
    VS_STATUS_OK
}

fn to_domain_stats_event(event: vs_stats_event) -> Result<DomainCaptureStatisticsEvent, i32> {
    let event_type =
        DomainCaptureStatisticsEventType::try_from(event.event_type).map_err(|_| VS_STATUS_INVALID_ARGUMENT)?;
    let event_key = parse_utf8_field(event.event_key_ptr, event.event_key_len)?;
    let capture_id = parse_utf8_field(event.capture_id_ptr, event.capture_id_len)?;
    let duration_ms = if event.duration_ms >= 0 {
        Some(event.duration_ms)
    } else {
        None
    };
    let screenshot_completion_duration_ms = if event.screenshot_completion_duration_ms >= 0 {
        Some(event.screenshot_completion_duration_ms)
    } else {
        None
    };

    Ok(DomainCaptureStatisticsEvent {
        event_key,
        event_type,
        occurred_at_ms: event.occurred_at_ms,
        timezone_offset_minutes: event.timezone_offset_minutes,
        bytes_produced: event.bytes_produced,
        duration_ms,
        screenshot_completion_duration_ms,
        capture_id,
    })
}

fn parse_utf8_field(ptr: *const u8, len: usize) -> Result<String, i32> {
    if ptr.is_null() || len == 0 {
        return Err(VS_STATUS_INVALID_ARGUMENT);
    }
    let bytes = unsafe { slice::from_raw_parts(ptr, len) };
    let value = std::str::from_utf8(bytes).map_err(|_| VS_STATUS_INVALID_ARGUMENT)?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(VS_STATUS_INVALID_ARGUMENT);
    }
    Ok(trimmed.to_string())
}

fn to_ffi_day_key(day: DomainStatsDayKey) -> vs_stats_day_key {
    vs_stats_day_key {
        year: day.year,
        month: day.month,
        day: day.day,
        reserved: 0,
    }
}

fn to_ffi_summary(summary: CaptureStatisticsSummary) -> vs_stats_summary {
    vs_stats_summary {
        total_screenshots_captured: summary.total_screenshots_captured,
        total_recordings_completed: summary.total_recordings_completed,
        total_recorded_duration_ms: summary.total_recorded_duration_ms,
        total_screenshot_completion_duration_ms: summary.total_screenshot_completion_duration_ms,
        completed_screenshot_session_count: summary.completed_screenshot_session_count,
        average_screenshot_editor_completion_duration_ms: summary
            .average_screenshot_editor_completion_duration_ms,
        total_capture_bytes_produced: summary.total_capture_bytes_produced,
        current_capture_streak_days: summary.current_capture_streak_days,
        best_capture_streak_days: summary.best_capture_streak_days,
        active_capture_days: summary.active_capture_days,
        first_capture_day: summary
            .first_capture_day_key
            .map_or(vs_stats_day_key::default(), to_ffi_day_key),
        has_first_capture_day: summary.first_capture_day_key.is_some(),
        last_capture_day: summary
            .last_capture_day_key
            .map_or(vs_stats_day_key::default(), to_ffi_day_key),
        has_last_capture_day: summary.last_capture_day_key.is_some(),
        most_active_day: summary
            .most_active_day_key
            .map_or(vs_stats_day_key::default(), to_ffi_day_key),
        has_most_active_day: summary.most_active_day_key.is_some(),
        most_active_day_score: summary.most_active_day_score,
    }
}

fn to_ffi_daily_bucket(bucket: &DailyCaptureStats) -> vs_stats_daily_bucket {
    vs_stats_daily_bucket {
        day: to_ffi_day_key(bucket.day_key),
        screenshot_count: bucket.screenshot_count,
        recording_count: bucket.recording_count,
        recorded_duration_ms: bucket.recorded_duration_ms,
        capture_bytes_produced: bucket.capture_bytes_produced,
        first_capture_at_ms: bucket.first_capture_at_ms.unwrap_or_default(),
        has_first_capture_at_ms: bucket.first_capture_at_ms.is_some(),
        last_capture_at_ms: bucket.last_capture_at_ms.unwrap_or_default(),
        has_last_capture_at_ms: bucket.last_capture_at_ms.is_some(),
    }
}
