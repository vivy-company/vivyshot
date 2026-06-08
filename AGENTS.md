# AGENTS.md

## Mission

Build VivyShot as a Swift-first, native macOS screen capture and editing app.

## Product Goals

- Keep VivyShot focused on macOS.
- Use Swift, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, and other Apple frameworks directly.
- Keep capture, annotation, recording, review, export, settings, and store behavior owned by the macOS app.
- Do not plan for non-macOS surfaces, alternate-language cores, generated native bridges, or stable C integration layers.

## Licensing Goals

- App sources: GPL-3.0-only.
- App Store binaries: Apple App Store EULA + VivyShot binary terms (`LICENSE-APPSTORE.md`).

## Distribution And Commercial Goals

- Official macOS distribution is available through the App Store:
  https://apps.apple.com/us/app/id6760658121
- The App Store app uses a free base app with one-time in-app purchases.

## Agent Working Rules

- Keep repo messaging aligned with the Swift-only macOS direction above.
- Do not introduce alternate-language core, generated bridge, or future non-macOS platform claims unless explicitly requested.
- Prefer direct Apple framework integration over proxy layers for native capture, recording, editing, and export behavior.
- Keep CI, governance, legal docs, README copy, and website copy consistent with the macOS-only product strategy.

## Greenfield Policy

- VivyShot is currently a greenfield, pre-1.0 project.
- Breaking changes are acceptable across data fields, APIs, and internal architecture when they improve the product.
- Do not preserve backward compatibility by default.
- Do not add compatibility shims, migration layers, or deprecation overhead unless explicitly requested.
- Optimize for the best long-term native macOS design rather than legacy constraints.
