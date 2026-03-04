# VivyShot Capture History Spec (Screenshots + Recordings)

- Status: Active Draft
- Date: 2026-03-04
- Owner: VivyShot
- Related: `SPEC.md`, `docs/video-editor-spec.md`

## 1. Problem Statement

Users can capture quickly, but recently captured screenshots and recordings are hard to find again in Finder.

VivyShot needs a first-class in-app history so users can quickly reopen, copy, re-save, or reveal recent captures without file browsing friction.

## 2. Product Goals

1. Make the latest captures accessible in one click from the menu bar app.
2. Provide a gallery-style History window for fast visual browsing.
3. Include both:
   - explicitly saved captures
   - clipboard-only captures (copied but not manually saved)
4. Apply retention rules so copied/temporary media does not grow unbounded.
5. Keep capture flow fast; history indexing must not add noticeable delay.

## 3. Non-Goals (Initial Ship)

1. No cloud sync of history.
2. No cross-device history.
3. No full media management system (albums/tags/search-by-text).
4. No destructive editing inside History (editing remains in editor/capture flows).
5. No in-history video trimming/transcoding.

## 4. Locked Product Decisions

### 4.1 Entry Points

History is accessible from two places in the menu bar app:

1. `History…` menu action that opens the History window.
2. Inline `Recent Captures` section in the menu with newest items for one-click access.

### 4.2 History Window Type

History opens as a normal app window (not a tiny popover), optimized for quick browsing:

1. Gallery/grid visual layout.
2. Newest-first ordering by default.
3. Keyboard navigation and quick actions.

### 4.3 Capture Sources Included

History includes:

1. Screenshot captures copied to clipboard.
2. Screenshot captures explicitly saved/exported.
3. Video recordings produced by VivyShot:
   - temporary working output
   - explicitly saved/exported output

### 4.4 Retention Policy

Retention is source-aware:

1. Saved captures:
   - keep history metadata for 30 days by default
   - do not duplicate user file bytes
2. Copied-only screenshots:
   - persist app-managed cache artifact so they remain recoverable
   - keep for 7 days by default unless promoted to explicit save
3. Unsaved temporary recordings:
   - keep for 3 days by default
4. Global guardrails:
   - max entries: 500
   - max cache bytes (copied/temp artifacts): 5 GB
   - eviction: oldest-first among non-saved artifacts

Retention values are configurable in Settings; defaults above are mandatory for first ship.

## 5. Terminology

1. Capture:
   - any screenshot or recording produced by VivyShot.
2. History Item:
   - logical row shown in History UI.
3. Artifact:
   - physical media file referenced by a history item.
4. Saved Artifact:
   - user-chosen destination file.
5. Cached Artifact:
   - app-managed file for copied or temporary outputs.
6. Source Flags:
   - item-origin labels: `copied`, `saved`, `temporary`.
7. Promotion:
   - transition of item from copied/temp only to saved.

## 6. UX Specification

### 6.1 Menu Bar Inline Recents

Add `Recent Captures` section under capture actions:

1. Show up to 5 latest items by default (user-configurable).
2. Row label format:
   - `[type icon] <title> · <relative time>`
3. Row behavior:
   - screenshot: open preview/editor target
   - recording: open preview/post-record context
4. Footer actions:
   - `Open History…`
   - `Clear Copied/Temporary History…`

If no items exist, show disabled row `No recent captures`.

### 6.2 History Window Layout

Window sections:

1. Top bar:
   - filter: `All`, `Screenshots`, `Recordings`, `Saved`, `Copied`
   - sort: `Newest First` (default), `Oldest First`
2. Main gallery:
   - responsive thumbnail grid
   - tile metadata: thumbnail, type badge, timestamp, source badges (`Saved` / `Copied` / `Temp`)
3. Action strip:
   - `Open`
   - `Reveal in Finder` (when file exists)
   - `Copy Again`
   - `Save As…` (for copied/temp or missing saved-path fallback)
   - `Delete from History`

### 6.3 Empty and Error States

1. Empty state:
   - title: `No captures yet`
   - hint: `Take a screenshot or recording to populate history.`
2. Missing file state:
   - tile marked unavailable
   - `Reveal in Finder` disabled
   - allowed actions: `Delete from History`, `Save As…` if cached artifact exists

## 7. Domain Model

### 7.1 Enums

```text
CaptureKind = screenshot | recording

ArtifactRole = primary | derivative | thumbnail

StorageClass = saved_external | cache_managed

SourceFlag = copied | saved | temporary

AvailabilityState = available | missing | purged
```

### 7.2 Logical Data Structures

```text
HistoryItem {
  id: UUID
  kind: CaptureKind
  sourceFlags: Set<SourceFlag>
  createdAtMs: Int64
  lastUpdatedAtMs: Int64

  title: String
  durationMs: Int64?            // recording only
  widthPx: Int32
  heightPx: Int32
  byteSize: Int64?              // preferred visible artifact byte count

  availability: AvailabilityState
  openedCount: Int32
  lastOpenedAtMs: Int64?

  dedupeKey: String             // stable hash key for merge window
}

ArtifactRef {
  id: UUID
  historyItemId: UUID
  role: ArtifactRole            // primary media, derivative export, thumbnail
  storageClass: StorageClass
  url: String                   // absolute path URL string
  byteSize: Int64
  createdAtMs: Int64
  updatedAtMs: Int64
  isPresent: Bool               // cached existence signal
}

HistoryEvent {
  id: UUID
  historyItemId: UUID
  eventType: String             // capture_copied, capture_saved, recording_stopped...
  createdAtMs: Int64
  payloadJson: String           // bounded metadata payload for diagnostics
}
```

### 7.3 Derived Presentation Model

```text
HistoryTileViewModel {
  id: UUID
  kind: CaptureKind
  sourceBadges: [String]
  title: String
  subtitle: String              // relative time + dimensions (+ duration for recording)
  thumbnailURL: URL?
  isAvailable: Bool
  primaryAction: Open | SaveAs | None
}
```

## 8. Persistence Specification

### 8.1 Metadata Store

Metadata store path:

1. `Application Support/VivyShot/history/history.sqlite`

SQLite mode requirements:

1. WAL journaling.
2. Foreign keys enabled.
3. Schema version tracked by `PRAGMA user_version`.

### 8.2 Tables (Normative)

```sql
CREATE TABLE history_items (
  id TEXT PRIMARY KEY,                          -- UUID
  kind TEXT NOT NULL CHECK (kind IN ('screenshot','recording')),
  source_flags INTEGER NOT NULL,                -- bitset: copied=1, saved=2, temporary=4
  created_at_ms INTEGER NOT NULL,
  last_updated_at_ms INTEGER NOT NULL,
  title TEXT NOT NULL,
  duration_ms INTEGER,                          -- NULL for screenshots
  width_px INTEGER NOT NULL,
  height_px INTEGER NOT NULL,
  preferred_byte_size INTEGER,
  availability TEXT NOT NULL CHECK (availability IN ('available','missing','purged')),
  opened_count INTEGER NOT NULL DEFAULT 0,
  last_opened_at_ms INTEGER,
  dedupe_key TEXT NOT NULL
);

CREATE TABLE artifacts (
  id TEXT PRIMARY KEY,                          -- UUID
  history_item_id TEXT NOT NULL REFERENCES history_items(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('primary','derivative','thumbnail')),
  storage_class TEXT NOT NULL CHECK (storage_class IN ('saved_external','cache_managed')),
  url TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  is_present INTEGER NOT NULL CHECK (is_present IN (0,1))
);

CREATE TABLE history_events (
  id TEXT PRIMARY KEY,                          -- UUID
  history_item_id TEXT NOT NULL REFERENCES history_items(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  payload_json TEXT NOT NULL
);
```

### 8.3 Indexes (Normative)

```sql
CREATE INDEX idx_history_items_created_desc
ON history_items(created_at_ms DESC);

CREATE INDEX idx_history_items_kind_created_desc
ON history_items(kind, created_at_ms DESC);

CREATE INDEX idx_history_items_flags_created_desc
ON history_items(source_flags, created_at_ms DESC);

CREATE INDEX idx_history_items_dedupe_updated
ON history_items(dedupe_key, last_updated_at_ms DESC);

CREATE INDEX idx_artifacts_item_role
ON artifacts(history_item_id, role);

CREATE INDEX idx_artifacts_storage_present
ON artifacts(storage_class, is_present, updated_at_ms ASC);
```

### 8.4 Source Flag Bitset Mapping (Normative)

`history_items.source_flags` is a bitset with fixed assignments:

```text
copied    = 1 (1 << 0)
saved     = 2 (1 << 1)
temporary = 4 (1 << 2)
```

Valid examples:

```text
1 => copied only
3 => copied + saved
4 => temporary only
6 => temporary + saved
7 => copied + saved + temporary
```

Invalid rule:

1. `source_flags = 0` is not allowed.

### 8.5 File System Layout

Within sandbox/container:

1. Cached artifacts:
   - `Library/Caches/VivyShot/history/artifacts/`
2. Generated thumbnails:
   - `Library/Caches/VivyShot/history/thumbs/`
3. Optional import cache for external previews:
   - `Library/Caches/VivyShot/history/proxy/` (future)

File naming convention:

1. Primary cached artifact:
   - `<historyItemId>/primary.<ext>`
2. Thumbnail:
   - `<historyItemId>/thumb@2x.jpg`

## 9. Write Path and Merge Semantics

### 9.1 Write Triggers

Create or update history on:

1. Screenshot copy completion.
2. Screenshot save completion.
3. Recording stop completion.
4. Recording explicit export completion.

### 9.2 Dedupe Strategy

Merge duplicate events into one history item if all conditions are true:

1. Same `kind`.
2. Same `dedupeKey`.
3. Event time delta <= 30 seconds.

`dedupeKey` guidance:

1. Screenshot:
   - hash of image dimensions + first N bytes signature + capture timestamp bucket.
2. Recording:
   - hash of output file inode/path + duration bucket + size bucket.

If merged:

1. Preserve original `createdAtMs`.
2. Update `lastUpdatedAtMs`.
3. Union `sourceFlags`.
4. Update artifact refs if new saved path becomes available.
5. Append `history_events` row for auditability.

### 9.3 Source Flag Rules

1. `copied` set when capture copied to clipboard.
2. `temporary` set for app-generated intermediate media.
3. `saved` set after successful explicit save/export.
4. `saved` never removed automatically.
5. `temporary` may remain true after save if temporary source still exists, but retention logic ignores saved items for destructive purge.

### 9.4 Event Taxonomy (Normative)

Allowed `history_events.event_type` values:

1. `capture_copied`
2. `capture_saved`
3. `recording_stopped`
4. `recording_saved`
5. `history_opened`
6. `history_deleted`
7. `artifact_missing_detected`
8. `artifact_recovered`
9. `retention_purged`

`payload_json` must be:

1. valid JSON object.
2. max 4 KB per event row.
3. free of raw pixel bytes or sensitive clipboard payload data.

## 10. Retention and Eviction Policy

### 10.1 Default TTL by Category

1. Copied-only screenshots:
   - 7 days
2. Temporary recordings without saved flag:
   - 3 days
3. Saved items metadata:
   - 30 days
4. Thumbnails:
   - bounded by parent item lifetime and global cache cap

### 10.2 Global Caps

1. `maxHistoryEntries = 500`
2. `maxCacheBytes = 5 * 1024 * 1024 * 1024`

### 10.3 Eviction Order

When limits exceeded, evict in this order:

1. Purge oldest non-saved cached artifacts (`temporary` or copied-only).
2. Remove orphan thumbnails.
3. If still above `maxHistoryEntries`, remove oldest metadata rows where:
   - no saved artifact refs exist, or
   - item is already `purged`.
4. Saved external files are never deleted by retention.

### 10.4 Cleanup Schedule

Run cleanup:

1. On launch.
2. On app activation (debounced).
3. After each write trigger (background queue).
4. On Settings retention change.

Cleanup requirements:

1. Non-blocking.
2. Re-entrant safe.
3. Crash-safe against half-deleted files.

## 11. Read Path Contracts

### 11.1 Menu Recents Query

Inputs:

1. `limit` (default 5)
2. optional `allowedKinds`

Output:

1. newest available items first
2. include missing items only if no available entries exist

Sort key:

1. `created_at_ms DESC`
2. fallback `last_updated_at_ms DESC`

Minimum fields required for menu projection:

```text
id, kind, source_flags, created_at_ms, title, availability, thumb_url
```

### 11.2 History Window Query

Inputs:

1. `filterKind`: all | screenshots | recordings
2. `filterSource`: all | saved | copied | temporary
3. `sort`: newest | oldest
4. `cursor` + `pageSize`

Output:

1. `items[]`
2. `nextCursor`
3. `totalCount` (optional for initial paint optimization)

Pagination requirements:

1. stable cursor across writes in same session.
2. no duplicate rows across adjacent pages.

Minimum fields required for tile projection:

```text
id, kind, source_flags, created_at_ms, title, width_px, height_px, duration_ms,
availability, preferred_byte_size, primary_artifact_url, thumb_url
```

### 11.3 Reference SQL Shapes (Normative)

Menu recents:

```sql
SELECT
  hi.id,
  hi.kind,
  hi.source_flags,
  hi.created_at_ms,
  hi.title,
  hi.availability,
  at.url AS thumb_url
FROM history_items hi
LEFT JOIN artifacts at
  ON at.history_item_id = hi.id AND at.role = 'thumbnail' AND at.is_present = 1
WHERE hi.availability = 'available'
ORDER BY hi.created_at_ms DESC, hi.last_updated_at_ms DESC
LIMIT :limit;
```

History gallery page:

```sql
SELECT
  hi.id,
  hi.kind,
  hi.source_flags,
  hi.created_at_ms,
  hi.title,
  hi.width_px,
  hi.height_px,
  hi.duration_ms,
  hi.availability,
  hi.preferred_byte_size,
  p.url AS primary_artifact_url,
  t.url AS thumb_url
FROM history_items hi
LEFT JOIN artifacts p
  ON p.history_item_id = hi.id AND p.role = 'primary'
LEFT JOIN artifacts t
  ON t.history_item_id = hi.id AND t.role = 'thumbnail' AND t.is_present = 1
WHERE (:kind = 'all' OR hi.kind = :kind)
  AND (
    :source = 'all'
    OR (:source = 'saved' AND (hi.source_flags & 2) != 0)
    OR (:source = 'copied' AND (hi.source_flags & 1) != 0)
    OR (:source = 'temporary' AND (hi.source_flags & 4) != 0)
  )
  AND hi.created_at_ms < :cursor_created_at_ms
ORDER BY hi.created_at_ms DESC, hi.id DESC
LIMIT :page_size;
```

## 12. State Machine

### 12.1 Item Lifecycle

```text
Captured
  -> Indexed(copied|temporary)
  -> Promoted(saved flag added) [optional]
  -> Missing(external file removed) [optional]
  -> Purged(cache removed by retention) [optional]
  -> Deleted(user removed from history)
```

### 12.2 Availability Transitions

1. `available -> missing`:
   - existence check fails for all openable artifacts.
2. `missing -> available`:
   - path exists again and passes lightweight probe.
3. `available|missing -> purged`:
   - retention removed cache and no saved artifact remains.

## 13. Actions and Behavioral Contracts

### 13.1 `Open`

1. If saved artifact exists, open saved artifact.
2. Else if cached artifact exists, open cached artifact.
3. Else show unavailable error toast and keep selection.

### 13.2 `Reveal in Finder`

1. Enabled only when target path exists.
2. Prefer saved artifact path.
3. Fallback to cached artifact path.

### 13.3 `Copy Again`

1. Screenshots:
   - place image data on pasteboard.
2. Recordings:
   - place file URL on pasteboard.
3. If artifact missing, action disabled.

### 13.4 `Save As…`

1. Available for copied/temp entries and missing-saved fallback when cached artifact exists.
2. Successful save must set `saved` source flag and add saved artifact ref.

### 13.5 `Delete from History`

1. Removes metadata row and events.
2. Deletes app-managed cached artifacts and thumbnails.
3. Never deletes user-saved external originals.

## 14. Settings Specification

Add History section in Settings:

1. `Show Recent Captures in Menu` (bool, default true)
2. `Recent Items In Menu` (enum: 3 | 5 | 10; default 5)
3. `Keep Copied Captures For` (enum: 1d | 3d | 7d | 30d; default 7d)
4. `Keep Temporary Recordings For` (enum: 1d | 3d | 7d; default 3d)
5. `Saved Metadata Retention` (enum: 7d | 30d | 90d; default 30d)
6. `Clear Copied/Temporary History…`
7. `Clear All History Metadata…`

Immediate-effect rules:

1. Retention changes trigger background cleanup.
2. Menu item count change applies without restart.

## 15. Performance and Reliability Targets

1. Write path overhead per capture completion:
   - p95 < 15 ms on hot path
2. History window first paint with 500 items:
   - p95 < 250 ms
3. Thumbnail decode:
   - async incremental loading, no long main-thread stalls
4. Database corruption tolerance:
   - skip bad rows, recover remaining rows, log once per launch
5. Startup impact:
   - cleanup task must not delay initial menu display

## 16. Privacy, Sandbox, and Security

1. History data is local-only.
2. No remote upload or analytics payload dependency for core function.
3. `Clear` actions remove metadata and app-managed caches.
4. Saved user files are never deleted by cleanup or clear operations.
5. Paths shown in UI must be sanitized for display where needed.

### 16.1 App Sandbox Requirements (Mandatory)

This feature must work in App Store sandbox builds.

Required sandbox access model:

1. App Sandbox enabled.
2. User-selected read/write file access used for explicit save/export/import flows.
3. No broad filesystem entitlements for history (no unrestricted home/folder crawling).
4. No dependency on Full Disk Access for core History behavior.

### 16.2 External Saved File Access Strategy

For saved artifacts outside app container:

1. Persist a security-scoped bookmark per saved artifact reference.
2. Resolve bookmark before external file operations (`Open`, `Reveal`, `Copy Again` for file URL).
3. Call scoped access start/stop around each external operation.
4. If bookmark is stale or resolution fails:
   - mark artifact unavailable (`missing`)
   - keep history entry
   - allow `Delete from History`
   - allow `Save As…` when cached artifact exists

### 16.3 TCC and Permission Behavior

1. History browsing/opening existing artifacts must not trigger screen/camera/microphone prompts.
2. Screen recording permission remains capture-flow only.
3. If capture permissions are denied, History still loads and supports existing items.
4. Permission denial messaging must be shown only on capture actions, not passive history viewing.

### 16.4 Container Write Rules

1. Copied/temporary artifacts and thumbnails are written only under app container cache paths.
2. `Clear` actions may only delete:
   - history metadata store
   - app-managed cached artifacts
   - app-managed thumbnails
3. External user-saved files are never deleted by cleanup, clear, or retention jobs.

### 16.5 App Store Compliance Constraints

1. Use public AppKit/Foundation APIs only for file reveal/open behavior.
2. No private APIs, Finder scripting automation, or elevated privilege assumptions.
3. Behavior must degrade gracefully when bookmark access, path existence checks, or scoped resource access fails.

## 17. Migration and Compatibility

1. Schema changes must be forward-migrated with `user_version`.
2. Failed migration fallback:
   - backup DB
   - recreate clean DB
   - preserve on-disk artifacts best-effort
3. Unknown enum values:
   - treated as hidden/unsupported rows, not fatal.

## 18. Test and Release Gates

### 18.1 Unit Tests

1. TTL cutoff calculations by source flags.
2. Dedupe merge decision matrix.
3. Source-flag union and promotion behavior.
4. Eviction ordering under entry and byte caps.
5. State transition validity (`available/missing/purged`).

### 18.2 Integration Tests

1. Copy screenshot -> appears in menu recents and history.
2. Copy then save within merge window -> single merged item.
3. Recording stop -> history item with duration and thumbnail.
4. Clear copied/temp -> saved metadata remains.
5. Missing saved file -> item surfaces unavailable state.

### 18.3 UI Tests

1. Menu recents list rendering and item actions.
2. History filter/sort switching.
3. Keyboard navigation in gallery.
4. Empty state and missing-file state.

Release blocker:

1. Copied screenshots not recoverable after app restart.
2. Retention cleanup blocking capture interaction.
3. Saved originals deleted by any history operation.

## 19. Initial Release Scope (v1)

Must ship:

1. `History…` menu entry.
2. Inline `Recent Captures` section.
3. Gallery window with filters, sorting, and actions.
4. Copied screenshot persistence with TTL.
5. Recording history entries with TTL.
6. Background cleanup with caps and safe eviction.
