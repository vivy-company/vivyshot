import Foundation

enum CaptureTemporaryFiles {
  static func recordingURL() -> URL {
    url(prefix: "capture", pathExtension: "mp4")
  }

  static func webcamURL() -> URL {
    url(prefix: "webcam", pathExtension: "mov")
  }

  static func exportURL(pathExtension: String) -> URL {
    url(prefix: "export", pathExtension: pathExtension)
  }

  static func clipboardURL(pathExtension: String) -> URL {
    url(prefix: "clipboard", pathExtension: pathExtension)
  }

  private static func url(prefix: String, pathExtension: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(prefix)-\(UUID().uuidString).\(pathExtension)")
  }
}
