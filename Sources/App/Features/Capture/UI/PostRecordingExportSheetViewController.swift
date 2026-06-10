import AppKit

@MainActor
final class PostRecordingExportSheetViewController: NSViewController {
  private let storeManager: StoreManager
  private var target: PostRecordingExportSheetTarget = .video
  private var options: PostRecordingExportOptions
  private let onCancel: () -> Void
  private let onSave: (PostRecordingExportOptions) -> Void
  private let onSaveGIF: () -> Void

  private let contentWidth: CGFloat = 360
  private let labelWidth: CGFloat = 112
  private let controlWidth: CGFloat = 190
  private let formStack = NSStackView()

  private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let codecPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let frameRatePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let scalePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let bitratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let primaryButton = NSButton()

  init(
    initialOptions: PostRecordingExportOptions,
    storeManager: StoreManager,
    onCancel: @escaping () -> Void,
    onSave: @escaping (PostRecordingExportOptions) -> Void,
    onSaveGIF: @escaping () -> Void
  ) {
    self.storeManager = storeManager
    self.options = initialOptions
    self.onCancel = onCancel
    self.onSave = onSave
    self.onSaveGIF = onSaveGIF
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let rootView = NSView(frame: CGRect(origin: .zero, size: contentSize))
    rootView.wantsLayer = true
    rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view = rootView

    configurePopups()
    configureButtons()

    let rootStack = NSStackView()
    rootStack.orientation = .vertical
    rootStack.alignment = .leading
    rootStack.spacing = 16
    rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 18, right: 24)
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(rootStack)

    let titleLabel = NSTextField(labelWithString: String(localized: "Export Recording", bundle: AppLocalizer.shared.bundle))
    titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
    titleLabel.textColor = .labelColor

    let detailLabel = NSTextField(labelWithString: String(localized: "Choose how this recording should be exported.", bundle: AppLocalizer.shared.bundle))
    detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byWordWrapping
    detailLabel.maximumNumberOfLines = 2
    detailLabel.preferredMaxLayoutWidth = contentWidth

    let headerStack = NSStackView(views: [titleLabel, detailLabel])
    headerStack.orientation = .vertical
    headerStack.alignment = .leading
    headerStack.spacing = 3
    headerStack.translatesAutoresizingMaskIntoConstraints = false
    headerStack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    rootStack.addArrangedSubview(headerStack)

    formStack.orientation = .vertical
    formStack.alignment = .leading
    formStack.spacing = 8
    formStack.translatesAutoresizingMaskIntoConstraints = false
    formStack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    rootStack.addArrangedSubview(formStack)

    let buttonRow = NSStackView()
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 8
    buttonRow.translatesAutoresizingMaskIntoConstraints = false
    buttonRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let cancelButton = NSButton(
      title: String(localized: "Cancel", bundle: AppLocalizer.shared.bundle),
      target: self,
      action: #selector(cancelButtonPressed)
    )
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"

    buttonRow.addArrangedSubview(spacer)
    buttonRow.addArrangedSubview(cancelButton)
    buttonRow.addArrangedSubview(primaryButton)
    rootStack.addArrangedSubview(buttonRow)

    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: rootView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
    ])

    rebuildFormRows()
    preferredContentSize = contentSize
  }

  private var gifFormatTitle: String {
    canUse(PostRecordingExportTarget.gif.paidFeature)
      ? String(localized: "GIF", bundle: AppLocalizer.shared.bundle)
      : String(localized: "GIF (Pro)", bundle: AppLocalizer.shared.bundle)
  }

  private var exportButtonTitle: String {
    switch target {
    case .video:
      return String(localized: "Export", bundle: AppLocalizer.shared.bundle)
    case .gif:
      return canUse(PostRecordingExportTarget.gif.paidFeature)
        ? String(localized: "Export GIF", bundle: AppLocalizer.shared.bundle)
        : String(localized: "Export GIF (Pro)", bundle: AppLocalizer.shared.bundle)
    }
  }

  private var contentSize: CGSize {
    switch target {
    case .video:
      return CGSize(width: 408, height: 318)
    case .gif:
      return CGSize(width: 408, height: 284)
    }
  }

  private func configurePopups() {
    configurePopup(
      formatPopup,
      titles: [String(localized: "Video", bundle: AppLocalizer.shared.bundle), gifFormatTitle],
      selectedIndex: 0,
      action: #selector(formatChanged)
    )
    configurePopup(
      codecPopup,
      titles: PostRecordingExportCodec.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportCodec.allCases.firstIndex(of: options.codec) ?? 0,
      action: #selector(codecChanged)
    )
    configurePopup(
      frameRatePopup,
      titles: PostRecordingExportFrameRate.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportFrameRate.allCases.firstIndex(of: options.frameRate) ?? 0,
      action: #selector(frameRateChanged)
    )
    configurePopup(
      qualityPopup,
      titles: PostRecordingExportQuality.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportQuality.allCases.firstIndex(of: options.quality) ?? 0,
      action: #selector(qualityChanged)
    )
    configurePopup(
      scalePopup,
      titles: PostRecordingExportScale.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportScale.allCases.firstIndex(of: options.scale) ?? 0,
      action: #selector(scaleChanged)
    )
    configurePopup(
      bitratePopup,
      titles: PostRecordingExportBitratePreset.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportBitratePreset.allCases.firstIndex(of: options.bitrate) ?? 0,
      action: #selector(bitrateChanged)
    )
  }

  private func configurePopup(_ popup: NSPopUpButton, titles: [String], selectedIndex: Int, action: Selector) {
    popup.removeAllItems()
    popup.addItems(withTitles: titles)
    popup.selectItem(at: selectedIndex)
    popup.target = self
    popup.action = action
    popup.controlSize = .regular
    popup.bezelStyle = .rounded
    popup.translatesAutoresizingMaskIntoConstraints = false
    popup.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
  }

  private func configureButtons() {
    primaryButton.title = exportButtonTitle
    primaryButton.target = self
    primaryButton.action = #selector(exportButtonPressed)
    primaryButton.bezelStyle = .rounded
    primaryButton.keyEquivalent = "\r"
  }

  private func rebuildFormRows() {
    for row in formStack.arrangedSubviews {
      formStack.removeArrangedSubview(row)
      row.removeFromSuperview()
    }

    formStack.addArrangedSubview(formRow(label: "Format", control: formatPopup))

    switch target {
    case .video:
      formStack.addArrangedSubview(formRow(label: "Codec", control: codecPopup))
      formStack.addArrangedSubview(formRow(label: "Frame Rate", control: frameRatePopup))
      formStack.addArrangedSubview(formRow(label: "Quality", control: qualityPopup))
      formStack.addArrangedSubview(formRow(label: "Scale", control: scalePopup))
      formStack.addArrangedSubview(formRow(label: "Bitrate", control: bitratePopup))
    case .gif:
      formStack.addArrangedSubview(formRow(label: "Type", control: valueLabel("Animated GIF")))
      formStack.addArrangedSubview(formRow(label: "Frame Rate", control: valueLabel("12 fps", localized: false)))
      formStack.addArrangedSubview(formRow(label: "Max Size", control: valueLabel("960 px", localized: false)))
      formStack.addArrangedSubview(formRow(label: "Audio", control: valueLabel("No audio")))
    }
  }

  private func formRow(label key: String, control: NSView) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = 14
    row.translatesAutoresizingMaskIntoConstraints = false

    let label = NSTextField(labelWithString: String(localized: String.LocalizationValue(key), bundle: AppLocalizer.shared.bundle))
    label.alignment = .right
    label.font = .systemFont(ofSize: NSFont.systemFontSize)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

    row.addArrangedSubview(label)
    row.addArrangedSubview(control)
    row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    return row
  }

  private func valueLabel(_ key: String, localized: Bool = true) -> NSTextField {
    let title = localized ? String(localized: String.LocalizationValue(key), bundle: AppLocalizer.shared.bundle) : key
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize)
    label.textColor = .labelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
    return label
  }

  private func updateContentSize() {
    let size = contentSize
    preferredContentSize = size
    view.setFrameSize(size)
    view.window?.setContentSize(size)
  }

  @objc
  private func cancelButtonPressed() {
    onCancel()
  }

  @objc
  private func exportButtonPressed() {
    switch target {
    case .video:
      onSave(options)
    case .gif:
      onSaveGIF()
    }
  }

  @objc
  private func formatChanged() {
    target = formatPopup.indexOfSelectedItem == 1 ? .gif : .video
    primaryButton.title = exportButtonTitle
    rebuildFormRows()
    updateContentSize()
  }

  @objc
  private func codecChanged() {
    let values = PostRecordingExportCodec.allCases
    guard values.indices.contains(codecPopup.indexOfSelectedItem) else {
      return
    }
    options.codec = values[codecPopup.indexOfSelectedItem]
  }

  @objc
  private func frameRateChanged() {
    let values = PostRecordingExportFrameRate.allCases
    guard values.indices.contains(frameRatePopup.indexOfSelectedItem) else {
      return
    }
    options.frameRate = values[frameRatePopup.indexOfSelectedItem]
  }

  @objc
  private func qualityChanged() {
    let values = PostRecordingExportQuality.allCases
    guard values.indices.contains(qualityPopup.indexOfSelectedItem) else {
      return
    }
    options.quality = values[qualityPopup.indexOfSelectedItem]
  }

  @objc
  private func scaleChanged() {
    let values = PostRecordingExportScale.allCases
    guard values.indices.contains(scalePopup.indexOfSelectedItem) else {
      return
    }
    options.scale = values[scalePopup.indexOfSelectedItem]
  }

  @objc
  private func bitrateChanged() {
    let values = PostRecordingExportBitratePreset.allCases
    guard values.indices.contains(bitratePopup.indexOfSelectedItem) else {
      return
    }
    options.bitrate = values[bitratePopup.indexOfSelectedItem]
  }

  private func menuTitle(for codec: PostRecordingExportCodec) -> String {
    proMenuTitle(codec.title, feature: codec.paidFeature)
  }

  private func menuTitle(for frameRate: PostRecordingExportFrameRate) -> String {
    proMenuTitle(frameRate.title, feature: frameRate.paidFeature)
  }

  private func menuTitle(for quality: PostRecordingExportQuality) -> String {
    proMenuTitle(quality.title, feature: quality.paidFeature)
  }

  private func menuTitle(for scale: PostRecordingExportScale) -> String {
    scale.title
  }

  private func menuTitle(for bitrate: PostRecordingExportBitratePreset) -> String {
    proMenuTitle(bitrate.title, feature: bitrate.paidFeature)
  }

  private func proMenuTitle(_ title: String, feature: PaidFeature?) -> String {
    guard !canUse(feature) else {
      return title
    }
    return String(format: String(localized: "%@ (Pro)", bundle: AppLocalizer.shared.bundle), title)
  }

  private func canUse(_ feature: PaidFeature?) -> Bool {
    guard let feature else {
      return true
    }
    return storeManager.canUse(feature)
  }
}
