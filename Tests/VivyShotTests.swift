import AppKit
import AVFoundation
import SQLite3
import XCTest
@testable import VivyShot

final class AppTests: XCTestCase {
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
      textOverlayCount: 1
    )
    let plan = ExportPlanner.exportPlan(trimStartMS: 100, trimEndMS: 800, keyEventCount: 2, clickEventCount: 1, context: context)
    XCTAssertEqual(plan?.planMode, PlanMode.compositeMP4.rawValue)
    XCTAssertEqual(plan?.overlayItemCount, 3)
    XCTAssertFalse(plan?.includeAudio ?? true)
    XCTAssertTrue(plan?.needsCustomCompositor ?? false)
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
      cornerCode: 5,
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

    let controller = LaunchAtLoginController(service: service)
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
    let controller = LaunchAtLoginController(service: service)
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
