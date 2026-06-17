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

        Text(localized("Screen capture and recording for macOS."))
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Text(localized("Capture a region, window, or screen, then annotate screenshots, trim recordings, and export when you are done."))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Text(String(format: localized("Version %@ (%@)"), appVersion, buildNumber))
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
    Section(localized("Links")) {
      AboutLinkRow(
        title: localized("Website"),
        systemImage: "globe",
        url: URL(string: "https://vivyshot.com")!
      )
      AboutLinkRow(
        title: localized("Privacy Policy"),
        systemImage: "hand.raised",
        url: URL(string: "https://vivyshot.com/privacy")!
      )
      AboutLinkRow(
        title: localized("Terms of Use"),
        systemImage: "doc.text",
        url: URL(string: "https://vivyshot.com/terms")!
      )
    }
  }

  var aboutContactSection: some View {
    Section(localized("Get in Touch")) {
      AboutLinkRow(
        title: localized("Developer"),
        systemImage: "person.crop.circle",
        url: URL(string: "https://x.com/wiedymi")!
      )
      AboutLinkRow(
        title: localized("Discord"),
        systemImage: "bubble.left.and.bubble.right",
        url: URL(string: "https://discord.gg/zemMZtrkSb")!
      )
      AboutLinkRow(
        title: localized("Email"),
        systemImage: "envelope",
        url: URL(string: "mailto:vivyshot@vivy.company")!
      )
    }
  }

  var aboutAppsSection: some View {
    Section(localized("Our Apps")) {
      AboutLinkRow(
        title: "VVTerm",
        subtitle: localized("Native SSH terminal and SFTP client for iPhone, iPad, and Mac."),
        assetImage: "VVTermIcon",
        url: URL(string: "https://vvterm.com")!
      )
    }
  }

}
