# VivyShot Upload And Copy Link Spec

- Status: Active Draft
- Date: 2026-06-17
- Owner: VivyShot
- Related: `SPEC.md`, `docs/post-recording-export-options-spec.md`, `docs/capture-history-spec.md`, `Sources/App/Features/RegionSelection/UI/CaptureAnnotationToolbar.swift`, `Sources/App/Features/RegionSelection/UI/RegionSelectionOverlay+Export.swift`, `Sources/App/Features/Capture/UI/PostRecordingActionPanel.swift`, `Sources/App/Features/Capture/Application/PostRecordingSavePresenter.swift`

## 1. Problem Statement

Users who are familiar with ShareX expect one fast command:

1. capture or finish a recording
2. upload the produced file
3. copy the shareable URL to the clipboard

VivyShot currently has strong local completion actions:

1. screenshots can be copied or saved from the annotation toolbar
2. recordings can be copied as a local video file or saved from the post-recording review window

It does not yet have a first-class link-sharing completion action. Users who want a URL must save locally, upload elsewhere, then copy a link manually.

## 2. Product Goal

Add a native `Upload and Copy Link` workflow for screenshots and videos.

The workflow should feel like a sibling of `Copy` and `Save`, not a separate cloud product. The user finishes the capture, VivyShot uploads the final artifact to the selected destination, then copies the final URL to the clipboard after a successful upload.

The first implementation should support user-owned S3-compatible object storage, with Cloudflare R2 as an important compatibility target.

## 3. Product Principles

1. Local capture stays complete without upload.
2. Upload is always opt-in. No new install uploads automatically.
3. A link copy means the upload already succeeded and the copied URL is usable.
4. Secrets stay local and are stored in macOS Keychain, not in `UserDefaults`, logs, crash reports, or exported diagnostics.
5. Shared object names must be random and non-descriptive by default.
6. Public-link behavior must be explicit because anyone with the link may be able to view the capture.
7. The implementation stays Swift-first and macOS-native.
8. All upload behavior must work inside the macOS App Sandbox.

## 4. Non-Goals

Initial implementation does not include:

1. VivyShot-hosted cloud accounts.
2. Cloud sync of capture history.
3. Collaboration, comments, or team workspaces.
4. A non-macOS uploader daemon.
5. A plugin runtime or scripting system.
6. Background watch-folder uploading.
7. URL shortening as part of v1.
8. Full ShareX feature parity.

Also:

1. `Copy`, `Save`, and local recording export must not become dependent on cloud configuration.
2. Upload failures must not delete the local temporary artifact before the user can recover or retry.
3. SXCU import must not execute arbitrary code or silently install unsafe behavior.

## 5. Locked Product Decisions

### 5.1 Completion Action Name

Use `Upload and Copy Link` in menus and settings.

Short labels may use `Upload` when space is constrained, but tooltips and confirmation text must say `Upload and Copy Link`.

### 5.2 Screenshot Toolbar Placement

Add the upload action after `Save` in the screenshot annotation toolbar.

Current action group:

1. `Undo`
2. `Redo`
3. `Copy`
4. `Save`

Target action group:

1. `Undo`
2. `Redo`
3. `Copy`
4. `Save`
5. `Upload and Copy Link`

Preferred symbol: `square.and.arrow.up`, subject to runtime availability checks. The visual pairing should read naturally beside `square.and.arrow.down` for Save.

### 5.3 Screenshot Main Action

Extend the configurable screenshot main action from:

1. `Copy`
2. `Save`

to:

1. `Copy`
2. `Save`
3. `Upload and Copy Link`

If no upload profile is configured and the user invokes the action, VivyShot opens the upload setup surface instead of failing silently.

### 5.4 Video Review Placement

Add `Upload and Copy Link` to the post-recording review window.

It should be available in the same completion area as `Save` and `Copy Video`, not hidden in general settings. The action uses the currently selected export state and produces the same encoded artifact that would be saved or copied, then uploads that file and copies the resulting URL.

### 5.5 First Provider Family

The first provider family is `S3-compatible storage`.

Supported profile targets:

1. AWS S3
2. Cloudflare R2
3. MinIO
4. Backblaze B2 S3-compatible endpoint
5. Wasabi or other compatible endpoints when they work with standard S3 signing

Cloudflare R2 is not a separate upload engine in v1. It is an S3-compatible profile preset with R2-specific defaults and validation help.

### 5.6 SXCU Priority

SXCU compatibility is important, but it is not the foundation for v1.

Implementation order:

1. Build the safe native S3-compatible uploader first.
2. Add manual custom HTTP uploader profiles second if needed.
3. Add SXCU import as an advanced compatibility layer after the internal upload model is stable.

Reason: SXCU is powerful and useful, but importing arbitrary request definitions before VivyShot has strong safety boundaries would make the first version harder to trust.

## 6. Current Code Reality

### 6.1 Screenshot Surface

`Sources/App/Features/RegionSelection/UI/CaptureAnnotationToolbar.swift`

Current behavior:

1. The toolbar already has icon actions for `Copy` and `Save`.
2. The configurable main action uses `ScreenshotMainAction`.
3. Toolbar actions flow through `CaptureAnnotationToolbarAction`.

`Sources/App/Features/RegionSelection/UI/RegionSelectionOverlay+Export.swift`

Current behavior:

1. `performCopy()` renders the final selected image, writes PNG/image data to the pasteboard, optionally auto-saves, closes the editor, records statistics, and shows a toast.
2. `performSave()` renders the final selected image, saves automatically or presents `NSSavePanel`, closes the editor, and records statistics after success.

The upload path should reuse the same final image export helpers so the uploaded image matches what Copy and Save would produce.

### 6.2 Video Surface

`Sources/App/Features/Capture/UI/PostRecordingActionPanel.swift`

Current behavior:

1. The review window has toolbar actions for export and save.
2. The Save menu includes `Copy Video`, MP4, MOV, and GIF actions.
3. Keyboard shortcuts already route completion actions through `PostRecordingReviewShortcut`.

`Sources/App/Features/Capture/Application/PostRecordingSavePresenter.swift`

Current behavior:

1. Save/copy actions produce encoded files through the existing export pipeline.
2. Copy Video copies a local file to the pasteboard, not a URL.

The upload path should reuse the same rendered/exported artifact pipeline before uploading.

### 6.3 Sandbox Reality

`Config/VivyShot.entitlements`

Current entitlements:

1. `com.apple.security.app-sandbox`
2. `com.apple.security.device.audio-input`
3. `com.apple.security.device.camera`
4. `com.apple.security.files.user-selected.read-write`

Current upload implication:

1. The app is sandboxed.
2. The app can read and write user-selected files.
3. The app can use its container and temporary directories.
4. The app must not assume arbitrary filesystem access.
5. The current entitlement file does not include outbound network access.

Before shipping upload support, the app must add the outbound network client entitlement:

```text
com.apple.security.network.client
```

No upload feature is complete until the App Store sandbox entitlement set matches the shipped behavior.

## 7. UX Specification

### 7.1 First-Run Upload Setup

When the user clicks `Upload and Copy Link` without a configured profile:

1. Show a compact setup sheet.
2. Explain that uploads require a user-owned destination.
3. Offer `S3-Compatible Storage` as the primary option.
4. Include an explicit public/private link choice.
5. Do not upload the current capture until setup validates successfully and the user confirms.

No marketing copy. The sheet is a tool setup surface.

### 7.2 Upload Profile Fields

S3-compatible profile fields:

1. Profile name
2. Provider preset: `Custom S3`, `Cloudflare R2`, `AWS S3`, `MinIO`, `Backblaze B2`
3. Endpoint URL
4. Region
5. Bucket
6. Object prefix template
7. Public base URL or custom domain
8. Access key ID
9. Secret access key
10. Optional session token
11. Link mode:
    - public object URL
    - private presigned URL
12. Presigned URL expiration when private mode is selected

Secrets are written to Keychain. Non-secret profile metadata can be persisted in app settings or an upload profiles store.

### 7.3 Object Key Defaults

Default object key:

```text
{yyyy}/{MM}/{random-20}.{ext}
```

Rules:

1. Random portion must be generated with a cryptographically secure random source.
2. Do not include window title, app name, file path, user name, machine name, or capture text.
3. Keep file extension accurate.
4. Use `png` for screenshot default uploads.
5. Use the selected/exported container extension for videos.

### 7.4 Upload Progress

For screenshots:

1. Close the editor only after the upload has started and VivyShot has retained enough local data to retry.
2. Show a small progress state near the toolbar or as a native progress sheet.
3. On success, copy URL and show `Link Copied`.
4. On failure, keep enough state to retry or save locally.

For videos:

1. Show progress in the post-recording review window.
2. Separate export progress from upload progress.
3. Keep the review window open until upload succeeds or the user cancels.
4. On success, copy URL and close only if the user chose a one-shot completion action.

### 7.5 Clipboard Semantics

The clipboard must contain only the final URL after upload success.

Do not copy:

1. presigned PUT URLs
2. internal S3 API URLs when public custom base URL is configured
3. local file paths
4. JSON responses
5. error details

If private presigned link mode is used, the copied URL is a bearer link and the UI must show its expiration.

### 7.6 History

Each successful upload should create or update a history entry with:

1. capture ID
2. local artifact type
3. provider profile ID
4. bucket
5. object key
6. final copied URL
7. link mode
8. expiration date when relevant
9. uploaded byte count
10. upload completed timestamp
11. remote delete availability

History should allow:

1. copy URL again
2. open URL
3. reveal local saved file when available
4. delete remote object when credentials allow it

## 8. Security Model

### 8.0 App Sandbox Requirements

Upload must be designed as a sandbox-compatible workflow.

Requirements:

1. Use VivyShot-owned in-memory data, app container files, or temporary-directory exports as upload sources.
2. Do not require broad filesystem access.
3. Use `NSSavePanel` or user-selected read/write access only for explicit local save/export actions.
4. If a future upload flow reads a previously saved external file without a fresh panel selection, persist and resolve a security-scoped bookmark.
5. Keep temporary upload artifacts inside the app container or `FileManager.default.temporaryDirectory`.
6. Clean up temporary artifacts only after upload success, explicit discard, or safe retry expiry.
7. Add `com.apple.security.network.client` before network upload is enabled in production builds.
8. Keep entitlement changes minimal; do not add server/listener, downloads-folder, documents-folder, or broader file entitlements unless the exact feature requires them.

Keychain storage must use app-owned Keychain items. If a future build introduces shared Keychain access groups, that must be specified separately in entitlements and reviewed as part of the security model.

### 8.1 Public Link Mode

Public mode uploads an object and copies a stable public URL.

Requirements:

1. User must explicitly select public mode.
2. Setup must say that anyone with the link can view the object.
3. Profile validation should warn if the URL cannot be fetched after upload.
4. Object keys must be unguessable by default.
5. Deletion should be available from history when credentials have permission.

### 8.2 Private Presigned Link Mode

Private mode uploads an object that is not publicly readable and copies a time-limited GET URL.

Requirements:

1. Default expiration should be short enough to communicate temporary sharing, such as 24 hours.
2. User can choose a longer expiration only from explicit settings.
3. UI must label the copied link as expiring.
4. The URL must be treated as sensitive in logs and diagnostics.

Important compatibility note: Cloudflare R2 presigned URLs work through the R2 S3 API endpoint, not through custom public domains. A custom-domain private link for R2 requires a proxy/Worker/HMAC-style setup and is out of scope for the first native S3-compatible uploader.

### 8.3 Credentials

Credential requirements:

1. Store access key ID, secret access key, and session token in Keychain.
2. Never store secrets in `UserDefaults`, settings JSON, SQLite history, or diagnostics.
3. Redact secrets and signed query strings from logs.
4. Encourage least-privilege credentials during setup.
5. Profile validation should work with credentials scoped to one bucket and prefix.
6. Do not ask for or recommend root account keys.

Recommended minimum permissions for S3-compatible public upload:

1. `PutObject` for the configured prefix
2. `GetObject` only if validation requires reading through the S3 API
3. `DeleteObject` if remote delete is enabled
4. `AbortMultipartUpload`, `CreateMultipartUpload`, `UploadPart`, `CompleteMultipartUpload`, and list-parts equivalents when video multipart upload is enabled

### 8.4 Diagnostics

Diagnostics may include:

1. provider type
2. endpoint host
3. bucket name only if user consents
4. HTTP status code
5. S3 error code
6. upload phase

Diagnostics must not include:

1. secret access key
2. session token
3. authorization header
4. full presigned URL
5. signed query parameters
6. local capture contents

## 9. Upload Architecture

### 9.1 Core Types

Introduce a shared upload feature area:

```text
Sources/App/Features/Upload/
  Domain/
  Application/
  UI/
```

Required domain concepts:

1. `UploadProfile`
2. `UploadDestination`
3. `UploadLinkMode`
4. `UploadObjectKeyTemplate`
5. `UploadRequest`
6. `UploadResult`
7. `UploadError`
8. `UploadHistoryRecord`

The capture and recording features should call an upload service; they should not own S3 signing or profile storage directly.

### 9.2 Proposed File Structure

Create the upload feature as its own ownership boundary:

```text
Sources/App/Features/Upload/
  Domain/
    UploadDomain.swift
    UploadProfile.swift
    UploadRequest.swift
    UploadResult.swift
    UploadError.swift
    UploadObjectKeyTemplate.swift
    UploadHistoryRecord.swift
    SXCUUploaderDefinition.swift
  Application/
    UploadCoordinator.swift
    UploadProfileStore.swift
    UploadProfilePersistence.swift
    UploadCredentialStore.swift
    UploadHistoryStore.swift
    UploadHistorySQLiteStore.swift
    UploadDiagnosticsRedactor.swift
    UploadPasteboardWriter.swift
    S3UploadClient.swift
    S3RequestSigner.swift
    S3PresignedURLBuilder.swift
    S3MultipartUploadPlanner.swift
    SXCUImportService.swift
  UI/
    UploadSetupSheet.swift
    UploadProfileListView.swift
    UploadProfileEditorView.swift
    UploadProgressView.swift
    SXCUImportReviewView.swift
```

Touch existing screenshot files:

```text
Sources/App/Features/Capture/Domain/CaptureSelectionDomain.swift
Sources/App/Features/Capture/UI/CaptureOptionPresentation.swift
Sources/App/Features/RegionSelection/UI/CaptureAnnotationToolbar.swift
Sources/App/Features/RegionSelection/UI/CaptureToolbarModels.swift
Sources/App/Features/RegionSelection/UI/RegionSelectionOverlay+EditingToolbar.swift
Sources/App/Features/RegionSelection/UI/RegionSelectionOverlay+Export.swift
Sources/App/Features/RegionSelection/UI/RegionSelectionOverlay+Shortcuts.swift
Sources/App/Features/Settings/UI/SettingsAppearanceTab.swift
```

Touch existing video files:

```text
Sources/App/Features/Capture/Domain/PostRecordingReviewDomain.swift
Sources/App/Features/Capture/UI/PostRecordingActionPanel.swift
Sources/App/Features/Capture/Application/PostRecordingSavePresenter.swift
```

Touch existing app/settings integration files:

```text
Sources/App/App/AppEnvironment.swift
Sources/App/Features/Settings/Application/AppSettings.swift
Sources/App/Features/Settings/Application/AppSettingsDefinitions.swift
Sources/App/Features/Settings/Application/AppSettingsPersistence.swift
Sources/App/Features/Settings/UI/SettingsWindowController.swift
Config/VivyShot.entitlements
project.yml
```

Add tests:

```text
Tests/UploadObjectKeyTemplateTests.swift
Tests/UploadDiagnosticsRedactorTests.swift
Tests/S3RequestSignerTests.swift
Tests/S3PresignedURLBuilderTests.swift
Tests/S3MultipartUploadPlannerTests.swift
Tests/SXCUImportServiceTests.swift
```

The exact file split can be tightened during implementation, but the upload feature should remain separate from capture and recording. Existing capture surfaces may initiate upload actions; they should not own profile persistence, credential storage, S3 signing, SXCU parsing, or upload history.

### 9.3 Domain API Draft

The domain layer should be plain Swift value types with no AppKit, SwiftUI, Keychain, SQLite, or networking dependencies.

```swift
enum UploadArtifactKind: String, Codable, Sendable {
  case screenshot
  case video
}

enum UploadProviderKind: String, Codable, CaseIterable, Sendable {
  case s3Compatible
  case customHTTP
}

enum UploadProviderPreset: String, Codable, CaseIterable, Sendable {
  case customS3
  case cloudflareR2
  case awsS3
  case minio
  case backblazeB2
}

enum UploadLinkMode: String, Codable, CaseIterable, Sendable {
  case publicURL
  case privatePresignedURL
}

struct UploadProfile: Identifiable, Codable, Equatable, Sendable {
  var id: UUID
  var name: String
  var providerKind: UploadProviderKind
  var s3: S3UploadProfile?
  var customHTTP: CustomHTTPUploadProfile?
  var defaultLinkMode: UploadLinkMode
  var objectKeyTemplate: UploadObjectKeyTemplate
  var isDefaultForScreenshots: Bool
  var isDefaultForVideos: Bool
  var createdAt: Date
  var updatedAt: Date
}

struct S3UploadProfile: Codable, Equatable, Sendable {
  var preset: UploadProviderPreset
  var endpoint: URL
  var region: String
  var bucket: String
  var publicBaseURL: URL?
  var pathStyle: Bool
  var allowsInsecureLocalHTTP: Bool
  var credentialID: UUID
}

struct CustomHTTPUploadProfile: Codable, Equatable, Sendable {
  var requestURL: URL
  var method: String
  var bodyKind: CustomHTTPUploadBodyKind
  var headers: [CustomHTTPHeader]
  var fileFormName: String?
  var responseURLStrategy: CustomHTTPResponseURLStrategy
  var credentialID: UUID?
}

enum CustomHTTPUploadBodyKind: String, Codable, Equatable, Sendable {
  case multipartFormData
  case binary
  case json
}

struct CustomHTTPHeader: Codable, Equatable, Sendable {
  var name: String
  var value: String
  var isSecret: Bool
}

enum CustomHTTPResponseURLStrategy: Codable, Equatable, Sendable {
  case responseURL
  case header(name: String)
  case jsonPath(String)
}

struct UploadObjectKeyTemplate: Codable, Equatable, Sendable {
  var rawValue: String

  func render(context: UploadObjectKeyContext) throws -> String
}

struct UploadObjectKeyContext: Equatable, Sendable {
  var artifactKind: UploadArtifactKind
  var fileExtension: String
  var now: Date
  var randomToken: String
}

struct UploadRequest: Identifiable, Equatable, Sendable {
  var id: UUID
  var artifactKind: UploadArtifactKind
  var profileID: UUID
  var source: UploadSource
  var fileName: String
  var objectKey: String
  var contentType: String
  var byteCount: Int64
  var linkMode: UploadLinkMode
}

enum UploadSource: Equatable, Sendable {
  case data(Data)
  case file(URL)
}

struct UploadResult: Equatable, Sendable {
  var requestID: UUID
  var profileID: UUID
  var artifactKind: UploadArtifactKind
  var bucket: String?
  var objectKey: String
  var finalURL: URL
  var linkMode: UploadLinkMode
  var expiresAt: Date?
  var byteCount: Int64
  var completedAt: Date
  var remoteDelete: UploadRemoteDelete?
}

struct UploadRemoteDelete: Codable, Equatable, Sendable {
  var profileID: UUID
  var bucket: String?
  var objectKey: String
}
```

Error types should be user-presentable without leaking secrets:

```swift
enum UploadError: LocalizedError, Equatable {
  case noDefaultProfile(UploadArtifactKind)
  case profileNotFound(UUID)
  case missingCredentials
  case invalidEndpoint
  case invalidObjectKey
  case unsupportedSXCUFeature(String)
  case rejectedUnsafeSXCU(String)
  case credentialsRejected
  case bucketNotFound
  case prefixDenied
  case networkUnavailable
  case publicURLNotReadable
  case uploadCanceled
  case multipartAbortFailed
  case clipboardWriteFailed(URL)
  case providerError(statusCode: Int, code: String?, message: String?)
}
```

### 9.4 Application API Draft

The application layer owns orchestration, storage, networking, Keychain, SQLite, and pasteboard integration.

```swift
actor UploadCoordinator {
  func uploadAndCopyLink(_ request: UploadRequest) async throws -> UploadResult
  func upload(_ request: UploadRequest) async throws -> UploadResult
  func cancelUpload(id: UUID) async
  func deleteRemoteObject(_ remoteDelete: UploadRemoteDelete) async throws
}

actor UploadProfileStore {
  func profiles() async throws -> [UploadProfile]
  func defaultProfile(for artifactKind: UploadArtifactKind) async throws -> UploadProfile?
  func save(_ profile: UploadProfile) async throws
  func deleteProfile(id: UUID) async throws
}

protocol UploadCredentialStore: Sendable {
  func save(_ credentials: UploadCredentials, id: UUID) async throws
  func credentials(id: UUID) async throws -> UploadCredentials
  func deleteCredentials(id: UUID) async throws
}

struct UploadCredentials: Equatable, Sendable {
  var accessKeyID: String
  var secretAccessKey: String
  var sessionToken: String?
}

protocol UploadClient: Sendable {
  func upload(_ request: UploadRequest, profile: UploadProfile) async throws -> UploadResult
  func delete(_ remoteDelete: UploadRemoteDelete, profile: UploadProfile) async throws
}
```

S3-specific APIs:

```swift
struct S3SignedRequest: Equatable, Sendable {
  var method: String
  var url: URL
  var headers: [String: String]
  var body: S3RequestBody
}

enum S3RequestBody: Equatable, Sendable {
  case empty
  case data(Data)
  case file(URL)
}

struct S3RequestSigner {
  func signedPUT(
    profile: S3UploadProfile,
    credentials: UploadCredentials,
    objectKey: String,
    contentType: String,
    byteCount: Int64
  ) throws -> S3SignedRequest
}

struct S3PresignedURLBuilder {
  func presignedGETURL(
    profile: S3UploadProfile,
    credentials: UploadCredentials,
    objectKey: String,
    expiresIn: TimeInterval
  ) throws -> URL
}

struct S3MultipartUploadPlanner {
  func plan(fileSize: Int64) -> S3MultipartUploadPlan
}

struct S3MultipartUploadPlan: Equatable, Sendable {
  var partSize: Int64
  var partCount: Int
  var threshold: Int64
}
```

SXCU import APIs:

```swift
struct SXCUImportService {
  func parse(data: Data) throws -> SXCUUploaderDefinition
  func validate(_ definition: SXCUUploaderDefinition) throws -> SXCUImportSummary
  func makeUploadProfile(from summary: SXCUImportSummary) throws -> UploadProfile
}

struct SXCUImportSummary: Equatable, Sendable {
  var name: String
  var supportedDestinations: Set<UploadArtifactKind>
  var requestURL: URL
  var method: String
  var bodyKind: SXCURequestBodyKind
  var responseURLStrategy: SXCUResponseURLStrategy
  var warnings: [String]
  var requiredSecretFields: [String]
}

struct SXCUUploaderDefinition: Equatable, Sendable {
  var version: String?
  var name: String?
  var destinationType: String?
  var requestMethod: String
  var requestURL: URL
  var headers: [String: String]
  var body: SXCURequestBodyKind
  var arguments: [String: String]
  var fileFormName: String?
  var urlTemplate: String?
  var thumbnailURLTemplate: String?
  var deletionURLTemplate: String?
  var errorMessageTemplate: String?
}

enum SXCURequestBodyKind: String, Equatable, Sendable {
  case none
  case multipartFormData
  case formURLEncoded
  case json
  case xml
  case binary
}

enum SXCUResponseURLStrategy: Equatable, Sendable {
  case responseURL
  case header(name: String)
  case jsonPath(String)
}
```

### 9.5 Persistence Draft

Use separate storage responsibilities:

1. Profile metadata: app settings JSON or a small upload-owned JSON file under `Application Support/VivyShot/upload/`.
2. Secrets: Keychain items keyed by `UploadProfile.s3.credentialID`.
3. Upload history: SQLite under `Application Support/VivyShot/history/history.sqlite` or an upload-owned SQLite file under `Application Support/VivyShot/upload/upload.sqlite`.
4. Temporary artifacts: app container temporary directory or `FileManager.default.temporaryDirectory`.

Do not store secrets in profile metadata or history records.

Suggested logical tables if upload history uses SQLite:

```sql
CREATE TABLE upload_history (
  id TEXT PRIMARY KEY NOT NULL,
  capture_id TEXT,
  artifact_kind TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  provider_kind TEXT NOT NULL,
  bucket TEXT,
  object_key TEXT NOT NULL,
  final_url TEXT NOT NULL,
  link_mode TEXT NOT NULL,
  expires_at_ms INTEGER,
  byte_count INTEGER NOT NULL,
  completed_at_ms INTEGER NOT NULL,
  remote_delete_available INTEGER NOT NULL DEFAULT 0
);
```

Suggested Keychain identity:

```text
service: com.vivyshot.upload
account: upload-profile:<profileID>:<credentialID>
```

### 9.6 UI API Draft

The UI layer should be thin SwiftUI/AppKit presentation over domain/application APIs.

```swift
@MainActor
final class UploadSetupViewModel: ObservableObject {
  @Published var profiles: [UploadProfile]
  @Published var selectedProfileID: UUID?
  @Published var validationState: UploadValidationState

  func load() async
  func validateDraft() async
  func saveDraft() async throws
  func importSXCU(url: URL) async throws -> SXCUImportSummary
}

enum UploadProgressPhase: Equatable {
  case preparing
  case exporting
  case uploading(bytesSent: Int64, totalBytes: Int64?)
  case verifying
  case copyingLink
  case complete(URL)
  case failed(String)
}
```

Screenshot integration should add:

1. `CaptureAnnotationToolbarAction.uploadAndCopyLink`
2. `ScreenshotMainAction.uploadAndCopyLink`
3. `RegionSelectionView.performUploadAndCopyLink()`

Video integration should add:

1. `PostRecordingReviewShortcut.uploadAndCopyLink`
2. `PostRecordingAction.uploadAndCopyLink(...)`
3. `PostRecordingSaveMenuAction.uploadAndCopyLink`

### 9.7 Screenshot Upload Flow

Flow:

1. User clicks `Upload and Copy Link`.
2. Finish inline text editing.
3. Resolve capture target.
4. Render final image using the same export path as Copy/Save.
5. Encode image.
6. Create upload request with MIME type and extension.
7. Upload.
8. Resolve final URL.
9. Copy URL to pasteboard.
10. Record statistics/history completion.
11. Show success toast.

If upload fails, the editor should remain recoverable or offer immediate local save.

### 9.8 Video Upload Flow

Flow:

1. User clicks `Upload and Copy Link`.
2. Resolve review export state.
3. Export or reuse the selected encoded artifact.
4. Upload using single PUT for small files.
5. Use multipart upload for large files.
6. Resolve final URL.
7. Copy URL to pasteboard.
8. Record upload history.
9. Close review window only after success.

For videos around 100 MB or larger, multipart upload should be preferred for reliability and resume/cancel behavior.

### 9.9 Cancellation

Users must be able to cancel an in-progress upload.

Cancellation requirements:

1. Cancel pending network requests.
2. Abort incomplete multipart uploads when the provider supports it.
3. Leave the local capture/export artifact available until cleanup is safe.
4. Do not copy any URL after cancellation.

## 10. S3-Compatible Behavior

### 10.1 Required Operations

MVP operations:

1. signed single-part `PUT`
2. optional object verification
3. public URL construction
4. presigned GET URL construction
5. delete object

Video-ready operations:

1. create multipart upload
2. upload parts
3. complete multipart upload
4. abort multipart upload

### 10.2 R2 Defaults

Cloudflare R2 preset defaults:

1. endpoint host pattern: `<account-id>.r2.cloudflarestorage.com`
2. region: `auto`
3. public URL: user-provided custom domain or R2 public bucket URL
4. `public-read` ACL disabled

R2 profile validation must not assume AWS ACL behavior.

### 10.3 MinIO Defaults

MinIO preset defaults:

1. custom endpoint required
2. path-style option visible
3. HTTP allowed only for local/private network endpoints after an explicit warning

Default internet endpoints must require HTTPS.

## 11. SXCU Compatibility

### 11.1 What SXCU Means For VivyShot

ShareX custom uploader files are JSON request definitions. They can describe upload request method, URL, headers, body type, file form name, and response parsing rules for the final URL.

VivyShot should eventually import a safe subset so users can reuse existing ShareX-compatible hosting services.

For VivyShot, `.sxcu` is treated as user-provided configuration data, not as an implementation source. Importing an `.sxcu` file means parsing the JSON, validating it, and translating the accepted fields into VivyShot's own `UploadProfile` model.

VivyShot must not copy or port ShareX source code, tests, bundled uploader presets, UI implementation, or internal uploader architecture. Compatibility should be implemented from public format behavior and independently written Swift code.

User-facing wording may state factual compatibility, such as `Import ShareX custom uploader (.sxcu)`, but must not imply endorsement, official integration, or that VivyShot is powered by ShareX.

### 11.2 Safe Import Subset

Initial SXCU import may support:

1. destination types: image uploader and file uploader
2. methods: `POST`, `PUT`
3. body types: multipart form data, binary, JSON when no secret interpolation is required
4. static HTTPS request URLs
5. static headers
6. response URL extraction from JSON path, header, or redirect URL
7. user-visible fields for secrets

Initial SXCU import must reject or require explicit review for:

1. non-HTTPS internet URLs
2. arbitrary regex response parsing
3. dynamic prompt/interpolation features
4. URL shorteners
5. URL sharing services
6. hidden authorization headers
7. deletion URLs that include embedded secrets
8. imported settings that automatically change default upload behavior without confirmation

### 11.3 Import UX

SXCU import flow:

1. User selects `.sxcu`.
2. VivyShot parses and summarizes what it will do.
3. Secrets are shown as fields to review or re-enter.
4. User chooses whether it applies to screenshots, videos, or both.
5. User confirms before the profile becomes active.

No double-click auto-install behavior in v1.

### 11.4 Redistribution Boundary

VivyShot may import `.sxcu` files selected by the user.

VivyShot should not bundle third-party `.sxcu` files, copied ShareX presets, or community uploader definitions unless their license clearly allows redistribution and the bundled config has been reviewed for secrets, unsafe endpoints, and misleading behavior.

If example configs are needed for tests or documentation, create minimal original fixtures that exercise the supported schema without copying real service configs from ShareX or community repositories.

## 12. Monetization Boundary

Local capture, Copy, Save, and standard recording export remain core app features.

Upload integrations are a candidate Pro feature because they are an advanced workflow, but the first spec does not lock pricing. If gated later:

1. Never gate access to locally saved files.
2. Never hold a capture hostage after the user creates it.
3. Make the paywall appear before upload begins.
4. Allow users to remove stored credentials and profiles without Pro.

## 13. Settings

Add an `Upload` settings section or tab only when the feature is implemented.

Settings should include:

1. profile list
2. add/edit/delete profile
3. default profile
4. default link mode
5. screenshot upload format
6. video upload format/preset
7. object key template
8. copy link automatically after upload
9. remote delete confirmation behavior
10. SXCU import

Do not overload the existing Screenshot or Video tabs with all upload configuration. Those tabs can reference the selected upload profile, but profile management should live in one upload-owned surface.

## 14. Error Handling

Common user-facing errors:

1. No upload profile configured
2. Credentials rejected
3. Bucket not found
4. Prefix denied
5. Public URL did not become readable
6. File too large for single-part upload
7. Multipart upload failed
8. Network offline
9. Upload canceled
10. Clipboard write failed after successful upload

If upload succeeds but clipboard write fails, show the URL in a selectable field and store it in history.

## 15. Validation And Tests

Unit tests:

1. object key generation never includes unsafe metadata
2. key templates normalize extensions
3. credential redaction removes authorization headers and signed query strings
4. public URL construction handles trailing slashes
5. R2 endpoint and region defaults are stable
6. SXCU parser accepts safe fixtures and rejects unsafe fixtures

Integration tests where feasible:

1. S3 signing canonical request construction
2. single-part upload against a local S3-compatible test server
3. multipart upload planning
4. cancellation aborts multipart state

Manual QA:

1. screenshot upload copies a public URL
2. screenshot upload copies a private expiring URL
3. video upload copies a public URL
4. video upload progress separates export and upload phases
5. failed upload allows retry or local save
6. deleting a history item can delete the remote object
7. diagnostics contain no secrets
8. sandboxed App Store-style build can upload successfully with only required entitlements
9. upload source files remain inside the app container or temporary directory unless explicitly user-selected

## 16. Implementation Phases

### Phase 1: Product Skeleton

1. Add upload profile model.
2. Add Keychain-backed secret storage.
3. Add S3-compatible single-part uploader.
4. Add settings/setup UI for one profile.
5. Add screenshot `Upload and Copy Link` action.
6. Add and validate the outbound network client entitlement.

### Phase 2: Video Support

1. Add post-recording `Upload and Copy Link`.
2. Reuse existing video export pipeline.
3. Add upload progress and cancellation.
4. Add multipart upload for larger videos.

### Phase 3: History And Delete

1. Persist upload history metadata.
2. Add copy/open/delete remote actions.
3. Add diagnostics redaction coverage.

### Phase 4: SXCU Compatibility

1. Add safe SXCU parser.
2. Add import review UI.
3. Map safe configs to VivyShot upload profiles.
4. Add fixtures for ShareX-style image and file uploaders.

## 17. Acceptance Criteria

1. A configured user can capture a screenshot, click the upload icon after Save, and paste a usable URL.
2. A configured user can finish a recording, choose `Upload and Copy Link`, and paste a usable URL.
3. No upload occurs unless the user explicitly configures and invokes upload behavior.
4. Credentials are stored in Keychain and do not appear in settings, history, logs, or diagnostics.
5. Public/private link mode is visible before first upload.
6. Object keys are random and do not leak capture context.
7. Cloudflare R2 works through the S3-compatible profile path.
8. Upload failure leaves the user with retry or local save options.
9. Existing Copy, Save, Copy Video, Save MP4, Save MOV, and Save GIF behavior remains intact.
10. The feature works in the sandboxed app with no broad file access entitlement.

## 18. External Compatibility References

Reference behavior to preserve:

1. ShareX exposes `Copy URL to clipboard` as an after-upload task.
2. ShareX supports custom uploader JSON files with response URL extraction.
3. ShareX configures Cloudflare R2 through its Amazon S3 destination using the R2 endpoint and `auto` region.
4. S3 presigned URLs are bearer links and should be treated as sensitive.
5. Cloudflare R2 presigned URLs do not work through custom public domains.

Useful documentation:

1. `https://getsharex.com/docs/custom-uploader`
2. `https://getsharex.com/docs/amazon-s3`
3. `https://getsharex.com/docs/cloudflare-r2`
4. `https://developers.cloudflare.com/r2/api/s3/presigned-urls/`
5. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html`
6. `https://docs.aws.amazon.com/IAM/latest/UserGuide/securing_access-keys.html`
