use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};
use time::{Date, Month, OffsetDateTime, UtcOffset};

pub const STATS_EVENT_SCREENSHOT_CAPTURED: u8 = 0;
pub const STATS_EVENT_SCREENSHOT_SESSION_COMPLETED: u8 = 1;
pub const STATS_EVENT_RECORDING_COMPLETED: u8 = 2;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct StatsDayKey {
    pub year: i32,
    pub month: u8,
    pub day: u8,
}

impl StatsDayKey {
    pub fn from_timestamp_ms_and_offset(
        occurred_at_ms: i64,
        timezone_offset_minutes: i32,
    ) -> Option<Self> {
        let seconds = timezone_offset_minutes.checked_mul(60)?;
        let offset = UtcOffset::from_whole_seconds(seconds).ok()?;
        let timestamp_nanos = (occurred_at_ms as i128).checked_mul(1_000_000)?;
        let utc = OffsetDateTime::from_unix_timestamp_nanos(timestamp_nanos).ok()?;
        Some(Self::from_date(utc.to_offset(offset).date()))
    }

    pub fn to_yyyy_mm_dd(self) -> String {
        format!("{:04}-{:02}-{:02}", self.year, self.month, self.day)
    }

    pub fn is_next_day_after(self, other: Self) -> bool {
        let Some(date) = other.as_date() else {
            return false;
        };
        let Some(next) = date.next_day() else {
            return false;
        };
        Self::from_date(next) == self
    }

    fn from_date(date: Date) -> Self {
        Self {
            year: date.year(),
            month: date.month() as u8,
            day: date.day(),
        }
    }

    fn as_date(self) -> Option<Date> {
        let month = Month::try_from(self.month).ok()?;
        Date::from_calendar_date(self.year, month, self.day).ok()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum CaptureStatisticsEventType {
    ScreenshotCaptured,
    ScreenshotSessionCompleted,
    RecordingCompleted,
}

impl CaptureStatisticsEventType {
    pub fn to_ffi_code(self) -> u8 {
        match self {
            Self::ScreenshotCaptured => STATS_EVENT_SCREENSHOT_CAPTURED,
            Self::ScreenshotSessionCompleted => STATS_EVENT_SCREENSHOT_SESSION_COMPLETED,
            Self::RecordingCompleted => STATS_EVENT_RECORDING_COMPLETED,
        }
    }
}

impl TryFrom<u8> for CaptureStatisticsEventType {
    type Error = CaptureStatisticsError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            STATS_EVENT_SCREENSHOT_CAPTURED => Ok(Self::ScreenshotCaptured),
            STATS_EVENT_SCREENSHOT_SESSION_COMPLETED => Ok(Self::ScreenshotSessionCompleted),
            STATS_EVENT_RECORDING_COMPLETED => Ok(Self::RecordingCompleted),
            _ => Err(CaptureStatisticsError::InvalidEventType),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureStatisticsEvent {
    pub event_key: String,
    pub event_type: CaptureStatisticsEventType,
    pub occurred_at_ms: i64,
    pub timezone_offset_minutes: i32,
    pub bytes_produced: i64,
    pub duration_ms: Option<i64>,
    pub screenshot_completion_duration_ms: Option<i64>,
    pub capture_id: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DailyCaptureStats {
    pub day_key: StatsDayKey,
    pub screenshot_count: i32,
    pub recording_count: i32,
    pub recorded_duration_ms: i64,
    pub capture_bytes_produced: i64,
    pub first_capture_at_ms: Option<i64>,
    pub last_capture_at_ms: Option<i64>,
}

impl DailyCaptureStats {
    pub fn activity_score(&self) -> i64 {
        i64::from(self.screenshot_count)
            + (i64::from(self.recording_count) * 3)
            + (self.recorded_duration_ms / 300_000)
    }

    fn record_screenshot(&mut self, occurred_at_ms: i64, bytes_produced: i64) {
        self.screenshot_count = self.screenshot_count.saturating_add(1);
        self.capture_bytes_produced = self.capture_bytes_produced.saturating_add(bytes_produced);
        self.update_time_bounds(occurred_at_ms);
    }

    fn record_recording(&mut self, occurred_at_ms: i64, duration_ms: i64, bytes_produced: i64) {
        self.recording_count = self.recording_count.saturating_add(1);
        self.recorded_duration_ms = self.recorded_duration_ms.saturating_add(duration_ms);
        self.capture_bytes_produced = self.capture_bytes_produced.saturating_add(bytes_produced);
        self.update_time_bounds(occurred_at_ms);
    }

    fn update_time_bounds(&mut self, occurred_at_ms: i64) {
        self.first_capture_at_ms = Some(
            self.first_capture_at_ms
                .map_or(occurred_at_ms, |value| value.min(occurred_at_ms)),
        );
        self.last_capture_at_ms = Some(
            self.last_capture_at_ms
                .map_or(occurred_at_ms, |value| value.max(occurred_at_ms)),
        );
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureStatisticsState {
    pub total_screenshots_captured: i64,
    pub total_recordings_completed: i64,
    pub total_recorded_duration_ms: i64,
    pub total_screenshot_completion_duration_ms: i64,
    pub completed_screenshot_session_count: i64,
    pub total_capture_bytes_produced: i64,
    pub current_capture_streak_days: i32,
    pub best_capture_streak_days: i32,
    pub first_capture_day_key: Option<StatsDayKey>,
    pub last_capture_day_key: Option<StatsDayKey>,
    pub daily_capture: BTreeMap<StatsDayKey, DailyCaptureStats>,
    pub ingested_event_keys: HashSet<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CaptureStatisticsSummary {
    pub total_screenshots_captured: i64,
    pub total_recordings_completed: i64,
    pub total_recorded_duration_ms: i64,
    pub total_screenshot_completion_duration_ms: i64,
    pub completed_screenshot_session_count: i64,
    pub average_screenshot_editor_completion_duration_ms: i64,
    pub total_capture_bytes_produced: i64,
    pub current_capture_streak_days: i32,
    pub best_capture_streak_days: i32,
    pub active_capture_days: i32,
    pub first_capture_day_key: Option<StatsDayKey>,
    pub last_capture_day_key: Option<StatsDayKey>,
    pub most_active_day_key: Option<StatsDayKey>,
    pub most_active_day_score: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureStatisticsError {
    InvalidEventType,
    InvalidEventKey,
    InvalidCaptureID,
    InvalidTimezoneOffset,
    InvalidTimestamp,
    InvalidBytesProduced,
    InvalidDuration,
    MissingDuration,
    MissingScreenshotCompletionDuration,
    UnexpectedDuration,
    UnexpectedScreenshotCompletionDuration,
}

pub fn capture_statistics_ingest_event(
    state: &mut CaptureStatisticsState,
    event: &CaptureStatisticsEvent,
) -> Result<bool, CaptureStatisticsError> {
    validate_event(event)?;

    if !state.ingested_event_keys.insert(event.event_key.clone()) {
        return Ok(false);
    }

    match event.event_type {
        CaptureStatisticsEventType::ScreenshotCaptured => {
            let day_key = derive_event_day_key(event)?;
            state.total_screenshots_captured = state.total_screenshots_captured.saturating_add(1);
            state.total_capture_bytes_produced = state
                .total_capture_bytes_produced
                .saturating_add(event.bytes_produced);
            let bucket = state.daily_capture.entry(day_key).or_insert_with(|| DailyCaptureStats {
                day_key,
                ..DailyCaptureStats::default()
            });
            bucket.record_screenshot(event.occurred_at_ms, event.bytes_produced);
            update_streak(state, day_key);
        }
        CaptureStatisticsEventType::ScreenshotSessionCompleted => {
            let duration_ms = event
                .screenshot_completion_duration_ms
                .expect("validated screenshot completion duration");
            state.total_screenshot_completion_duration_ms = state
                .total_screenshot_completion_duration_ms
                .saturating_add(duration_ms);
            state.completed_screenshot_session_count =
                state.completed_screenshot_session_count.saturating_add(1);
        }
        CaptureStatisticsEventType::RecordingCompleted => {
            let duration_ms = event.duration_ms.expect("validated recording duration");
            let day_key = derive_event_day_key(event)?;
            state.total_recordings_completed = state.total_recordings_completed.saturating_add(1);
            state.total_recorded_duration_ms =
                state.total_recorded_duration_ms.saturating_add(duration_ms);
            state.total_capture_bytes_produced = state
                .total_capture_bytes_produced
                .saturating_add(event.bytes_produced);
            let bucket = state.daily_capture.entry(day_key).or_insert_with(|| DailyCaptureStats {
                day_key,
                ..DailyCaptureStats::default()
            });
            bucket.record_recording(event.occurred_at_ms, duration_ms, event.bytes_produced);
            update_streak(state, day_key);
        }
    }

    Ok(true)
}

pub fn capture_statistics_summary(state: &CaptureStatisticsState) -> CaptureStatisticsSummary {
    let (most_active_day_key, most_active_day_score) = state
        .daily_capture
        .iter()
        .fold((None, 0_i64), |best, (day_key, bucket)| {
            let score = bucket.activity_score();
            if score < best.1 {
                best
            } else {
                (Some(*day_key), score)
            }
        });

    CaptureStatisticsSummary {
        total_screenshots_captured: state.total_screenshots_captured,
        total_recordings_completed: state.total_recordings_completed,
        total_recorded_duration_ms: state.total_recorded_duration_ms,
        total_screenshot_completion_duration_ms: state.total_screenshot_completion_duration_ms,
        completed_screenshot_session_count: state.completed_screenshot_session_count,
        average_screenshot_editor_completion_duration_ms: average_screenshot_completion_duration(
            state,
        ),
        total_capture_bytes_produced: state.total_capture_bytes_produced,
        current_capture_streak_days: state.current_capture_streak_days,
        best_capture_streak_days: state.best_capture_streak_days,
        active_capture_days: state.daily_capture.len() as i32,
        first_capture_day_key: state.first_capture_day_key,
        last_capture_day_key: state.last_capture_day_key,
        most_active_day_key,
        most_active_day_score,
    }
}

pub fn capture_statistics_daily_buckets(state: &CaptureStatisticsState) -> Vec<DailyCaptureStats> {
    state.daily_capture.values().cloned().collect()
}

pub fn capture_statistics_recent_daily_buckets(
    state: &CaptureStatisticsState,
    day_count: usize,
) -> Vec<DailyCaptureStats> {
    if day_count == 0 {
        return Vec::new();
    }

    let Some(mut current_day) = state.last_capture_day_key else {
        return Vec::new();
    };

    let mut buckets = Vec::with_capacity(day_count);
    for _ in 0..day_count {
        buckets.push(
            state
                .daily_capture
                .get(&current_day)
                .cloned()
                .unwrap_or(DailyCaptureStats {
                    day_key: current_day,
                    ..DailyCaptureStats::default()
                }),
        );
        let Some(previous_date) = current_day.as_date().and_then(|value| value.previous_day()) else {
            break;
        };
        current_day = StatsDayKey::from_date(previous_date);
    }
    buckets.reverse();
    buckets
}

pub fn capture_statistics_reset() -> CaptureStatisticsState {
    CaptureStatisticsState::default()
}

fn average_screenshot_completion_duration(state: &CaptureStatisticsState) -> i64 {
    if state.completed_screenshot_session_count <= 0 {
        return 0;
    }
    state.total_screenshot_completion_duration_ms / state.completed_screenshot_session_count
}

fn validate_event(event: &CaptureStatisticsEvent) -> Result<(), CaptureStatisticsError> {
    if event.event_key.trim().is_empty() {
        return Err(CaptureStatisticsError::InvalidEventKey);
    }
    if event.capture_id.trim().is_empty() {
        return Err(CaptureStatisticsError::InvalidCaptureID);
    }
    if event.bytes_produced < 0 {
        return Err(CaptureStatisticsError::InvalidBytesProduced);
    }
    if UtcOffset::from_whole_seconds(
        event
            .timezone_offset_minutes
            .checked_mul(60)
            .ok_or(CaptureStatisticsError::InvalidTimezoneOffset)?,
    )
    .is_err()
    {
        return Err(CaptureStatisticsError::InvalidTimezoneOffset);
    }
    if StatsDayKey::from_timestamp_ms_and_offset(
        event.occurred_at_ms,
        event.timezone_offset_minutes,
    )
    .is_none()
    {
        return Err(CaptureStatisticsError::InvalidTimestamp);
    }

    match event.event_type {
        CaptureStatisticsEventType::ScreenshotCaptured => {
            if event.duration_ms.is_some() {
                return Err(CaptureStatisticsError::UnexpectedDuration);
            }
            if event.screenshot_completion_duration_ms.is_some() {
                return Err(CaptureStatisticsError::UnexpectedScreenshotCompletionDuration);
            }
        }
        CaptureStatisticsEventType::ScreenshotSessionCompleted => {
            if event.duration_ms.is_some() {
                return Err(CaptureStatisticsError::UnexpectedDuration);
            }
            let Some(duration_ms) = event.screenshot_completion_duration_ms else {
                return Err(CaptureStatisticsError::MissingScreenshotCompletionDuration);
            };
            if duration_ms < 0 {
                return Err(CaptureStatisticsError::InvalidDuration);
            }
        }
        CaptureStatisticsEventType::RecordingCompleted => {
            if event.screenshot_completion_duration_ms.is_some() {
                return Err(CaptureStatisticsError::UnexpectedScreenshotCompletionDuration);
            }
            let Some(duration_ms) = event.duration_ms else {
                return Err(CaptureStatisticsError::MissingDuration);
            };
            if duration_ms < 0 {
                return Err(CaptureStatisticsError::InvalidDuration);
            }
        }
    }

    Ok(())
}

fn derive_event_day_key(event: &CaptureStatisticsEvent) -> Result<StatsDayKey, CaptureStatisticsError> {
    StatsDayKey::from_timestamp_ms_and_offset(event.occurred_at_ms, event.timezone_offset_minutes)
        .ok_or(CaptureStatisticsError::InvalidTimestamp)
}

fn update_streak(state: &mut CaptureStatisticsState, day_key: StatsDayKey) {
    if state.first_capture_day_key.is_none() {
        state.first_capture_day_key = Some(day_key);
    }

    match state.last_capture_day_key {
        None => {
            state.current_capture_streak_days = 1;
        }
        Some(previous) if previous == day_key => {}
        Some(previous) if day_key.is_next_day_after(previous) => {
            state.current_capture_streak_days = state.current_capture_streak_days.saturating_add(1);
        }
        Some(_) => {
            state.current_capture_streak_days = 1;
        }
    }

    state.best_capture_streak_days = state
        .best_capture_streak_days
        .max(state.current_capture_streak_days);
    if state.last_capture_day_key.map_or(true, |existing| day_key > existing) {
        state.last_capture_day_key = Some(day_key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn screenshot_event(
        event_key: &str,
        capture_id: &str,
        occurred_at_ms: i64,
        offset_minutes: i32,
        bytes_produced: i64,
    ) -> CaptureStatisticsEvent {
        CaptureStatisticsEvent {
            event_key: event_key.to_string(),
            event_type: CaptureStatisticsEventType::ScreenshotCaptured,
            occurred_at_ms,
            timezone_offset_minutes: offset_minutes,
            bytes_produced,
            duration_ms: None,
            screenshot_completion_duration_ms: None,
            capture_id: capture_id.to_string(),
        }
    }

    fn screenshot_completed_event(
        event_key: &str,
        capture_id: &str,
        occurred_at_ms: i64,
        offset_minutes: i32,
        duration_ms: i64,
    ) -> CaptureStatisticsEvent {
        CaptureStatisticsEvent {
            event_key: event_key.to_string(),
            event_type: CaptureStatisticsEventType::ScreenshotSessionCompleted,
            occurred_at_ms,
            timezone_offset_minutes: offset_minutes,
            bytes_produced: 0,
            duration_ms: None,
            screenshot_completion_duration_ms: Some(duration_ms),
            capture_id: capture_id.to_string(),
        }
    }

    fn recording_event(
        event_key: &str,
        capture_id: &str,
        occurred_at_ms: i64,
        offset_minutes: i32,
        bytes_produced: i64,
        duration_ms: i64,
    ) -> CaptureStatisticsEvent {
        CaptureStatisticsEvent {
            event_key: event_key.to_string(),
            event_type: CaptureStatisticsEventType::RecordingCompleted,
            occurred_at_ms,
            timezone_offset_minutes: offset_minutes,
            bytes_produced,
            duration_ms: Some(duration_ms),
            screenshot_completion_duration_ms: None,
            capture_id: capture_id.to_string(),
        }
    }

    #[test]
    fn duplicate_events_are_no_ops() {
        let mut state = CaptureStatisticsState::default();
        let event = screenshot_event("screenshot_capture:c1", "c1", 1_710_000_000_000, 480, 10_240);
        assert_eq!(capture_statistics_ingest_event(&mut state, &event), Ok(true));
        assert_eq!(capture_statistics_ingest_event(&mut state, &event), Ok(false));
        assert_eq!(state.total_screenshots_captured, 1);
    }

    #[test]
    fn screenshot_completion_durations_accumulate() {
        let mut state = CaptureStatisticsState::default();
        let capture = screenshot_event("screenshot_capture:c1", "c1", 1_710_000_000_000, 480, 2_000);
        let completion = screenshot_completed_event(
            "screenshot_session_completed:c1",
            "c1",
            1_710_000_010_000,
            480,
            10_000,
        );
        assert_eq!(capture_statistics_ingest_event(&mut state, &capture), Ok(true));
        assert_eq!(capture_statistics_ingest_event(&mut state, &completion), Ok(true));
        let summary = capture_statistics_summary(&state);
        assert_eq!(summary.total_screenshots_captured, 1);
        assert_eq!(summary.completed_screenshot_session_count, 1);
        assert_eq!(summary.average_screenshot_editor_completion_duration_ms, 10_000);
    }

    #[test]
    fn streaks_advance_across_consecutive_days() {
        let mut state = CaptureStatisticsState::default();
        let first = screenshot_event("screenshot_capture:c1", "c1", 1_710_000_000_000, 0, 1_000);
        let second = screenshot_event(
            "screenshot_capture:c2",
            "c2",
            1_710_086_400_000,
            0,
            1_500,
        );
        assert_eq!(capture_statistics_ingest_event(&mut state, &first), Ok(true));
        assert_eq!(state.current_capture_streak_days, 1);
        assert_eq!(capture_statistics_ingest_event(&mut state, &second), Ok(true));
        assert_eq!(state.current_capture_streak_days, 2);
        assert_eq!(state.best_capture_streak_days, 2);
    }

    #[test]
    fn recording_updates_duration_bytes_and_daily_score() {
        let mut state = CaptureStatisticsState::default();
        let event = recording_event(
            "recording_completed:r1",
            "r1",
            1_710_000_000_000,
            0,
            25_000_000,
            610_000,
        );
        assert_eq!(capture_statistics_ingest_event(&mut state, &event), Ok(true));
        let summary = capture_statistics_summary(&state);
        assert_eq!(summary.total_recordings_completed, 1);
        assert_eq!(summary.total_recorded_duration_ms, 610_000);
        assert_eq!(summary.total_capture_bytes_produced, 25_000_000);
        assert_eq!(summary.most_active_day_score, 5);
    }

    #[test]
    fn recent_daily_buckets_zero_fill_gaps() {
        let mut state = CaptureStatisticsState::default();
        let first = screenshot_event("screenshot_capture:c1", "c1", 1_710_000_000_000, 0, 1_000);
        let third = screenshot_event(
            "screenshot_capture:c3",
            "c3",
            1_710_172_800_000,
            0,
            1_000,
        );
        assert_eq!(capture_statistics_ingest_event(&mut state, &first), Ok(true));
        assert_eq!(capture_statistics_ingest_event(&mut state, &third), Ok(true));

        let recent = capture_statistics_recent_daily_buckets(&state, 3);
        assert_eq!(recent.len(), 3);
        assert_eq!(recent[0].screenshot_count, 1);
        assert_eq!(recent[1].screenshot_count, 0);
        assert_eq!(recent[2].screenshot_count, 1);
    }

    #[test]
    fn timezone_offset_changes_bucket_day() {
        let utc_ms = 1_710_003_600_000; // 2024-03-10T01:00:00Z
        let pacific = StatsDayKey::from_timestamp_ms_and_offset(utc_ms, -480).unwrap();
        let china = StatsDayKey::from_timestamp_ms_and_offset(utc_ms, 480).unwrap();
        assert_ne!(pacific, china);
        assert_eq!(pacific.to_yyyy_mm_dd(), "2024-03-09");
        assert_eq!(china.to_yyyy_mm_dd(), "2024-03-10");
    }
}
