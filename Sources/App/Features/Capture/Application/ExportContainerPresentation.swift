import UniformTypeIdentifiers

extension ExportPlanner {
  static func preferredSaveContentType(codec: PostRecordingExportCodec) -> UTType {
    preferredSaveContainer(codec: codec) == .mov ? .quickTimeMovie : .mpeg4Movie
  }

  static func allowedSaveContentTypes(codec: PostRecordingExportCodec) -> [UTType] {
    codec == .hevc ? [.quickTimeMovie, .mpeg4Movie] : [.mpeg4Movie, .quickTimeMovie]
  }
}

extension PostRecordingVideoSaveContainer {
  var contentType: UTType {
    switch self {
    case .mp4:
      return .mpeg4Movie
    case .mov:
      return .quickTimeMovie
    }
  }

  var fileExtension: String {
    switch self {
    case .mp4:
      return "mp4"
    case .mov:
      return "mov"
    }
  }
}
