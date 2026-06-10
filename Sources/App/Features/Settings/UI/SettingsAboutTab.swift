import AppKit
import SwiftUI

@MainActor
extension SettingsView {
  var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
  }

  var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }

  var aboutHeroSection: some View {
    Section {
      VStack(spacing: 16) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .frame(width: 80, height: 80)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

        Text("VivyShot")
          .font(.title)
          .fontWeight(.bold)

        Text("Screen capture and recording for macOS.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Text("Capture a region, window, or screen, then annotate screenshots, trim recordings, and export when you are done.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Text("Version \(appVersion) (\(buildNumber))")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .onTapGesture(count: 7) {
            isReviewerModeSheetPresented = true
          }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)
    }
  }

  var aboutLinksSection: some View {
    Section("Links") {
      AboutLinkRow(
        title: String(localized: "Website", bundle: AppLocalizer.shared.bundle),
        systemImage: "globe",
        url: URL(string: "https://vivyshot.com")!
      )
      AboutLinkRow(
        title: String(localized: "Privacy Policy", bundle: AppLocalizer.shared.bundle),
        systemImage: "hand.raised",
        url: URL(string: "https://vivyshot.com/privacy")!
      )
      AboutLinkRow(
        title: String(localized: "Terms of Use", bundle: AppLocalizer.shared.bundle),
        systemImage: "doc.text",
        url: URL(string: "https://vivyshot.com/terms")!
      )
    }
  }

  var aboutContactSection: some View {
    Section("Get in Touch") {
      AboutLinkRow(
        title: String(localized: "Developer", bundle: AppLocalizer.shared.bundle),
        systemImage: "person.crop.circle",
        url: URL(string: "https://x.com/wiedymi")!
      )
      AboutLinkRow(
        title: String(localized: "Discord", bundle: AppLocalizer.shared.bundle),
        systemImage: "bubble.left.and.bubble.right",
        url: URL(string: "https://discord.gg/zemMZtrkSb")!
      )
      AboutLinkRow(
        title: String(localized: "Email", bundle: AppLocalizer.shared.bundle),
        systemImage: "envelope",
        url: URL(string: "mailto:vivyshot@vivy.company")!
      )
    }
  }

  var aboutAppsSection: some View {
    Section("Our Apps") {
      AboutLinkRow(
        title: "VVTerm",
        subtitle: String(localized: "Native SSH terminal and SFTP client for iPhone, iPad, and Mac.", bundle: AppLocalizer.shared.bundle),
        assetImage: "VVTermIcon",
        url: URL(string: "https://vvterm.com")!
      )
    }
  }

}
