/// Output image format selected by screenshot export.
enum ImageEncodeFormat: UInt8 {
  case png = 0
  case jpeg = 1
}

/// Runtime scroll direction state for stitched screenshot capture.
struct StitchAutoScrollState {
  var directionSign: Int32
  var noMotionTicks: UInt32
  var didFlipDirection: Bool
}

/// Result of ingesting one stitch segment into a stitch session.
struct StitchSessionResult {
  let accepted: Bool
  let rows: Int
  let side: UInt8
  let score: Double
  let directionLocked: Bool
  let expectedRows: Int
  let segmentCount: Int
  let scrollDirectionSign: Int
}
