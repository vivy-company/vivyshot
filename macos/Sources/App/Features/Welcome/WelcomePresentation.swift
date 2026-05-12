import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
  static let shared = WelcomeWindowController()

  private init() {
    let contentSize = Self.contentSize(needsScreenRecordingPermission: !CGPreflightScreenCaptureAccess())
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = String(localized: "Welcome to VivyShot", bundle: AppLocalizer.shared.bundle)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(contentSize)
    window.contentMinSize = NSSize(width: 520, height: 560)

    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show(onStartCapture: @escaping () -> Void = {}) {
    show(onStartCapture: onStartCapture, onOpenSettings: presentSettingsWindow)
  }

  func show(
    onStartCapture: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void
  ) {
    guard let window else { return }

    let needsPermission = !CGPreflightScreenCaptureAccess()
    let contentSize = Self.contentSize(needsScreenRecordingPermission: needsPermission)
    window.title = String(localized: "Welcome to VivyShot", bundle: AppLocalizer.shared.bundle)
    window.setContentSize(contentSize)
    window.contentView = NSHostingView(
      rootView: AnyView(
        VivyShotWelcomeView(
          settings: .shared,
          screenRecordingAllowed: !needsPermission,
          onStartCapture: { [weak self] in
            self?.completeWelcome()
            onStartCapture()
          },
          onOpenSettings: { [weak self] in
            self?.completeWelcome()
            onOpenSettings()
          },
          onOpenScreenRecordingSettings: {
            openScreenRecordingSettings()
          }
        )
        .environment(\.locale, AppLocalizer.shared.locale)
        .frame(width: contentSize.width, height: contentSize.height)
      )
    )
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    AppSettings.shared.markWelcomeSeen()
  }

  private func completeWelcome() {
    AppSettings.shared.markWelcomeSeen()
    window?.close()
  }

  private static func contentSize(needsScreenRecordingPermission: Bool) -> NSSize {
    NSSize(width: 560, height: needsScreenRecordingPermission ? 700 : 640)
  }
}

@MainActor
func presentWelcomeWindow(onStartCapture: @escaping () -> Void = {}) {
  WelcomeWindowController.shared.show(onStartCapture: onStartCapture)
}

@MainActor
func presentWelcomeWindow(
  onStartCapture: @escaping () -> Void,
  onOpenSettings: @escaping () -> Void
) {
  WelcomeWindowController.shared.show(onStartCapture: onStartCapture, onOpenSettings: onOpenSettings)
}

@MainActor
func presentWelcomeWindowIfNeeded(
  onStartCapture: @escaping () -> Void = {},
  onOpenSettings: @escaping () -> Void = {}
) {
  guard !AppSettings.shared.hasSeenWelcome else {
    return
  }
  presentWelcomeWindow(onStartCapture: onStartCapture, onOpenSettings: onOpenSettings)
}

@MainActor
private func openScreenRecordingSettings() {
  guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
    return
  }
  NSWorkspace.shared.open(url)
  NSApp.activate(ignoringOtherApps: true)
}

@MainActor
private struct VivyShotWelcomeView: View {
  @ObservedObject var settings: AppSettings
  @State var screenRecordingAllowed: Bool

  let onStartCapture: () -> Void
  let onOpenSettings: () -> Void
  let onOpenScreenRecordingSettings: () -> Void

  var body: some View {
    VStack(spacing: 26) {
      header
      featureList
      shortcutHero

      if !screenRecordingAllowed {
        screenRecordingPermissionRow
      }

      Spacer(minLength: 10)
      actionRow
    }
    .padding(.horizontal, 40)
    .padding(.top, 42)
    .padding(.bottom, 48)
    .onAppear {
      screenRecordingAllowed = CGPreflightScreenCaptureAccess()
    }
  }

  private var header: some View {
    VStack(spacing: 14) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)

      VStack(spacing: 6) {
        Text(localized("Welcome to VivyShot"))
          .font(.system(.largeTitle, design: .rounded).weight(.bold))
          .multilineTextAlignment(.center)

        Text(localized("Capture screenshots and recordings from the menu bar or with one shortcut."))
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var shortcutHero: some View {
    VStack(spacing: 10) {
      Text(settings.captureShortcutDisplay)
        .font(.system(size: 38, weight: .semibold, design: .rounded))
        .monospaced()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityLabel(localized("Capture Shortcut"))

      Text(localized("Press anywhere to capture a region."))
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .padding(.horizontal, 18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }

  private var featureList: some View {
    VStack(spacing: 16) {
      WelcomeFeatureRow(
        systemImage: "camera.viewfinder",
        title: localized("Capture"),
        detail: localized("Select a region, window, or screen.")
      )
      WelcomeFeatureRow(
        systemImage: "pencil.and.outline",
        title: localized("Edit"),
        detail: localized("Annotate screenshots or prepare recordings.")
      )
      WelcomeFeatureRow(
        systemImage: "square.and.arrow.up",
        title: localized("Share"),
        detail: localized("Copy, save, or export when you are done.")
      )
    }
  }

  private var screenRecordingPermissionRow: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.orange)
        .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 3) {
        Text(localized("Screen Recording Permission"))
          .font(.callout.weight(.semibold))
        Text(localized("Needed before VivyShot can capture your screen."))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button(localized("Open System Settings")) {
        onOpenScreenRecordingSettings()
        screenRecordingAllowed = CGPreflightScreenCaptureAccess()
      }
      .controlSize(.regular)
    }
    .padding(12)
    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.orange.opacity(0.22), lineWidth: 1)
    )
  }

  private var actionRow: some View {
    VStack(spacing: 10) {
      Button {
        onStartCapture()
      } label: {
        Text(localized("Start Capture"))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .frame(width: 280)
      .keyboardShortcut(.defaultAction)

      Button {
        onOpenSettings()
      } label: {
        Text(localized("Settings"))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .frame(width: 280)
    }
    .font(.body.weight(.semibold))
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private func localized(_ key: String) -> String {
    AppLocalizer.shared.string(key)
  }
}

@MainActor
private struct WelcomeFeatureRow: View {
  let systemImage: String
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .center, spacing: 13) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
  }
}
