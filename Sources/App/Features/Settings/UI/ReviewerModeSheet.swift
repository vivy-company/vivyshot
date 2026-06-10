import SwiftUI

struct ReviewerModeSheet: View {
  @ObservedObject var storeManager: StoreManager
  @Environment(\.dismiss) private var dismiss
  @State private var reviewCode = ""
  @State private var reviewError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        ZStack {
          Circle()
            .fill(Color.green.opacity(0.16))
            .frame(width: 44, height: 44)
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.green)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("App Review")
            .font(.title3)
            .fontWeight(.semibold)
          Text("Temporarily unlocks Lifetime and Supporter access.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      statusCard

      if storeManager.isReviewModeEnabled {
        enabledSection
      } else {
        codeSection
      }

      HStack {
        Spacer()
        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 460)
  }

  private var statusCard: some View {
    HStack {
      Text("Reviewer Mode")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(storeManager.isReviewModeEnabled ? "Enabled" : "Disabled")
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
          Capsule()
            .fill(storeManager.isReviewModeEnabled ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
        )
        .foregroundStyle(storeManager.isReviewModeEnabled ? .green : .secondary)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var enabledSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Reviewer mode is active on this device.")
        .font(.subheadline)
      Text(reviewModeExpiryText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button("Disable Reviewer Mode") {
        storeManager.setReviewModeEnabled(false)
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var codeSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Enter the review code to enable full access for App Review.")
        .font(.subheadline)
      TextField("Review Code", text: $reviewCode)
        .textFieldStyle(.roundedBorder)

      Button("Enable Reviewer Mode") {
        let success = storeManager.enableReviewMode(code: reviewCode)
        if success {
          reviewError = nil
          reviewCode = ""
        } else {
          reviewError = "Invalid review code."
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(reviewCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

      if let reviewError {
        Text(reviewError)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      Text("Reviewer mode is local-only and expires after 2 hours or when the app restarts.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var reviewModeExpiryText: String {
    guard let expiresAt = storeManager.reviewModeExpiresAt else {
      return String(
        localized: "Lifetime and Supporter access are unlocked until the app restarts.",
        bundle: AppLocalizer.shared.bundle
      )
    }

    let format = String(
      localized: "Lifetime and Supporter access are unlocked until %@.",
      bundle: AppLocalizer.shared.bundle
    )
    return String(format: format, expiresAt.formatted(date: .omitted, time: .shortened))
  }
}
