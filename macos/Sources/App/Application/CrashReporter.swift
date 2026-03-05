import AppKit
import CryptoKit
import Foundation

final class CrashReporter {
  nonisolated(unsafe) static let shared = CrashReporter()

  private struct SessionMarker: Codable {
    let pid: Int32
    let executable: String
    let appVersion: String
    let startedAtISO8601: String
  }

  private struct PendingRecovery {
    let marker: SessionMarker
    let crashReportPath: String?
    let logURL: URL
  }

  private struct AnonymousCrashDetails {
    let reportID: String
    let osVersion: String
    let exceptionType: String
    let signal: String
    let termination: String
    let faultingThread: String
    let topFrame: String
  }

  private let fileManager = FileManager.default
  private let isoFormatter = ISO8601DateFormatter()
  private let diagnosticsDirectoryURL: URL
  private let sessionMarkerURL: URL
  private var pendingRecovery: PendingRecovery?

  private init() {
    let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
    let executable = Self.executableName
    diagnosticsDirectoryURL = appSupportRoot
      .appendingPathComponent(executable, isDirectory: true)
      .appendingPathComponent("Diagnostics", isDirectory: true)
    sessionMarkerURL = diagnosticsDirectoryURL.appendingPathComponent("active-session.json")
  }

  func install() {
    ensureDiagnosticsDirectoryExists()
    recoverUnexpectedTerminationIfNeeded()
    writeCurrentSessionMarker()
    NSSetUncaughtExceptionHandler { exception in
      CrashReporter.shared.recordUncaughtException(exception)
    }
  }

  func markCleanShutdown() {
    try? fileManager.removeItem(at: sessionMarkerURL)
  }

  @MainActor
  func presentRecoveredCrashNoticeIfNeeded() {
    guard let pendingRecovery else {
      return
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "VivyShot Quit Unexpectedly"
    alert.informativeText = "VivyShot recovered and can continue normally. Send a crash report so we can fix it faster."
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Send Report")
    alert.addButton(withTitle: "Show Files")

    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertSecondButtonReturn {
      openPrefilledIssue(recovery: pendingRecovery)
    } else if response == .alertThirdButtonReturn {
      revealRecoveryFiles(recovery: pendingRecovery)
    }

    self.pendingRecovery = nil
  }

  private func ensureDiagnosticsDirectoryExists() {
    try? fileManager.createDirectory(at: diagnosticsDirectoryURL, withIntermediateDirectories: true)
  }

  private func recoverUnexpectedTerminationIfNeeded() {
    guard let rawData = try? Data(contentsOf: sessionMarkerURL),
          let marker = try? JSONDecoder().decode(SessionMarker.self, from: rawData)
    else {
      return
    }

    try? fileManager.removeItem(at: sessionMarkerURL)

    let recoveredAt = isoFormatter.string(from: Date())
    let crashReportPath = latestSystemCrashReportPath(executable: marker.executable)
    let crashReportPathText = crashReportPath ?? "Not found"
    let summary = """
    Previous run ended unexpectedly.
    Started: \(marker.startedAtISO8601)
    PID: \(marker.pid)
    Version: \(marker.appVersion)
    System crash report: \(crashReportPathText)
    """

    let fileName = "recovered-crash-\(safeTimestamp()).log"
    let logURL = diagnosticsDirectoryURL.appendingPathComponent(fileName)
    let body = """
    VivyShot recovered crash report
    Recovered at: \(recoveredAt)

    \(summary)
    """
    try? body.data(using: .utf8)?.write(to: logURL, options: .atomic)

    pendingRecovery = PendingRecovery(
      marker: marker,
      crashReportPath: crashReportPath,
      logURL: logURL
    )
  }

  private func writeCurrentSessionMarker() {
    let marker = SessionMarker(
      pid: getpid(),
      executable: Self.executableName,
      appVersion: Self.appVersionString,
      startedAtISO8601: isoFormatter.string(from: Date())
    )
    guard let data = try? JSONEncoder().encode(marker) else {
      return
    }
    try? data.write(to: sessionMarkerURL, options: .atomic)
  }

  private func recordUncaughtException(_ exception: NSException) {
    let fileName = "uncaught-exception-\(safeTimestamp()).log"
    let logURL = diagnosticsDirectoryURL.appendingPathComponent(fileName)
    let stack = exception.callStackSymbols.joined(separator: "\n")
    let body = """
    Uncaught exception captured by VivyShot
    Time: \(isoFormatter.string(from: Date()))
    Name: \(exception.name.rawValue)
    Reason: \(exception.reason ?? "Unknown")

    Stack:
    \(stack)
    """
    try? body.data(using: .utf8)?.write(to: logURL, options: .atomic)
  }

  private func latestSystemCrashReportPath(executable: String) -> String? {
    let reportsDirectory = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    guard let files = try? fileManager.contentsOfDirectory(
      at: reportsDirectory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      return nil
    }

    let name = executable.lowercased()
    let candidates = files.filter { url in
      let lower = url.lastPathComponent.lowercased()
      guard lower.hasPrefix(name) else {
        return false
      }
      return lower.hasSuffix(".crash") || lower.hasSuffix(".ips")
    }

    let newest = candidates.max { lhs, rhs in
      let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return leftDate < rightDate
    }

    return newest?.path
  }

  private func safeTimestamp() -> String {
    isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
  }

  @MainActor
  private func revealRecoveryFiles(recovery: PendingRecovery) {
    var urls = [recovery.logURL]
    if let crashReportPath = recovery.crashReportPath {
      urls.append(URL(fileURLWithPath: crashReportPath))
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @MainActor
  private func openPrefilledIssue(recovery: PendingRecovery) {
    let details = makeAnonymousCrashDetails(recovery: recovery)

    let body = """
    ### Anonymous Crash Report
    - Report ID: \(details.reportID)
    - App version: \(recovery.marker.appVersion)
    - OS version: \(details.osVersion)
    - Crash type: \(details.exceptionType) / \(details.signal)
    - Termination: \(details.termination)
    - Faulting thread: \(details.faultingThread)
    - Top frame: \(details.topFrame)

    ### What Were You Doing?
    Describe the steps right before the crash and what you expected.

    ### Privacy
    This report intentionally excludes local paths, file names, usernames, and process IDs.
    """

    var components = URLComponents(string: "https://github.com/vivy-company/vivyshot/issues/new")
    components?.queryItems = [
      URLQueryItem(name: "title", value: "Crash report: \(details.reportID)"),
      URLQueryItem(name: "body", value: body),
    ]

    if let url = components?.url, NSWorkspace.shared.open(url) {
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(body, forType: .string)

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Crash Details Copied"
    alert.informativeText = "Could not open the issue page. Crash details were copied to clipboard."
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func makeAnonymousCrashDetails(recovery: PendingRecovery) -> AnonymousCrashDetails {
    let unknown = "unknown"
    var osVersion = unknown
    var exceptionType = unknown
    var signal = unknown
    var termination = unknown
    var faultingThread = unknown
    var topFrame = unknown

    if let path = recovery.crashReportPath,
       let parsed = parseIPSCrashMetadata(path: path)
    {
      osVersion = parsed.osVersion
      exceptionType = parsed.exceptionType
      signal = parsed.signal
      termination = parsed.termination
      faultingThread = parsed.faultingThread
      topFrame = parsed.topFrame
    }

    let fingerprintSeed = [
      recovery.marker.appVersion,
      osVersion,
      exceptionType,
      signal,
      termination,
      faultingThread,
      topFrame,
    ].joined(separator: "|")

    let reportID = Self.sha256Hex(fingerprintSeed).prefix(12).uppercased()
    return AnonymousCrashDetails(
      reportID: "VS-\(reportID)",
      osVersion: osVersion,
      exceptionType: exceptionType,
      signal: signal,
      termination: termination,
      faultingThread: faultingThread,
      topFrame: topFrame
    )
  }

  private func parseIPSCrashMetadata(path: String) -> (
    osVersion: String,
    exceptionType: String,
    signal: String,
    termination: String,
    faultingThread: String,
    topFrame: String
  )? {
    guard path.lowercased().hasSuffix(".ips") else {
      return nil
    }
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
      return nil
    }
    guard let firstNewline = raw.firstIndex(of: "\n") else {
      return nil
    }
    let body = String(raw[raw.index(after: firstNewline)...])
    guard let bodyData = body.data(using: .utf8),
          let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    else {
      return nil
    }

    let osVersion: String = {
      guard let os = payload["osVersion"] as? [String: Any] else {
        return "unknown"
      }
      let train = (os["train"] as? String) ?? "macOS"
      let build = (os["build"] as? String) ?? "unknown"
      return "\(train) (\(build))"
    }()

    let exceptionType = ((payload["exception"] as? [String: Any])?["type"] as? String) ?? "unknown"
    let signal = ((payload["exception"] as? [String: Any])?["signal"] as? String) ?? "unknown"
    let termination = ((payload["termination"] as? [String: Any])?["indicator"] as? String) ?? "unknown"

    let faultingThreadInt = payload["faultingThread"] as? Int
    let faultingThread = faultingThreadInt.map(String.init) ?? "unknown"
    let topFrame = extractTopFrameSymbol(payload: payload, faultingThread: faultingThreadInt) ?? "unknown"

    return (osVersion, exceptionType, signal, termination, faultingThread, topFrame)
  }

  private func extractTopFrameSymbol(payload: [String: Any], faultingThread: Int?) -> String? {
    guard let threads = payload["threads"] as? [[String: Any]], !threads.isEmpty else {
      return nil
    }

    let targetThread: [String: Any]? = {
      if let faultingThread {
        if threads.indices.contains(faultingThread) {
          return threads[faultingThread]
        }
        if let byID = threads.first(where: { ($0["id"] as? Int) == faultingThread }) {
          return byID
        }
      }
      return threads.first(where: { ($0["triggered"] as? Bool) == true }) ?? threads.first
    }()

    guard let targetThread,
          let frames = targetThread["frames"] as? [[String: Any]],
          !frames.isEmpty
    else {
      return nil
    }

    for frame in frames {
      if let symbol = frame["symbol"] as? String, !symbol.isEmpty {
        return symbol
      }
    }
    return nil
  }

  private static func sha256Hex(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static var executableName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "VivyShot"
  }

  private static var appVersionString: String {
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    return "\(shortVersion) (\(build))"
  }
}
