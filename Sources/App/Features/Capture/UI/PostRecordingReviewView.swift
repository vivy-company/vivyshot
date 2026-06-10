import AppKit
import SwiftUI

struct PostRecordingActionView: View {
  let project: PostRecordingProject
  @ObservedObject var reviewState: PostRecordingReviewState
  let thumbnail: NSImage?
  @StateObject private var playbackState = PostRecordingPreviewPlaybackState()

  init(
    project: PostRecordingProject,
    reviewState: PostRecordingReviewState,
    thumbnail: NSImage?
  ) {
    self.project = project
    self.reviewState = reviewState
    self.thumbnail = thumbnail
  }

  var body: some View {
    ZStack {
      Color.black

      if FileManager.default.fileExists(atPath: project.inputURL.path) {
        VStack(spacing: 0) {
          ZStack {
            PostRecordingPlayerPreview(
              url: project.inputURL,
              playbackState: playbackState,
              isMuted: !reviewState.editState.isOutputAudioEnabled
            )

            PostRecordingOverlayPreviewLayer(
              project: project,
              playbackState: playbackState
            )
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          PostRecordingPlaybackControls(
            reviewState: reviewState,
            playbackState: playbackState
          )
        }
        .onAppear {
          playbackState.configure(
            durationSeconds: project.durationSeconds,
            exportState: reviewState.exportState()
          )
        }
        .onChange(of: reviewState.editState) { _, newValue in
          playbackState.configure(
            durationSeconds: project.durationSeconds,
            exportState: newValue.exportState
          )
        }
      } else if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Image(systemName: "film")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(.white.opacity(0.7))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
  }
}
