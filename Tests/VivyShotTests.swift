import AppKit
import AVFoundation
import Combine
import SQLite3
import XCTest
@testable import VivyShot

final class AppTests: XCTestCase {
  @MainActor
  private final class SettingsChangeRecorder {
    var shortcutCount = 0
    var regionCount = 0
    var videoCount = 0
    var languageCount = 0

    private var cancellables: [AnyCancellable] = []

    init(settings: AppSettings) {
      cancellables = [
        settings.captureShortcutChanges.sink { [weak self] in
          MainActor.assumeIsolated {
            self?.shortcutCount += 1
          }
        },
        settings.regionSelectionSettingsChanges.sink { [weak self] in
          MainActor.assumeIsolated {
            self?.regionCount += 1
          }
        },
        settings.videoSettingsChanges.sink { [weak self] in
          MainActor.assumeIsolated {
            self?.videoCount += 1
          }
        },
        settings.appLanguageChanges.sink { [weak self] in
          MainActor.assumeIsolated {
            self?.languageCount += 1
          }
        }
      ]
    }
  }

  @MainActor
  private final class RecordingStateSpy: RecordingStateObserving {
    var states: [Bool] = []

    func recordingStateDidChange(isRecording: Bool) {
      states.append(isRecording)
    }
  }

  @MainActor
  private final class RecordingControllerSpy: RegionSelectionRecordingControlling {
    var stopCallCount = 0
    var liveControlState = RecordingLiveControlState(
      recordSystemAudio: false,
      recordMicrophone: false,
      showWebcam: false,
      highlightMouseClicks: false,
      highlightKeystrokes: false
    )

    func startRecording(
      selectionRectInScreen: CGRect,
      overlayState: RecordingOverlayState?,
      showFloatingHUD: Bool,
      flowHandler: any RecordingFlowHandling
    ) {}

    func stopRecordingFromInlineToolbar() {
      stopCallCount += 1
    }

    func setLiveRecordingTool(_ tool: RecordingTool, enabled: Bool) async -> RecordingLiveControlState {
      liveControlState
    }

    func setMicrophoneDeviceIDForNextRecording(_ deviceID: String) {}

    func setWebcamDeviceIDForNextRecording(_ deviceID: String) {}
  }

  @MainActor
  private final class ClosingRegionSelectionDelegate: RegionSelectionViewDelegate {
    func regionSelectionView(
      _ view: RegionSelectionView,
      didFinishSelection localRect: CGRect?,
      captureType: CaptureContentType,
      captureMode: CaptureMode
    ) {}

    func regionSelectionViewDidRequestCancel(_ view: RegionSelectionView) {}

    func regionSelectionViewDidRequestImmediateCancel(_ view: RegionSelectionView) {}

    func regionSelectionViewWillStartRecordingWebcamCapture(_ view: RegionSelectionView) async {}

    func regionSelectionViewDidFinishRecordingFlow(_ view: RegionSelectionView) {}

    func regionSelectionView(_ view: RegionSelectionView, didFailRecordingWithMessage message: String) {}

    func regionSelectionView(_ view: RegionSelectionView, didFinishEditingAnimatedClose animatedClose: Bool) {
      view.prepareForClose()
    }
  }

  private final class NoopCrashReporter: CrashReporting {
    func install() {}
    func markCleanShutdown() {}
    @MainActor func presentRecoveredCrashNoticeIfNeeded() {}
  }

  @MainActor
  private final class NoopToastPresenter: ToastPresenting {
    func show(_ message: String, duration: TimeInterval) {}
  }

  @MainActor
  private final class AnnotationCanvasDelegateSpy: AnnotationCanvasViewDelegate {
    var commits: [AnnotationCanvasCommit] = []

    func annotationCanvasViewDidChangeViewport(_ canvasView: AnnotationCanvasView) {}

    func annotationCanvasView(_ canvasView: AnnotationCanvasView, didCommit commit: AnnotationCanvasCommit) {
      commits.append(commit)
    }

    func annotationCanvasView(_ canvasView: AnnotationCanvasView, hitTestAnnotationAt point: CGPoint) -> AnnotationInfo? {
      nil
    }

    func annotationCanvasView(_ canvasView: AnnotationCanvasView, moveAnnotationAt index: Int, by delta: CGPoint) -> CGImage? {
      nil
    }

    func annotationCanvasView(_ canvasView: AnnotationCanvasView, resizeAnnotationAt index: Int, to imageRect: CGRect) -> CGImage? {
      nil
    }

    func annotationCanvasView(_ canvasView: AnnotationCanvasView, deleteAnnotationAt index: Int) -> CGImage? {
      nil
    }

    func annotationCanvasViewWillMoveCaptureArea(_ canvasView: AnnotationCanvasView) {}

    func annotationCanvasView(_ canvasView: AnnotationCanvasView, moveCaptureAreaBy delta: CGPoint) -> Bool {
      false
    }

    func annotationCanvasViewDidFinishMovingCaptureArea(_ canvasView: AnnotationCanvasView) {}
  }

  private final class StubLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginServiceStatus
    var registerError: Error?
    var unregisterError: Error?
    var registerCallCount = 0
    var unregisterCallCount = 0
    var statusAfterRegister: LaunchAtLoginServiceStatus?
    var statusAfterUnregister: LaunchAtLoginServiceStatus?

    init(status: LaunchAtLoginServiceStatus) {
      self.status = status
    }

    func register() throws {
      registerCallCount += 1
      if let registerError {
        throw registerError
      }
      if let statusAfterRegister {
        status = statusAfterRegister
      }
    }

    func unregister() throws {
      unregisterCallCount += 1
      if let unregisterError {
        throw unregisterError
      }
      if let statusAfterUnregister {
        status = statusAfterUnregister
      }
    }
  }

  func testStoreEntitlementResolution() {
    XCTAssertEqual(StoreEntitlement.resolve(productIDs: []), .free)
    XCTAssertEqual(
      StoreEntitlement.resolve(productIDs: [StoreProducts.lifetime]),
      StoreEntitlement(hasLifetimeUnlock: true, hasSupporterBadge: false)
    )
    XCTAssertEqual(
      StoreEntitlement.resolve(productIDs: [StoreProducts.supporter]),
      StoreEntitlement(hasLifetimeUnlock: false, hasSupporterBadge: true)
    )
  }

  func testStoreEntitlementBadgePriorityPrefersSupporter() {
    let entitlement = StoreEntitlement.resolve(productIDs: [StoreProducts.lifetime, StoreProducts.supporter])
    XCTAssertTrue(entitlement.hasPaidAccess)
    XCTAssertEqual(entitlement.badgeTitle, "Supporter")
    XCTAssertEqual(entitlement.tierTitle, "Supporter")
  }

  func testReviewerEntitlementUnlocksLifetimeAndSupporter() {
    let entitlement = StoreEntitlement.reviewer
    XCTAssertTrue(entitlement.hasPaidAccess)
    XCTAssertTrue(entitlement.hasLifetimeUnlock)
    XCTAssertTrue(entitlement.hasSupporterBadge)
    XCTAssertEqual(entitlement.badgeTitle, "Supporter")
  }

  func testPaywallComparisonRowsIncludePaidFeatureCatalogOnce() {
    let rows = paywallComparisonRows(localizer: AppLocalizer.shared)

    for feature in PaidFeature.paywallComparisonOrder {
      XCTAssertEqual(
        rows.filter { $0.title == feature.comparisonTitle }.count,
        1,
        "\(feature) should appear once in the paywall comparison table"
      )
    }
  }

  @MainActor
  func testStoreManagerCanInitializeWithoutStartingStoreKitTasks() {
    let storeManager = StoreManager(localizer: AppLocalizer.shared, automaticallyStartsStoreKit: false)

    XCTAssertFalse(storeManager.storeKitTasksStarted)
    XCTAssertEqual(storeManager.entitlement, .free)
    XCTAssertTrue(storeManager.products.isEmpty)
    XCTAssertEqual(storeManager.purchaseState, .idle)
    XCTAssertEqual(storeManager.restoreState, .idle)
  }

  @MainActor
  func testCaptureCoordinatorReportsRecordingStateThroughObserver() {
    let coordinator = UITestCaptureCoordinator()
    let observer = RecordingStateSpy()

    coordinator.recordingStateObserver = observer
    coordinator.startRegionCapture()
    coordinator.stopActiveRecordingFromStatusItem()

    XCTAssertEqual(observer.states, [false, true, false])
  }

  @MainActor
  func testInlineRecordingStopReachesControllerBeforeEditorCleanup() throws {
    let image = try XCTUnwrap(makeSolidImage(width: 8, height: 8))
    let view = RegionSelectionView(
      frame: CGRect(x: 0, y: 0, width: 320, height: 240),
      frozenImage: image,
      settings: AppSettings(),
      storeManager: StoreManager(localizer: AppLocalizer.shared, automaticallyStartsStoreKit: false),
      statisticsStore: StatisticsStore(),
      toastPresenter: NoopToastPresenter()
    )
    let controller = RecordingControllerSpy()
    let delegate = ClosingRegionSelectionDelegate()
    view.delegate = delegate
    view.recordingController = controller
    view.recordingActive = true

    view.stopVideoRecordingFromEditor()

    XCTAssertEqual(controller.stopCallCount, 1)
    XCTAssertNil(view.recordingController)
  }

  @MainActor
  func testAppSettingsInitDoesNotWriteDefaults() {
    let suiteName = "vivyshot-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    _ = AppSettings(defaults: defaults)

    XCTAssertNil(defaults.object(forKey: AppSettings.Keys.captureKeyCode))
    XCTAssertNil(defaults.object(forKey: AppSettings.Keys.captureUseCommand))
    XCTAssertNil(defaults.object(forKey: AppSettings.Keys.recordingFrameRate))
    XCTAssertNil(defaults.object(forKey: AppSettings.Keys.webcamOverlayNormalizedX))
  }

  @MainActor
  func testWelcomeStateStorePersistsSeenStateOutsideAppSettings() {
    let suiteName = "vivyshot-welcome-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = WelcomeStateStore(defaults: defaults)

    XCTAssertFalse(store.hasSeenWelcome)

    store.markSeen()

    XCTAssertTrue(store.hasSeenWelcome)
    XCTAssertTrue(WelcomeStateStore(defaults: defaults).hasSeenWelcome)
  }

  @MainActor
  func testProExportTrialStorePersistsConsumptionOutsideAppSettings() {
    let suiteName = "vivyshot-pro-export-trial-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = ProExportTrialStore(defaults: defaults)
    let consumedAt = Date(timeIntervalSince1970: 1_720_000_000)

    XCTAssertTrue(store.isAvailable)

    store.markConsumed(at: consumedAt)

    XCTAssertFalse(store.isAvailable)
    XCTAssertEqual(store.consumedAt, consumedAt)
    XCTAssertEqual(ProExportTrialStore(defaults: defaults).consumedAt, consumedAt)

    store.reset()

    XCTAssertTrue(store.isAvailable)
    XCTAssertTrue(ProExportTrialStore(defaults: defaults).isAvailable)
  }

  @MainActor
  func testAppSettingsPublishesSpecificChangeSlices() {
    let suiteName = "vivyshot-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = AppSettings(defaults: defaults)
    let changes = SettingsChangeRecorder(settings: settings)

    settings.setCaptureShortcut(keyCode: 0, command: true, shift: true, option: false, control: false)
    XCTAssertEqual(changes.shortcutCount, 1)
    XCTAssertEqual(changes.regionCount, 0)
    XCTAssertEqual(changes.videoCount, 0)

    settings.setCaptureShowHelper(false)
    XCTAssertEqual(changes.shortcutCount, 1)
    XCTAssertEqual(changes.regionCount, 1)
    XCTAssertEqual(changes.videoCount, 0)

    settings.setVideoShowWebcam(true)
    XCTAssertEqual(changes.shortcutCount, 1)
    XCTAssertEqual(changes.regionCount, 1)
    XCTAssertEqual(changes.videoCount, 1)
    XCTAssertEqual(changes.languageCount, 0)

    settings.setAppLanguage(.english)
    XCTAssertEqual(changes.shortcutCount, 1)
    XCTAssertEqual(changes.regionCount, 1)
    XCTAssertEqual(changes.videoCount, 1)
    XCTAssertEqual(changes.languageCount, 1)
    XCTAssertEqual(defaults.string(forKey: AppSettings.Keys.appLanguage), AppLanguage.english.rawValue)
  }

  @MainActor
  func testAppEnvironmentOwnsLanguagePropagationToLocalizer() {
    let suiteName = "vivyshot-environment-language-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      AppLocalizer.shared.update(language: .system)
    }
    let settings = AppSettings(defaults: defaults)
    let localizer = AppLocalizer.shared
    let environment = AppEnvironment(
      settings: settings,
      localizer: localizer,
      storeManager: StoreManager(localizer: localizer, automaticallyStartsStoreKit: false),
      proExportTrialStore: ProExportTrialStore(defaults: defaults),
      statisticsStore: StatisticsStore(),
      welcomeStateStore: WelcomeStateStore(defaults: defaults),
      launchAtLoginController: LaunchAtLoginController(localizer: localizer),
      crashReporter: NoopCrashReporter(),
      toastPresenter: NoopToastPresenter(),
      isUITestMode: true
    )

    XCTAssertEqual(localizer.language, .system)

    settings.setAppLanguage(.english)

    XCTAssertEqual(localizer.language, .english)
    _ = environment
  }

  @MainActor
  func testAppSettingsOverlayPlacementPersistsVideoSlice() {
    let suiteName = "vivyshot-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = AppSettings(defaults: defaults)
    let changes = SettingsChangeRecorder(settings: settings)

    settings.setWebcamOverlayFrame(CGRect(x: 0.12, y: 0.16, width: 0.28, height: 0.24))

    XCTAssertEqual(defaults.double(forKey: AppSettings.Keys.webcamOverlayNormalizedX), settings.webcamOverlayNormalizedX)
    XCTAssertEqual(defaults.double(forKey: AppSettings.Keys.webcamOverlayNormalizedY), settings.webcamOverlayNormalizedY)
    XCTAssertEqual(defaults.double(forKey: AppSettings.Keys.webcamOverlayNormalizedWidth), settings.webcamOverlayNormalizedWidth)
    XCTAssertEqual(defaults.double(forKey: AppSettings.Keys.webcamOverlayNormalizedHeight), settings.webcamOverlayNormalizedHeight)
    XCTAssertEqual(changes.shortcutCount, 0)
    XCTAssertEqual(changes.regionCount, 0)
    XCTAssertEqual(changes.videoCount, 1)
  }

  @MainActor
  func testAppSettingsVideoResetPersistsDefaultSnapshot() {
    let suiteName = "vivyshot-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = AppSettings(defaults: defaults)

    settings.setVideoRecordMicrophone(true)
    settings.setVideoShowWebcam(true)
    settings.setWebcamOverlayFrame(CGRect(x: 0.2, y: 0.25, width: 0.3, height: 0.35))
    settings.setVideoExportCodec(.hevc)
    settings.resetVideoCaptureSettings()

    XCTAssertEqual(settings.defaultCaptureType, .screenshot)
    XCTAssertEqual(settings.exportCodec, .h264)
    XCTAssertEqual(settings.recordSystemAudio, true)
    XCTAssertEqual(settings.recordMicrophone, false)
    XCTAssertEqual(settings.showWebcam, false)
    XCTAssertEqual(settings.webcamOverlayNormalizedFrame, AppSettings.defaultWebcamOverlayFrame)
    XCTAssertEqual(settings.keystrokeOverlayNormalizedFrame, AppSettings.defaultKeystrokeOverlayFrame)

    XCTAssertEqual(
      defaults.object(forKey: AppSettings.Keys.defaultCaptureType) as? Int,
      CaptureContentType.screenshot.rawValue
    )
    XCTAssertEqual(defaults.string(forKey: AppSettings.Keys.exportCodec), PostRecordingExportCodec.h264.rawValue)
    XCTAssertEqual(defaults.bool(forKey: AppSettings.Keys.recordSystemAudio), true)
    XCTAssertEqual(defaults.bool(forKey: AppSettings.Keys.recordMicrophone), false)
    XCTAssertEqual(defaults.bool(forKey: AppSettings.Keys.showWebcam), false)
    XCTAssertEqual(defaults.double(forKey: AppSettings.Keys.webcamOverlayNormalizedX), AppSettings.defaultWebcamOverlayFrame.minX)
    XCTAssertEqual(defaults.double(forKey: AppSettings.Keys.keystrokeOverlayNormalizedWidth), AppSettings.defaultKeystrokeOverlayFrame.width)
  }

  func testCaptureStatisticsStorePersistsLedgerAndDerivesDashboard() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-stats-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let databaseURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let store = StatisticsStore(databaseURL: databaseURL)
    let screenshotStartedAt = Date(timeIntervalSince1970: 1_710_000_000)
    let screenshotFinishedAt = screenshotStartedAt.addingTimeInterval(12)
    let recordingAt = screenshotStartedAt.addingTimeInterval(86_400)

    await store.recordScreenshotCaptured(captureID: "capture-1", occurredAt: screenshotStartedAt, bytesProduced: 1_234)
    await store.recordScreenshotSessionCompleted(captureID: "capture-1", startedAt: screenshotStartedAt, finishedAt: screenshotFinishedAt)
    await store.recordRecordingCompleted(recordingID: "recording-1", occurredAt: recordingAt, bytesProduced: 4_321, durationMS: 90_000)

    let dashboardData = await store.dashboardData()
    XCTAssertEqual(dashboardData?.summary.totalScreenshotsCaptured, 1)
    XCTAssertEqual(dashboardData?.summary.totalRecordingsCompleted, 1)
    XCTAssertEqual(dashboardData?.summary.averageScreenshotEditorCompletionDurationMS, 12_000)
    XCTAssertEqual(dashboardData?.dailyBuckets.count, 2)

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    guard let db else {
      XCTFail("Unable to open test database")
      return
    }
    defer { sqlite3_close(db) }
    XCTAssertEqual(try queryInt64(db, sql: "SELECT COUNT(*) FROM stats_ingested_events;"), 3)
  }

  func testCaptureStatisticsStoreEmitsChangeStreamEvents() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-stats-change-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let databaseURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let store = StatisticsStore(databaseURL: databaseURL)
    let changes = await store.changeStream()
    let nextChange = Task {
      var iterator = changes.makeAsyncIterator()
      return await iterator.next() != nil
    }

    await store.recordScreenshotCaptured(
      captureID: "capture-change",
      occurredAt: Date(timeIntervalSince1970: 1_710_000_000),
      bytesProduced: 128
    )

    let emitted = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        await nextChange.value
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }

    XCTAssertTrue(emitted)
  }

  @MainActor
  func testAppCoreImageCropAndEncode() throws {
    let image = try XCTUnwrap(makeSolidImage(width: 40, height: 30))
    let cropped = try XCTUnwrap(ScreenshotImage.crop(image, imageRect: CGRect(x: 5, y: 4, width: 12, height: 10)))
    XCTAssertEqual(cropped.width, 12)
    XCTAssertEqual(cropped.height, 10)

    let png = try XCTUnwrap(ScreenshotImage.encode(cropped, format: .png, jpegQuality: 100))
    let jpeg = try XCTUnwrap(ScreenshotImage.encode(cropped, format: .jpeg, jpegQuality: 88))
    XCTAssertGreaterThan(png.count, 64)
    XCTAssertGreaterThan(jpeg.count, 64)
  }

  @MainActor
  func testVideoExportHelpersStaySafe() {
    let fileType = ExportPlanner.bestSaveFileType(codec: .h264, supportedTypes: [.m4v])
    let preset = ExportPlanner.bestExportPreset(codec: .hevc, quality: .high, compatiblePresets: [])
    XCTAssertEqual(fileType, .m4v)
    XCTAssertEqual(preset, AVAssetExportPresetHighestQuality)

    let context = ExportContext(
      sourceHasAudio: true,
      sourceHasWebcamAsset: false,
      audioTrackVisible: false,
      webcamTrackVisible: true,
      textOverlayCount: 1,
      clickOverlaysVisible: true
    )
    let plan = ExportPlanner.exportPlan(trimStartMS: 100, trimEndMS: 800, keyEventCount: 2, clickEventCount: 1, context: context)
    XCTAssertEqual(plan?.planMode, PlanMode.compositeMP4.rawValue)
    XCTAssertEqual(plan?.overlayItemCount, 4)
    XCTAssertFalse(plan?.includeAudio ?? true)
    XCTAssertTrue(plan?.needsCustomCompositor ?? false)
  }

  @MainActor
  func testCustomMouseClickOverlayRendersFromProjectEvents() throws {
    let project = try XCTUnwrap(
      RecordingProject(
        recordingInfo: RecordingInfo(
          durationMS: 2_000,
          width: 800,
          height: 600,
          frameRate: 30,
          hasAudio: false,
          hasWebcamAsset: false,
          hasMicrophoneAudio: false
        )
      )
    )

    XCTAssertTrue(project.setMouseClickOverlay(style: .system))
    XCTAssertTrue(project.addClickEvent(timestampMS: 500, normalizedX: 0.25, normalizedY: 0.75, button: 0))
    XCTAssertTrue(project.hasMouseClickOverlays)
    let systemPlan = project.renderPlan(timeSeconds: 0.55, renderSize: CGSize(width: 800, height: 600), target: .preview)
    XCTAssertEqual(systemPlan?.items.first?.mouseClickStyleCode, UInt8(MouseClickHighlightStyle.system.rawValue))
    XCTAssertTrue(project.setMouseClickOverlay(style: nil))
    XCTAssertEqual(project.renderPlan(timeSeconds: 0.55, renderSize: CGSize(width: 800, height: 600), target: .preview)?.items.count, 0)

    XCTAssertTrue(project.setMouseClickOverlay(style: .ripple))
    let renderPlan = project.renderPlan(timeSeconds: 0.55, renderSize: CGSize(width: 800, height: 600), target: .preview)
    let item = try XCTUnwrap(renderPlan?.items.first)
    XCTAssertEqual(item.kind, .mouseClick)
    XCTAssertEqual(item.mouseClickStyleCode, UInt8(MouseClickHighlightStyle.ripple.rawValue))
    XCTAssertEqual(item.mouseClickButtonCode, 0)
    XCTAssertTrue(project.hasMouseClickOverlays)
    XCTAssertTrue(project.exportPlan()?.needsCustomCompositor ?? false)
  }

  @MainActor
  func testTrimGIFAndOverlayHelpers() {
    let trim = ExportPlanner.trimRange(durationMS: 1_000, startMS: 950, endMS: 960, minGapMS: 100, activeHandle: .end)
    XCTAssertEqual(trim?.startMS, 950)
    XCTAssertEqual(trim?.endMS, 1_000)

    let gif = ExportPlanner.gifPlan(startMS: 0, endMS: 1_000, preferredFPS: 12, maxDimension: 9_999)
    XCTAssertEqual(gif?.frameCount, 12)
    XCTAssertEqual(gif?.maxDimension, 2_048)
    XCTAssertEqual(gif.flatMap { ExportPlanner.gifFrameTimeMS(plan: $0, index: 0) }, 0)
    XCTAssertEqual(gif.flatMap { ExportPlanner.gifFrameTimeMS(plan: $0, index: 11) }, 1_000)

    let layout = OverlayLayout.keyLabel(renderSize: CGSize(width: 1920, height: 1080), charCount: 6)
    XCTAssertEqual(layout?.height ?? 0, 58, accuracy: 0.01)
  }

  func testRecordingOverlayFrameGeometryMatchesEditorAndSettingsPreviewRules() {
    let container = CGRect(x: 100, y: 50, width: 800, height: 450)

    let generic = RecordingOverlayFrameGeometry.resolvedOverlayFrame(
      CGRect(x: 0.95, y: 0.95, width: 0.2, height: 0.12),
      in: container
    )
    XCTAssertEqual(generic, CGRect(x: 740, y: 446, width: 160, height: 54))

    let normalized = RecordingOverlayFrameGeometry.normalizedOverlayFrame(generic, in: container)
    XCTAssertEqual(normalized.minX, 0.8, accuracy: 0.001)
    XCTAssertEqual(normalized.minY, 0.88, accuracy: 0.001)
    XCTAssertEqual(normalized.width, 0.2, accuracy: 0.001)
    XCTAssertEqual(normalized.height, 0.12, accuracy: 0.001)

    let circularWebcam = RecordingOverlayFrameGeometry.resolvedWebcamOverlayFrame(
      CGRect(x: 0.80, y: 0.10, width: 0.30, height: 0.12),
      in: container,
      shape: .circle,
      aspectRatio: .sixteenNine
    )
    XCTAssertEqual(circularWebcam.width, circularWebcam.height, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(circularWebcam.width, 84)
    XCTAssertTrue(container.contains(circularWebcam))

    XCTAssertEqual(
      RecordingOverlayFrameGeometry.normalizedUnitFrame(CGRect(x: 0.99, y: -0.2, width: 0.01, height: 2)),
      CGRect(x: 0.96, y: 0, width: 0.04, height: 1)
    )

    XCTAssertEqual(
      RecordingOverlayFrameGeometry.denormalizedOverlayFrame(CGRect(x: 0.25, y: 0.4, width: 0.5, height: 0.2), in: container),
      CGRect(x: 300, y: 230, width: 400, height: 90)
    )

    XCTAssertEqual(
      RecordingOverlayFrameGeometry.clampedOverlayFrame(
        CGRect(x: 850, y: 480, width: 20, height: 10),
        in: container,
        minimumSize: CGSize(width: 112, height: 42)
      ),
      CGRect(x: 788, y: 458, width: 112, height: 42)
    )
  }

  func testDisplayCoordinateConversionFlipsAroundPrimaryDisplayHeight() {
    let cocoaRect = CGRect(x: 24, y: 80, width: 320, height: 180)
    let cgRect = DisplayCoordinateConversion.cocoaRectToCGDisplayRect(
      cocoaRect,
      primaryDisplayHeight: 900
    )

    XCTAssertEqual(cgRect, CGRect(x: 24, y: 640, width: 320, height: 180))
    XCTAssertEqual(
      DisplayCoordinateConversion.cgDisplayRectToCocoaRect(cgRect, primaryDisplayHeight: 900),
      cocoaRect
    )
  }

  func testScreenshotImageMapsScreenRectToCapturedImageCropRect() throws {
    let cropRect = try XCTUnwrap(ScreenshotImage.imageCropRect(
      forScreenRect: CGRect(x: 100, y: 50, width: 200, height: 100),
      screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 500),
      imageSize: CGSize(width: 2000, height: 1000)
    ))

    XCTAssertEqual(cropRect, CGRect(x: 200, y: 700, width: 400, height: 200))
  }

  func testRegionSelectionInteractionStateOwnsSelectingTransitions() {
    var state = RegionSelectionInteractionState()

    state.beginManualSelection(at: CGPoint(x: 10, y: 20))
    XCTAssertEqual(state.dragStart, CGPoint(x: 10, y: 20))
    XCTAssertEqual(state.dragCurrent, CGPoint(x: 10, y: 20))
    XCTAssertFalse(state.isIdle)

    state.beginSmartSelection(
      at: CGPoint(x: 30, y: 40),
      windowRect: CGRect(x: 1, y: 2, width: 100, height: 80)
    )
    XCTAssertNil(state.dragStart)
    XCTAssertEqual(state.smartMouseDownPoint, CGPoint(x: 30, y: 40))
    XCTAssertEqual(state.smartWindowHoverRect, CGRect(x: 1, y: 2, width: 100, height: 80))

    state.activateSmartSelectionDrag(from: CGPoint(x: 30, y: 40))
    XCTAssertTrue(state.smartDragActivated)
    XCTAssertEqual(state.dragStart, CGPoint(x: 30, y: 40))
    XCTAssertNil(state.smartWindowHoverRect)

    state.commitSelectingOverlay(rect: CGRect(x: 10, y: 20, width: 50, height: 60))
    XCTAssertNil(state.dragStart)
    XCTAssertNil(state.dragCurrent)
    XCTAssertEqual(state.committedSelectionRect, CGRect(x: 10, y: 20, width: 50, height: 60))
    XCTAssertFalse(state.isIdle)

    state.commitSelectingOverlay(rect: nil)
    state.resetSmartSelection()
    XCTAssertTrue(state.isIdle)
  }

  func testInputEventNormalizerBuildsModifierTokenFromDomainMask() {
    let modifiers = RecordedInputModifierMask.command
      | RecordedInputModifierMask.shift
      | RecordedInputModifierMask.option
      | RecordedInputModifierMask.control

    XCTAssertEqual(
      InputEventNormalizer.normalizeKeyToken(keyCode: 8, modifiers: modifiers, characters: "c"),
      "⌘⇧⌥⌃C"
    )
    XCTAssertEqual(
      InputEventNormalizer.normalizeKeyToken(keyCode: 40, modifiers: 0, characters: nil),
      "K"
    )
  }

  func testCanvasGeometryFlipsYForImageRectsAndDeltas() throws {
    let destination = CGRect(x: 10, y: 20, width: 200, height: 100)
    let imageSize = CGSize(width: 400, height: 200)

    let imageRect = try XCTUnwrap(CanvasGeometry.viewRectToImageRect(
      viewRect: CGRect(x: 60, y: 90, width: 40, height: 30),
      destinationRect: destination,
      imageSize: imageSize
    ))
    XCTAssertEqual(imageRect, CGRect(x: 100, y: 0, width: 80, height: 60))

    let viewRect = try XCTUnwrap(CanvasGeometry.imageRectToViewRect(
      imageRect: imageRect,
      destinationRect: destination,
      imageSize: imageSize
    ))
    XCTAssertEqual(viewRect, CGRect(x: 60, y: 90, width: 40, height: 30))

    XCTAssertEqual(
      CanvasGeometry.viewDeltaToImageDelta(CGPoint(x: 5, y: 10), destinationRect: destination, imageSize: imageSize),
      CGPoint(x: 10, y: -20)
    )
    XCTAssertEqual(
      CanvasGeometry.imageDeltaToViewDelta(CGPoint(x: 10, y: 20), destinationRect: destination, imageSize: imageSize),
      CGPoint(x: 5, y: -10)
    )
  }

  func testAnnotationSessionRendersImageSpaceAtTopLeft() throws {
    let image = try XCTUnwrap(makeSolidImage(width: 24, height: 24, color: .white))
    let session = try XCTUnwrap(AnnotationSession(image: image))
    let rendered = try XCTUnwrap(session.addFilledRect(
      imageRect: CGRect(x: 2, y: 2, width: 8, height: 8),
      color: .black
    ))

    XCTAssertTrue(try isDarkPixel(in: rendered, x: 4, y: 4))
    XCTAssertFalse(try isDarkPixel(in: rendered, x: 4, y: 20))
  }

  func testAnnotationSessionRendersTextUprightInImageSpace() throws {
    let image = try XCTUnwrap(makeSolidImage(width: 80, height: 80, color: .white))
    let session = try XCTUnwrap(AnnotationSession(image: image))
    let rendered = try XCTUnwrap(session.addText(
      "F",
      at: CGPoint(x: 10, y: 10),
      style: TextAnnotationStyle(fontSize: 48, color: .black)
    ))

    let upperRightInk = try darkPixelCount(in: rendered, rect: CGRect(x: 30, y: 12, width: 20, height: 14))
    let lowerRightInk = try darkPixelCount(in: rendered, rect: CGRect(x: 30, y: 48, width: 20, height: 14))
    XCTAssertGreaterThan(upperRightInk, 8)
    XCTAssertLessThan(lowerRightInk, 3)
  }

  @MainActor
  func testInlineTextCommitUsesEditorTextRectAnchor() throws {
    let canvasView = AnnotationCanvasView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    canvasView.image = try XCTUnwrap(makeSolidImage(width: 100, height: 100, color: .white))
    canvasView.textStyle = EditorTextStyle(fontSize: 16, color: .black)

    let delegate = AnnotationCanvasDelegateSpy()
    canvasView.delegate = delegate

    canvasView.beginInlineTextEditor(
      at: CGPoint(x: 95, y: 95),
      imagePoint: CGPoint(x: 95, y: 5)
    )
    let textField = try XCTUnwrap(canvasView.inlineTextField)
    textField.stringValue = "Hello"

    let textRect = try XCTUnwrap(textField.cell?.titleRect(forBounds: textField.bounds))
    let expectedAnchor = try XCTUnwrap(canvasView.imagePointFromViewPoint(CGPoint(
      x: textField.frame.minX + textRect.minX,
      y: textField.frame.minY + textRect.maxY
    )))

    canvasView.finishInlineTextEditing(commit: true)

    guard case .text("Hello", let committedPoint) = try XCTUnwrap(delegate.commits.first) else {
      return XCTFail("Expected text commit")
    }
    XCTAssertEqual(committedPoint.x, expectedAnchor.x, accuracy: 0.01)
    XCTAssertEqual(committedPoint.y, expectedAnchor.y, accuracy: 0.01)
  }

  func testAnnotationSessionPixelatesImageSpaceAtTopLeft() throws {
    let image = try XCTUnwrap(makePrivacyEffectTestImage(width: 24, height: 24))
    let session = try XCTUnwrap(AnnotationSession(image: image))
    let rendered = try XCTUnwrap(session.addPixelate(imageRect: CGRect(x: 0, y: 0, width: 12, height: 12)))

    let original = try rgbPixel(in: image, x: 3, y: 8)
    let affected = try rgbPixel(in: rendered, x: 3, y: 8)
    let unaffected = try rgbPixel(in: rendered, x: 3, y: 20)
    XCTAssertNotEqual(affected, original)
    XCTAssertEqual(unaffected, RGBPixel(red: 255, green: 0, blue: 0))
  }

  func testAnnotationSessionBlursImageSpaceAtTopLeft() throws {
    let image = try XCTUnwrap(makePrivacyEffectTestImage(width: 24, height: 24))
    let session = try XCTUnwrap(AnnotationSession(image: image))
    let rendered = try XCTUnwrap(session.addBlur(imageRect: CGRect(x: 3, y: 0, width: 6, height: 12)))

    let affected = try rgbPixel(in: rendered, x: 5, y: 4)
    let unaffected = try rgbPixel(in: rendered, x: 5, y: 20)
    XCTAssertGreaterThan(affected.red, 32)
    XCTAssertLessThan(affected.red, 255)
    XCTAssertEqual(unaffected, RGBPixel(red: 255, green: 0, blue: 0))
  }

  func testArrowHeadGeometryMatchesOpenPreviewShape() throws {
    let points = try XCTUnwrap(AnnotationArrowGeometry.headPoints(
      start: CGPoint(x: 10, y: 50),
      end: CGPoint(x: 70, y: 50),
      strokeWidth: 5
    ))

    XCTAssertEqual(points.0.x, points.1.x, accuracy: 0.01)
    XCTAssertEqual(points.0.x, 44.02, accuracy: 0.01)
    XCTAssertEqual(points.0.y, 35, accuracy: 0.01)
    XCTAssertEqual(points.1.y, 65, accuracy: 0.01)
  }

  func testArrowHeadGeometryScalesMinimumLengthForCommittedImage() throws {
    let preview = try XCTUnwrap(AnnotationArrowGeometry.headPoints(
      start: CGPoint(x: 10, y: 20),
      end: CGPoint(x: 60, y: 20),
      strokeWidth: 1
    ))
    let committed = try XCTUnwrap(AnnotationArrowGeometry.headPoints(
      start: CGPoint(x: 20, y: 40),
      end: CGPoint(x: 120, y: 40),
      strokeWidth: 2,
      minimumHeadLength: AnnotationArrowGeometry.minimumHeadLength * 2
    ))

    XCTAssertEqual(committed.0.x / 2, preview.0.x, accuracy: 0.01)
    XCTAssertEqual(committed.0.y / 2, preview.0.y, accuracy: 0.01)
    XCTAssertEqual(committed.1.x / 2, preview.1.x, accuracy: 0.01)
    XCTAssertEqual(committed.1.y / 2, preview.1.y, accuracy: 0.01)
  }

  func testCanvasGeometryClampsPanUsingFittedDrawSize() throws {
    let clamped = try XCTUnwrap(CanvasGeometry.clampPanOffset(
      boundsSize: CGSize(width: 1_000, height: 500),
      imageSize: CGSize(width: 4_000, height: 2_000),
      zoomScale: 1,
      overscroll: 24,
      candidate: CGPoint(x: 2_000, y: -2_000)
    ))
    XCTAssertEqual(clamped.x, 24, accuracy: 0.01)
    XCTAssertEqual(clamped.y, -24, accuracy: 0.01)
  }

  func testResizableRectKeepsOppositeEdgeFixedWhenCrossingMinimumSize() throws {
    let resized = try XCTUnwrap(ResizableRect.resizeRect(
      start: CGRect(x: 100, y: 100, width: 80, height: 60),
      bounds: CGRect(x: 0, y: 0, width: 500, height: 500),
      edge: .left,
      delta: CGPoint(x: 120, y: 0),
      minWidth: 20,
      minHeight: 20
    ))
    XCTAssertEqual(resized, CGRect(x: 160, y: 100, width: 20, height: 60))
  }

  @MainActor
  func testLaunchAtLoginControllerHandlesApprovalAndDisable() {
    let service = StubLaunchAtLoginService(status: .notRegistered)
    service.statusAfterRegister = .requiresApproval
    service.statusAfterUnregister = .notRegistered

    let controller = LaunchAtLoginController(service: service, localizer: AppLocalizer.shared)
    controller.setEnabled(true)
    XCTAssertTrue(controller.isEnabled)
    XCTAssertEqual(controller.detailText, "Finish enabling startup in System Settings > General > Login Items.")
    XCTAssertEqual(service.registerCallCount, 1)

    controller.setEnabled(false)
    XCTAssertFalse(controller.isEnabled)
    XCTAssertNil(controller.detailText)
    XCTAssertEqual(service.unregisterCallCount, 1)
  }

  @MainActor
  func testLaunchAtLoginControllerSurfacesUpdateErrors() {
    enum StubError: LocalizedError {
      case blocked

      var errorDescription: String? { "Blocked" }
    }

    let service = StubLaunchAtLoginService(status: .notRegistered)
    service.registerError = StubError.blocked
    let controller = LaunchAtLoginController(service: service, localizer: AppLocalizer.shared)
    controller.setEnabled(true)
    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(controller.detailText, "Unable to update launch at login. Blocked")
    XCTAssertEqual(service.registerCallCount, 1)
  }

  private func makeSolidImage(width: Int, height: Int, color: NSColor = .systemBlue) -> CGImage? {
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  private func makePrivacyEffectTestImage(width: Int, height: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        if y >= height / 2 {
          pixels[index] = 255
          pixels[index + 1] = 0
          pixels[index + 2] = 0
        } else if x < width / 4 {
          pixels[index] = 0
          pixels[index + 1] = 0
          pixels[index + 2] = 0
        } else {
          pixels[index] = 255
          pixels[index + 1] = 255
          pixels[index + 2] = 255
        }
      }
    }
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    return context.makeImage()
  }

  private func isDarkPixel(in image: CGImage, x: Int, y: Int) throws -> Bool {
    let pixel = try rgbPixel(in: image, x: x, y: y)
    return pixel.red < 64 && pixel.green < 64 && pixel.blue < 64
  }

  private func darkPixelCount(in image: CGImage, rect: CGRect) throws -> Int {
    let normalized = rect.standardized
    let minX = max(0, Int(normalized.minX.rounded(.down)))
    let maxX = min(image.width, Int(normalized.maxX.rounded(.up)))
    let minY = max(0, Int(normalized.minY.rounded(.down)))
    let maxY = min(image.height, Int(normalized.maxY.rounded(.up)))
    var count = 0

    for y in minY..<maxY {
      for x in minX..<maxX where try isDarkPixel(in: image, x: x, y: y) {
        count += 1
      }
    }
    return count
  }

  private func rgbPixel(in image: CGImage, x: Int, y: Int) throws -> RGBPixel {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw NSError(domain: "AppTests", code: -3, userInfo: nil)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let index = (y * image.width + x) * 4
    return RGBPixel(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2])
  }
}

private struct RGBPixel: Equatable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8
}

private func queryInt64(_ db: OpaquePointer, sql: String) throws -> Int64 {
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
    throw NSError(domain: "AppTests", code: -1, userInfo: nil)
  }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW else {
    throw NSError(domain: "AppTests", code: -2, userInfo: nil)
  }
  return sqlite3_column_int64(statement, 0)
}
