# VivyShot Capture Statistics Spec

- Status: Active Draft
- Date: 2026-04-07
- Owner: VivyShot
- Related: `docs/capture-history-spec.md`, `docs/video-editor-spec.md`, `macos/Sources/App/Features/Store/StoreDomain.swift`

## 1. Problem Statement

VivyShot can already justify paid features around export controls and editing quality, but it does not yet turn repeated daily usage into a visible sense of progress.

Users who capture all day want to see:

1. How many screenshots they have taken.
2. How many recordings they have made.
3. How much total recording time they have accumulated.
4. How much storage VivyShot-generated captures have used.
5. A simple contribution-style daily graph and streak model that makes usage feel alive.
6. How long screenshots usually take from editor entry to finish.

This should be a premium, emotional-retention feature, not a remote analytics system.

## 2. Product Goals

1. Add a polished local-only statistics experience for heavy users.
2. Make the feature feel durable across months and years, not just recent history.
3. Gate full statistics behind paid unlock tiers, with `Lifetime` as the base unlock and `Supporter` inheriting all `Lifetime` capabilities.
4. Keep capture-time write overhead negligible.
5. Reuse existing history/capture events where practical instead of inventing a second full media index.
6. Keep semantics identical across all official surfaces.

## 3. Non-Goals (Initial Ship)

1. No remote telemetry.
2. No account sync or cross-device stats merge.
3. No team/workspace analytics.
4. No social sharing or public profile.
5. No billing-driven quotas based on usage volume.
6. No remote/cloud sync contract in v1.

## 4. Locked Product Decisions

### 4.1 Business Model

Statistics is a paid unlock feature.

Rules:

1. `Lifetime` users get full statistics UI and history.
2. `Supporter` users also get full statistics UI and history.
3. `Supporter` is the higher tier and must inherit everything `Lifetime` has.
4. Free users may see a teaser/preview entry point, but not the full dashboard.

### 4.2 Privacy Model

Statistics are local-only and derived only from VivyShot-owned capture actions.

Rules:

1. No network upload.
2. No third-party analytics SDK dependency.
3. No inspection of unrelated user files outside VivyShot-managed flows.

### 4.3 Ownership Split

Statistics are a **Rust-core domain with surface-owned adapters**.

Rust core owns:

1. statistics event schema
2. aggregation rules
3. streak logic
4. daily rollup logic
5. query/projection logic for summary cards and graph buckets
6. cross-surface canonical semantics
7. canonical time-bucketing policy

Surface owns:

1. detecting successful capture lifecycle events
2. entitlement checks
3. UI windows and presentation
4. storage backend implementation and file path selection
5. scheduling compaction, reset, and migration hooks

## 5. Why This Should Live In Rust Core

The repo goal is to keep shared behavior in the Rust core when it should remain identical across macOS, Windows, and Linux.

Capture statistics fit that boundary if they are modeled correctly:

1. The canonical meaning of a screenshot capture, completed recording, streak day, daily bucket, and byte accounting should not drift by surface.
2. The daily graph and streak math should be identical across platforms.
3. Lifetime aggregates should be reconstructible and queryable from a shared domain engine.
4. Future surfaces should not re-implement and subtly diverge on idempotency, day-boundary semantics, or counting rules.
5. Timezone and DST handling should be deterministic across platforms.

The correct split is therefore not "surface-only stats". The correct split is:

1. Rust core owns the statistics engine.
2. Surface feeds normalized events into that engine.
3. Surface stores the engine state using a platform-local persistence adapter.

This also resolves the mismatch with `docs/capture-history-spec.md`:

1. History remains retention-bound recent-media indexing.
2. Statistics becomes a separate long-lived core-owned domain that can outlive history retention.

## 6. UX Specification

### 6.1 Entry Points

Add:

1. `Statistics…` in the menu bar app.
2. Optional compact statistics card in Settings or Store upsell surfaces.
3. Optional teaser row in free tier:
   - `Statistics`
   - subtitle: `Unlock Lifetime or Supporter to see your capture streaks and totals`

### 6.2 Statistics Window

Window sections:

1. Summary cards:
   - `Total Screenshots`
   - `Total Recordings`
   - `Total Recording Time`
   - `Average Screenshot Time`
   - `Capture Storage Produced`
   - `Current Streak`
   - `Best Streak`
2. Activity graph:
   - GitHub-style daily grid
   - default range: last 26 weeks
   - optional range toggle: `3M`, `6M`, `1Y`, `All`
3. Breakdown section:
   - screenshots this week / month / all time
   - recordings this week / month / all time
   - recorded minutes this week / month / all time
   - storage produced this week / month / all time
4. Milestones section:
   - first screenshot date
   - first recording date
   - most active day

### 6.3 Graph Semantics

Each graph cell represents one local calendar day.

Intensity is based on a weighted daily activity score:

```text
dailyScore =
  screenshotCount
  + (recordingCount * 3)
  + floor(recordedDurationMinutes / 5)
```

Rules:

1. Zero activity days render empty.
2. Non-zero days render one of 4 filled intensities.
3. Tooltip shows exact daily totals.

### 6.4 Streak Semantics

A streak increments when a day has at least one qualifying capture action:

1. screenshot captured, or
2. recording successfully completed

Open/reveal/copy-again actions do not extend streaks.

## 7. Metric Definitions (Normative)

### 7.1 Primary Statistics Metrics

```text
totalScreenshotsCaptured: Int64
totalRecordingsCompleted: Int64
totalRecordedDurationMs: Int64
totalScreenshotCompletionDurationMs: Int64
completedScreenshotSessionCount: Int64
totalCaptureBytesProduced: Int64
currentCaptureStreakDays: Int32
bestCaptureStreakDays: Int32
```

Derived:

```text
averageScreenshotCompletionDurationMs =
  totalScreenshotCompletionDurationMs / completedScreenshotSessionCount
```

### 7.2 Daily Rollup Model

```text
DailyCaptureStats {
  dayKey: String                // local date, format YYYY-MM-DD
  screenshotCount: Int32
  recordingCount: Int32
  recordedDurationMs: Int64
  captureBytesProduced: Int64
  firstCaptureAtMs: Int64?
  lastCaptureAtMs: Int64?
}
```

### 7.3 Counting Rules

`totalScreenshotsCaptured` increments on successful screenshot capture completion, regardless of whether the result is copied or saved.

`totalRecordingsCompleted` increments when recording stop completes and a valid output artifact exists.

`totalRecordedDurationMs` adds recording duration once per completed recording.

`totalCaptureBytesProduced` adds only the primary VivyShot-generated artifact size for the original capture result:

1. screenshot primary image bytes
2. recording primary file bytes

Do not count:

1. duplicate user exports of the same source item
2. thumbnails
3. transient failed outputs
4. later re-saves from History

### 7.4 Screenshot Time Metric

`Average Screenshot Time` in the UI is defined internally as `average screenshot editor completion time`.

Session boundary:

1. start when a screenshot capture successfully enters the editor
2. end when the screenshot session is successfully finished through a user-completing action

Qualifying finish actions for v1:

1. `Copy`
2. `Save`

Rules:

1. Count only sessions that have both a valid start and a qualifying finish.
2. Do not count abandoned editor sessions in the average.
3. Do not count later reopen-from-history actions as part of the original screenshot completion time.
4. If idle-time filtering is added later, it must be applied consistently across all surfaces.
5. Instant screenshot flows that never enter the editor are excluded from this metric in v1.
6. UI copy must not imply that this metric covers all screenshot workflows.

## 8. Architecture

### 8.1 Source Of Truth

For v1, the source of truth is a **Rust-core statistics domain** persisted by the host surface.

Preferred write flow:

1. Capture/recording finishes on the host surface.
2. Surface normalizes the result into a core-defined statistics event.
3. Rust core ingests the event and updates statistics state.
4. Surface persists the updated state or core-generated mutation through its storage adapter.
5. History writer may separately record recent-media history entries.

### 8.2 Relationship To Capture History

Statistics should integrate with the history feature, but not be fully derived from live history rows.

Reason:

1. History rows may expire.
2. Statistics must remain durable after history retention cleanup.

Therefore:

1. History remains the recent-item/media index.
2. Stats remains the long-lived aggregate ledger/rollup.
3. Shared identifiers may link the two domains, but statistics must not depend on retained history rows for correctness.

### 8.3 Persistence Shape

Surfaces may use the same SQLite database family under `Application Support/VivyShot/`, but statistics tables remain logically separate from history tables.

Suggested path:

1. `Application Support/VivyShot/history/history.sqlite`

macOS may store statistics in the same DB initially, but the domain model and schema semantics are defined by Rust core rather than by Swift-only code.

### 8.4 Core Engine Model

Rust core should expose:

1. event input types
2. aggregate state types
3. ingest/update functions
4. summary query functions
5. graph projection functions
6. reset and backfill helpers

Preferred architecture inside `vivyshot-core`:

1. pure deterministic functions over explicit state
2. no direct SQLite dependency in the core crate
3. no store entitlement logic in core
4. no surface UI types in core
5. no surface-owned day-bucket derivation in core inputs

### 8.5 Core/Surface Contract

#### 8.5.1 Delivery Semantics

Surface-to-core delivery uses an **at-least-once** contract.

Rules:

1. Surface emits events only after the corresponding host-side action has succeeded.
2. Surface may retry the same event after crash/restart or uncertain commit state.
3. Rust core must treat duplicate `event_key` values as a no-op and report whether an event was newly applied.
4. Live ingestion may use one-event-at-a-time delivery in v1.
5. Batch ingestion is optional, but if added later it must preserve the same event semantics as repeated single-event ingestion.

#### 8.5.2 Ordering And Idempotency

Rules:

1. For normal live operation, surface should deliver events in nondecreasing `occurredAtMs`.
2. If both screenshot events exist for the same `captureId`, `screenshotCaptured` must not have a later `occurredAtMs` than `screenshotSessionCompleted`.
3. Duplicate `event_key` values are never an error; they are a deterministic no-op.
4. If a surface needs to insert older historical events after newer live events were already applied, it must trigger a projection rebuild from the authoritative event ledger.
5. Rebuild replay order is fixed as `occurred_at_ms ASC, event_key ASC`.

#### 8.5.3 Persistence Authority

Authority split:

1. `stats_ingested_events` is the authoritative durable ledger for correctness and rebuild.
2. `stats_lifetime_totals` and `stats_daily_capture` are derived projections optimized for reads.
3. Rust core owns semantic validation and projection derivation.
4. Surface owns physical storage, SQLite transactions, schema migration, and file location.
5. If the ledger and projections disagree, the ledger wins and projections must be rebuilt.

#### 8.5.4 Replay And Rebuild Rules

Rules:

1. Surface may hydrate a Rust stats session from persisted snapshot/projection state as a startup optimization.
2. The canonical recovery path is replay from `stats_ingested_events`.
3. If projection rows are missing, corrupt, or version-incompatible, surface must discard projections and rebuild from the authoritative ledger.
4. `Reset Statistics…` clears both the authoritative event ledger and all derived projections.
5. Replay must be deterministic and produce the same totals, streaks, and daily buckets on every official surface.

#### 8.5.5 Concrete FFI / Session API Shape

The statistics engine should follow the existing session-oriented FFI style already used for video and timeline domains.

Minimum v1 API shape:

```text
vs_stats_session_create() -> handle
vs_stats_session_destroy(handle)

vs_stats_session_ingest_event(handle, event, out_applied) -> status
vs_stats_session_get_summary(handle, out_summary) -> status
vs_stats_session_get_recent_daily_buckets(handle, day_count, out_ptr, out_cap, out_written) -> status
vs_stats_session_get_all_daily_buckets(handle, out_ptr, out_cap, out_written) -> status
vs_stats_session_reset(handle) -> status

vs_stats_session_serialize_json(handle, out_ptr, out_len, out_written) -> status
vs_stats_session_deserialize_json(json_ptr, json_len) -> handle
```

Contract rules:

1. `ingest_event` returns whether the event changed state so the surface can avoid redundant projection writes.
2. Daily-bucket query results must be returned in ascending canonical day order.
3. JSON serialization is an optimization for session snapshot persistence, not a replacement for the authoritative event ledger.
4. FFI types must remain control-plane only; no raw media bytes cross this boundary.

## 9. Persistence Specification

### 9.1 Logical Persistence Model (Normative)

The following schema is normative at the logical level. Surfaces may map it to SQLite tables directly.

```sql
CREATE TABLE stats_lifetime_totals (
  singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
  total_screenshots_captured INTEGER NOT NULL DEFAULT 0,
  total_recordings_completed INTEGER NOT NULL DEFAULT 0,
  total_recorded_duration_ms INTEGER NOT NULL DEFAULT 0,
  total_screenshot_completion_duration_ms INTEGER NOT NULL DEFAULT 0,
  completed_screenshot_session_count INTEGER NOT NULL DEFAULT 0,
  total_capture_bytes_produced INTEGER NOT NULL DEFAULT 0,
  current_capture_streak_days INTEGER NOT NULL DEFAULT 0,
  best_capture_streak_days INTEGER NOT NULL DEFAULT 0,
  first_capture_day_key TEXT,
  last_capture_day_key TEXT,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE stats_daily_capture (
  day_key TEXT PRIMARY KEY,
  screenshot_count INTEGER NOT NULL DEFAULT 0,
  recording_count INTEGER NOT NULL DEFAULT 0,
  recorded_duration_ms INTEGER NOT NULL DEFAULT 0,
  capture_bytes_produced INTEGER NOT NULL DEFAULT 0,
  first_capture_at_ms INTEGER,
  last_capture_at_ms INTEGER
);

CREATE TABLE stats_ingested_events (
  event_key TEXT PRIMARY KEY,
  source_type TEXT NOT NULL CHECK (
    source_type IN (
      'screenshot_capture',
      'screenshot_session_completed',
      'recording_completed'
    )
  ),
  occurred_at_ms INTEGER NOT NULL,
  timezone_offset_minutes INTEGER NOT NULL,
  capture_id TEXT NOT NULL,
  bytes_produced INTEGER NOT NULL,
  duration_ms INTEGER,
  screenshot_completion_duration_ms INTEGER,
  persisted_at_ms INTEGER NOT NULL
);
```

Recommended indexes:

```sql
CREATE INDEX idx_stats_ingested_events_occurred
ON stats_ingested_events(occurred_at_ms ASC, event_key ASC);

CREATE INDEX idx_stats_ingested_events_capture
ON stats_ingested_events(capture_id, source_type);
```

### 9.2 Idempotency Rule

Statistics writes must be idempotent.

Each qualifying capture event must generate a stable `event_key` so retries or crashes do not double count totals.

Examples:

1. screenshot capture: `screenshot_capture:<captureId>`
2. screenshot session completed: `screenshot_session_completed:<captureId>`
3. recording completed: `recording_completed:<recordingId>`

Rules:

1. `event_key` must be namespaced by event type.
2. Different event types for the same capture session must not collide.
3. The same logical event retried on the same surface must reuse the same `event_key`.
4. Cross-surface implementations must preserve the same key semantics.
5. `captureId` is the shared logical identifier across events in the same screenshot flow.

### 9.3 Core Event Model

Rust core should define a normalized input shape similar to:

```text
StatisticsEvent {
  eventKey: String
  eventType: screenshotCaptured | screenshotSessionCompleted | recordingCompleted
  occurredAtMs: Int64
  timezoneOffsetMinutes: Int32
  bytesProduced: Int64
  durationMs: Int64?           // recording only
  screenshotCompletionDurationMs: Int64?   // screenshotSessionCompleted only
  captureId: String
}
```

Surface is responsible for:

1. generating stable event keys
2. providing the capture timestamp and timezone offset at the moment of the event
3. ensuring only successful capture outcomes are emitted
4. measuring screenshot completion duration from editor entry to qualifying finish

Rust core is responsible for:

1. deriving canonical `dayKey` from `occurredAtMs` and `timezoneOffsetMinutes`
2. applying the same day-bucketing logic on every surface
3. evaluating streak transitions from canonical day keys
4. returning deterministic projections after ingest or replay

### 9.4 Canonical Day-Bucketing Policy

Daily buckets and streaks must be derived in Rust core, not by surfaces.

Rule set:

1. Each event carries `occurredAtMs` plus `timezoneOffsetMinutes` captured at event time.
2. Rust core derives the local calendar day key from those two values.
3. Day key format is fixed as `YYYY-MM-DD`.
4. If the user travels or DST changes occur, the bucket is based on the offset attached to the original event.
5. Reprojection must be deterministic when rebuilding aggregates from stored events.

### 9.5 Streak Update Rule

When ingesting a new day:

1. if `last_capture_day_key` is null:
   - set current streak to `1`
2. if new `day_key == last_capture_day_key`:
   - do not increment streak again
3. if new `day_key` is exactly next local calendar day after `last_capture_day_key`:
   - increment current streak by `1`
4. otherwise:
   - reset current streak to `1`
5. update `best_capture_streak_days = max(best, current)`

## 10. Read APIs and Projections

Rust core should expose read models such as:

```text
StatisticsSummaryViewModel
StatisticsDailyGraphPoint
StatisticsMilestoneViewModel
```

Surface may map these core projections into native UI view models.

FFI additions are expected for v1 if macOS consumes the statistics engine through the existing C ABI boundary.

The summary projection should expose an explicitly named field such as:

```text
averageScreenshotEditorCompletionDurationMs
```

so UI labels can stay friendly without losing metric precision.

## 11. Entitlement Model

Introduce a distinct capability check rather than reusing generic paid access.

Required new concept:

```text
StoreCapability.statisticsDashboard
```

Resolution rule for v1:

1. unlocked when `hasLifetimeUnlock == true` or `hasSupporterBadge == true`

In the current store model, this is equivalent to `hasPaidAccess`, but the product contract should still describe it as an explicit capability rather than as generic payment state.

## 12. Free / Locked Experience

For locked users:

1. Show entry point and positioning copy.
2. Show static preview or last-30-days mini mock if desired.
3. Do not reveal lifetime totals, streak counts, or full graph history.

Avoid hostile UX:

1. no modal spam after every capture
2. no blocking normal screenshot/recording flow

## 13. Performance and Reliability Targets

1. Stats write overhead on capture completion:
   - p95 < 5 ms incremental DB work
2. Statistics window first paint:
   - p95 < 120 ms for 1 year of daily buckets
3. Writes must be crash-safe and idempotent.
4. Stats corruption must not block capture flow.
5. Rebuilding projections from persisted events or state must be deterministic across surfaces.

## 14. Privacy and Data Handling

1. Local-only.
2. No raw image bytes in stats tables.
3. No clipboard payload contents.
4. No OCR/text extraction for stats.
5. Clearing history does not have to clear statistics unless the product exposes an explicit `Reset Statistics…` action.

## 15. Settings and Data Controls

Add optional settings actions:

1. `Open Statistics`
2. `Reset Statistics…`
3. `Include screenshots in streaks` and `Include recordings in streaks`

Initial simplification allowed:

1. Ship without user-configurable streak rules.
2. Default streak qualification includes both screenshots and recordings.

## 16. Migration Strategy

If statistics ships after history:

1. Backfill from existing history rows when possible.
2. Backfill only within retained history horizon.
3. Mark resulting totals as best-effort bootstrap, then continue from live capture events.

Important:

1. Backfill cannot reconstruct data already evicted by history retention.
2. Product copy must avoid implying perfect pre-feature lifetime reconstruction.
3. Backfill cannot reconstruct screenshot editor completion time unless the source history/events already contain editor-session start and finish timestamps.

## 17. Test Plan

### 17.1 Unit Tests

1. Daily rollup accumulation.
2. Idempotent re-ingest behavior.
3. Streak transitions across same day / next day / skipped day.
4. Byte counting rules excluding exports and thumbnails.
5. Projection stability for graph buckets and summary totals.
6. Screenshot completion duration accumulation and averaging.
7. Canonical day-key derivation across DST and timezone-offset changes.

### 17.2 Integration Tests

1. Screenshot capture increments totals and same-day graph bucket.
2. Screenshot editor entry -> `Copy` or `Save` records screenshot completion duration once.
3. Recording completion increments count, duration, and bytes.
4. Save/export after capture does not double count base stats.
5. Clearing history metadata does not erase statistics.
6. Reset statistics clears totals and graph buckets.
7. macOS storage round-trip preserves core statistics state without semantic drift.
8. Replaying stored events reproduces the same totals and day buckets.

### 17.3 UI Tests

1. Lifetime user can open statistics window.
2. Supporter user can open statistics window.
3. Free user sees locked state.
4. Graph renders correct tooltip/day details.

## 18. Release Scope (v1)

Must ship:

1. Paid-tier statistics window for `Lifetime` and `Supporter`.
2. Summary totals.
3. GitHub-style daily activity graph.
4. Current streak and best streak.
5. Screenshot count, recording count, recorded duration, average screenshot editor completion time, and bytes produced.
6. Durable local rollups that survive normal history retention.

Should wait:

1. cross-device sync
2. achievements/badges
3. per-project/editor stats
4. advanced leaderboards/achievements
