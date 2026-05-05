//
//  ChatToolbar.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/25/25.
//

import Foundation

@objc class WebSearchButton: NSButton { }
@objc class ThinkingButton: NSButton { }

protocol ChatToolbarDataSource: AnyObject {
    var provider: LLMProvider? { get }
    var webSearchEnabled: Bool { get }
    var thinkingEnabled: Bool { get }
    var effectiveModel: String? { get }

    func showSessionButtonMenu(_ sender: NSButton)
    func toggleWebSearch()
    func toggleThinking()
    func toolbarDidUpdate()
    func selectedModelDidChange()
}

class ChatToolbar {
    private(set) var modelSelectorButton: NSPopUpButton?
    private(set) var sessionButton: NSButton!
    private(set) var webSearchButton: WebSearchButton?
    private(set) var thinkingButton: ThinkingButton?
    private(set) var titleLabel: NSTextField!

    private let userDefaultsObserver = iTermUserDefaultsObserver()

    weak var dataSource: ChatToolbarDataSource?

    init(dataSource: ChatToolbarDataSource) {
        self.dataSource = dataSource

        let label = NSTextField(labelWithString: "AI Chat")
        label.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        self.titleLabel = label

        do {
            let image = NSImage(systemSymbolName: SFSymbol.infoCircle.rawValue, accessibilityDescription: nil)!
            sessionButton = NSButton(image: image, target: nil, action: nil)
            sessionButton.imageScaling = .scaleProportionallyUpOrDown
            sessionButton.controlSize = .large
            sessionButton.isBordered = false
        }

        sessionButton.bezelStyle = .badge
        sessionButton.isBordered = false
        sessionButton.target = self
        sessionButton.action = #selector(showSessionButtonMenu(_:))
        sessionButton.sizeToFit()

        do {
            let webSearchButton = WebSearchButton(image: NSImage.it_image(forSymbolName: SFSymbol.globe.rawValue,
                                                                          accessibilityDescription: "Web search image",
                                                                          fallbackImageName: "globe",
                                                                          for: Self.self)!,
                                                  target: nil,
                                                  action: nil)
            webSearchButton.imageScaling = .scaleProportionallyUpOrDown
            webSearchButton.controlSize = .large
            webSearchButton.contentTintColor = dataSource.webSearchEnabled ? .controlAccentColor : nil
            webSearchButton.isBordered = false
            webSearchButton.bezelStyle = .badge
            webSearchButton.isBordered = false
            webSearchButton.target = self
            webSearchButton.action = #selector(toggleWebSearch(_:))
            webSearchButton.sizeToFit()
            webSearchButton.toolTip = "Allow AI to perform web search?"
            self.webSearchButton = webSearchButton
            webSearchButton.isEnabled = (dataSource.provider?.supportsHostedWebSearch == true)
        }

        do {
            let smallerConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)

            let image = NSImage(
                systemSymbolName: SFSymbol.lightbulb.rawValue,
                accessibilityDescription: "Enable high-effort reasoning?")?.withSymbolConfiguration(smallerConfig)
            let thinkingButton = ThinkingButton(image: image!,
                                                  target: nil,
                                                action: nil)
            thinkingButton.imageScaling = .scaleNone
            thinkingButton.controlSize = .large
            thinkingButton.contentTintColor = dataSource.thinkingEnabled ? .controlAccentColor : nil
            thinkingButton.isBordered = false
            thinkingButton.bezelStyle = .badge
            thinkingButton.isBordered = false
            thinkingButton.target = self
            thinkingButton.action = #selector(toggleThinking(_:))
            thinkingButton.sizeToFit()
            thinkingButton.toolTip = "Enable high-effort reasoning? Slower but may produce better results."
            self.thinkingButton = thinkingButton
            thinkingButton.isEnabled = (dataSource.provider?.model.features.contains(.configurableThinking) == true)
        }
        createOrUpdateModelSelector()

        userDefaultsObserver.observeKey(kPreferenceKeyAIFeatureHostedWebSearch) { [weak self] in
            self?.update()
        }
        userDefaultsObserver.observeKey(kPreferenceKeyUseRecommendedAIModel) { [weak self] in
            self?.update()
        }
        userDefaultsObserver.observeKey(kPreferenceKeyAIVendor) { [weak self] in
            self?.update()
        }
        update()
    }
}

// Container for the macOS 26 floating bar. Hosts a translucent NSVisualEffect
// background plus a manually-laid-out row of controls. Replaces the previous
// NSGlassEffectView+NSStackView constraint-driven implementation so the chat
// UI is auto-layout-free.
final class FloatingChatToolbarView: NSView {
    static let controlHeight: CGFloat = 22
    static let buttonMinWidth: CGFloat = 22
    static let modelSelectorMinWidth: CGFloat = 120
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 20

    private let backdrop: NSVisualEffectView
    private let row: ChatManualStackView
    private let titleLabel: NSTextField
    private let modelSelectorButton: NSPopUpButton?
    private let thinkingButton: NSButton?
    private let webSearchButton: NSButton?
    private let sessionButton: NSButton?

    private let layoutJoiner = IdempotentOperationJoiner.asyncJoiner(.main)

    func setNeedsLayoutNow() {
        layoutJoiner.setNeedsUpdate { [weak self] in
            self?.performLayoutNow()
        }
    }

    init(titleLabel: NSTextField,
         modelSelectorButton: NSPopUpButton?,
         thinkingButton: NSButton?,
         webSearchButton: NSButton?,
         sessionButton: NSButton?) {
        self.titleLabel = titleLabel
        self.modelSelectorButton = modelSelectorButton
        self.thinkingButton = thinkingButton
        self.webSearchButton = webSearchButton
        self.sessionButton = sessionButton

        backdrop = NSVisualEffectView()
        backdrop.wantsLayer = true
        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active

        row = ChatManualStackView(orientation: .horizontal,
                                  spacing: 12,
                                  alignment: .center)

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true

        addSubview(backdrop)
        addSubview(row)

        row.addArrangedSubview(titleLabel)
        if let modelSelectorButton {
            modelSelectorButton.controlSize = .large
            row.addArrangedSubview(modelSelectorButton)
        }
        if let thinkingButton {
            thinkingButton.controlSize = .large
            row.addArrangedSubview(thinkingButton)
        }
        if let webSearchButton {
            webSearchButton.controlSize = .large
            row.addArrangedSubview(webSearchButton)
        }
        if let sessionButton {
            sessionButton.controlSize = .large
            row.addArrangedSubview(sessionButton)
        }

        // Override per-control sizing so the row reads the same minimums the
        // old constraint cascade enforced.
        row.sizeOverride = { [weak self] view, _ in
            guard let self else { return nil }
            if view === self.modelSelectorButton {
                let intrinsic = view.intrinsicContentSize
                return NSSize(width: max(Self.modelSelectorMinWidth, intrinsic.width),
                              height: Self.controlHeight)
            }
            if view === self.thinkingButton ||
               view === self.webSearchButton ||
               view === self.sessionButton {
                let intrinsic = view.intrinsicContentSize
                return NSSize(width: max(Self.buttonMinWidth, intrinsic.width),
                              height: Self.controlHeight)
            }
            // Title label: use intrinsic for both axes.
            return nil
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    // Manual-layout helper (don't override intrinsicContentSize — it would
    // activate the constraint engine for the surrounding view tree).
    func preferredSize() -> NSSize {
        let rowSize = row.fittingSize(crossAxisLimit: Self.controlHeight)
        let height = max(Self.controlHeight, rowSize.height) + Self.verticalPadding * 2
        let width = rowSize.width + Self.horizontalPadding * 2
        return NSSize(width: width, height: height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            setNeedsLayoutNow()
        }
    }

    override func layout() {
        super.layout()
        performLayoutNow()
    }

    private func performLayoutNow() {
        let backdropFrame = bounds
        if backdrop.frame != backdropFrame {
            backdrop.frame = backdropFrame
        }
        let rowX = Self.horizontalPadding
        let rowY = Self.verticalPadding
        let rowWidth = max(0, bounds.width - Self.horizontalPadding * 2)
        let rowHeight = max(0, bounds.height - Self.verticalPadding * 2)
        let rowFrame = NSRect(x: rowX, y: rowY, width: rowWidth, height: rowHeight)
        if row.frame != rowFrame {
            row.frame = rowFrame
        }
    }
}

extension ChatToolbar {
    @available(macOS 26, *)
    func createFloatingView() -> NSView {
        return FloatingChatToolbarView(titleLabel: titleLabel,
                                       modelSelectorButton: modelSelectorButton,
                                       thinkingButton: thinkingButton,
                                       webSearchButton: webSearchButton,
                                       sessionButton: sessionButton)
    }

    func createOrUpdateModelSelector() {
        modelSelectorButton?.removeAllItems()

        let availableModels = AITermController.allProvidersForCurrentVendor.map({ $0.model })
        let modelSelector = modelSelectorButton ?? NSPopUpButton()
        modelSelectorButton = modelSelector
        modelSelector.target = self
        modelSelector.action = #selector(selectModel(_:))

        modelSelector.isBordered = false
        modelSelector.bezelStyle = .inline
        modelSelector.font = NSFont.systemFont(ofSize: 16)

        for model in availableModels {
            modelSelector.addItem(withTitle: model.name)
            modelSelector.lastItem?.representedObject = model.name
        }

        if let selectedModel = dataSource?.effectiveModel {
            modelSelector.selectItem(withTitle: selectedModel)
        }
    }

    func update() {
        let provider = dataSource?.provider
        webSearchButton?.isEnabled = provider?.supportsHostedWebSearch == true
        thinkingButton?.isEnabled = (provider?.model.features.contains(.configurableThinking) == true)
        createOrUpdateModelSelector()

        dataSource?.toolbarDidUpdate()
    }

    var selectedModelIdentifier: String? {
        return modelSelectorButton?.selectedItem?.representedObject as? String
    }

    @objc private func showSessionButtonMenu(_ sender: NSButton) {
        dataSource?.showSessionButtonMenu(sender)
    }

    @objc private func toggleWebSearch(_ sender: Any) {
        dataSource?.toggleWebSearch()
        webSearchButton?.contentTintColor = dataSource?.webSearchEnabled == true ? .controlAccentColor : nil
    }

    @objc private func toggleThinking(_ sender: Any) {
        dataSource?.toggleThinking()
        thinkingButton?.contentTintColor = dataSource?.thinkingEnabled == true ? .controlAccentColor : nil
    }

    @objc private func selectModel(_ sender: Any?)  {
        dataSource?.selectedModelDidChange()
        update()
    }
}
