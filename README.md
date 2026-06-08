# VivyShot

[![macOS](https://img.shields.io/badge/macOS-15.2+-black?style=flat-square&logo=apple)](#requirements)
[![Website](https://img.shields.io/badge/Website-vivyshot.com-0a66c2?style=flat-square)](https://vivyshot.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS License](https://img.shields.io/badge/macOS-GPL%203.0-blue?style=flat-square)](LICENSE-GPL-3.0)
[![Binary License](https://img.shields.io/badge/Binary-App%20Store%20EULA-6e7681?style=flat-square)](LICENSE-APPSTORE.md)
[![App Store](https://img.shields.io/badge/App%20Store-Download-0a84ff?style=flat-square&logo=appstore&logoColor=white)](https://apps.apple.com/us/app/id6760658121)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ff69b4?style=flat-square&logo=github)](https://github.com/sponsors/vivy-company)

Open source screen capture, annotation, and recording software built as a native Swift macOS app.

![VivyShot screenshot](web/public/screenshot.png)

## What Is VivyShot?

VivyShot is a focused screenshot and recording tool for people who want to capture something, mark it up, copy it, and move on. It is built directly on Apple frameworks so the capture, editing, and export flow can stay native, simple, and maintainable.

The product direction is straightforward:

- Keep the workflow simple and keyboard-friendly.
- Keep the UI native to macOS.
- Keep the project open source and inspectable.
- Keep pricing simple: free forever for the core workflow, with one-time upgrades instead of a subscription.

## Features

### Capture
- Area, window, and full-screen capture
- Screenshot and short recording workflows
- Keyboard-first flow, including quick copy/share actions

### Editing
- Shapes, arrows, paint, and text tools
- Blur and pixelate tools for cleanup and redaction
- Fast export to clipboard, PNG, and JPEG
- Recording options for audio and input overlays

### Architecture
- Native macOS app in SwiftUI and AppKit
- Direct integration with ScreenCaptureKit, AVFoundation, CoreGraphics, and ImageIO
- App-owned annotation, recording, review, export, settings, and store behavior

## Distribution And Pricing

- Official macOS distribution is available through Apple's App Store: <https://apps.apple.com/us/app/id6760658121>
- Pricing direction:
  - Free forever for the core workflow
  - Lifetime unlock: `$9.99` one-time
  - Supporter: `$24.99` one-time, with the same full unlock plus a small in-app supporter badge
- No subscription.
- App Store binary license terms are documented in `LICENSE-APPSTORE.md`.

## Requirements

- macOS 15.2+
- Xcode 16.0+

## Build From Source

```bash
git clone https://github.com/vivy-company/vivyshot.git
cd vivyshot

# Open in Xcode.
open VivyShot.xcodeproj
```

## Test And CI Commands

```bash
xcodebuild -project VivyShot.xcodeproj -scheme VivyShot -configuration Debug -destination 'platform=macOS' build
plutil -lint Resources/*.lproj/Localizable.strings
```

## Repository Layout

```text
Sources/        # SwiftUI/AppKit macOS app sources
Resources/      # App assets, localizations, privacy, and StoreKit config
Config/         # Info.plist and entitlements
Tests/          # Unit tests
docs/           # Specs and engineering notes
web/            # VivyShot website
scripts/        # Development and release scripts
```

## Contributing

See `CONTRIBUTING.md` for contribution workflow and `CLA.md` for CLA signing requirements.

## Security

See `SECURITY.md` for vulnerability reporting guidelines.

## License

- Source code: GPL-3.0-only (`LICENSE-GPL-3.0`)
- Official App Store binaries: App Store EULA + VivyShot binary terms (`LICENSE-APPSTORE.md`)

If you obtain VivyShot via Apple's App Store, App Store EULA and binary terms apply to that binary distribution.
