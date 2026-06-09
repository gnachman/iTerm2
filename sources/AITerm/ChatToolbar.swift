//
//  ChatToolbar.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/25/25.
//

import Foundation

@objc class WebSearchButton: NSButton { }
@objc class ThinkingButton: NSButton { }

struct ChatProviderOption: Equatable {
    static let manualIdentifier = "manual"

    let identifier: String
    let title: String

    static func vendor(_ vendor: iTermAIVendor) -> ChatProviderOption {
        ChatProviderOption(identifier: vendorIdentifier(vendor),
                           title: vendorTitle(vendor))
    }

    static func manual() -> ChatProviderOption {
        ChatProviderOption(identifier: manualIdentifier,
                           title: "Manual Configs")
    }

    static func vendorIdentifier(_ vendor: iTermAIVendor) -> String {
        return "vendor:\(vendor.rawValue)"
    }

    static func vendor(from identifier: String) -> iTermAIVendor? {
        guard identifier.hasPrefix("vendor:"),
              let rawValue = UInt(identifier.dropFirst("vendor:".count)) else {
            return nil
        }
        return iTermAIVendor(rawValue: rawValue)
    }

    private static func vendorTitle(_ provider: iTermAIVendor) -> String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        case .deepSeek:
            return "DeepSeek"
        case .llama:
            return "Llama (Local)"
        case .apple:
            return "Apple"
        @unknown default:
            return "Provider"
        }
    }
}

protocol ChatToolbarDataSource: AnyObject {
    var provider: LLMProvider? { get }
    var availableProviderOptions: [ChatProviderOption] { get }
    var effectiveProviderIdentifier: String? { get }
    var canChangeProvider: Bool { get }
    var webSearchEnabled: Bool { get }
    var thinkingEnabled: Bool { get }
    var selectedReasoningEffort: ResponsesRequestBody.ReasoningOptions.Effort? { get }
    var selectedServiceTier: ResponsesRequestBody.ServiceTier? { get }
    var effectiveModel: String? { get }
    var availableModels: [AIMetadata.Model] { get }

    func showSessionButtonMenu(_ sender: NSButton)
    func toggleWebSearch()
    func toggleThinking()
    func toolbarDidUpdate()
    func selectedProviderDidChange()
    func selectedModelDidChange()
    func selectedReasoningEffortDidChange()
    func selectedServiceTierDidChange()
}

class ChatToolbar {
    private(set) var providerSelectorButton: NSPopUpButton?
    private(set) var modelSelectorButton: NSPopUpButton?
    private(set) var sessionButton: NSButton!
    private(set) var webSearchButton: WebSearchButton?
    private(set) var thinkingButton: ThinkingButton?
    private(set) var reasoningEffortButton: NSPopUpButton?
    private(set) var serviceTierButton: NSPopUpButton?
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
        createOrUpdateProviderSelector()
        createOrUpdateModelSelector()
        createOrUpdateReasoningEffortSelector()
        createOrUpdateServiceTierSelector()

        userDefaultsObserver.observeKey(kPreferenceKeyAIFeatureHostedWebSearch) { [weak self] in
            self?.update()
        }
        userDefaultsObserver.observeKey(kPreferenceKeyUseRecommendedAIModel) { [weak self] in
            self?.update()
        }
        userDefaultsObserver.observeKey(kPreferenceKeyAIVendor) { [weak self] in
            self?.update()
        }
        userDefaultsObserver.observeKey(ChatViewController.reasoningEffortUserDefaultsKey) { [weak self] in
            self?.update()
        }
        userDefaultsObserver.observeKey(ChatViewController.serviceTierUserDefaultsKey) { [weak self] in
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
    static let providerSelectorMinWidth: CGFloat = 96
    static let modelSelectorMinWidth: CGFloat = 120
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 20

    private let backdrop: NSVisualEffectView
    private let row: ChatManualStackView
    private let providerSelectorButton: NSPopUpButton?
    private let modelSelectorButton: NSPopUpButton?
    private let reasoningEffortButton: NSPopUpButton?
    private let serviceTierButton: NSPopUpButton?
    private let thinkingButton: NSButton?
    private let webSearchButton: NSButton?
    private let sessionButton: NSButton?

    private let layoutJoiner = IdempotentOperationJoiner.asyncJoiner(.main)

    func setNeedsLayoutNow() {
        layoutJoiner.setNeedsUpdate { [weak self] in
            self?.performLayoutNow()
        }
    }

    init(providerSelectorButton: NSPopUpButton?,
         modelSelectorButton: NSPopUpButton?,
         reasoningEffortButton: NSPopUpButton?,
         serviceTierButton: NSPopUpButton?,
         thinkingButton: NSButton?,
         webSearchButton: NSButton?,
         sessionButton: NSButton?) {
        self.providerSelectorButton = providerSelectorButton
        self.modelSelectorButton = modelSelectorButton
        self.reasoningEffortButton = reasoningEffortButton
        self.serviceTierButton = serviceTierButton
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

        if let providerSelectorButton {
            providerSelectorButton.controlSize = .large
            row.addArrangedSubview(providerSelectorButton)
        }
        if let modelSelectorButton {
            modelSelectorButton.controlSize = .large
            row.addArrangedSubview(modelSelectorButton)
        }
        if let reasoningEffortButton {
            reasoningEffortButton.controlSize = .large
            row.addArrangedSubview(reasoningEffortButton)
        }
        if let serviceTierButton {
            serviceTierButton.controlSize = .large
            row.addArrangedSubview(serviceTierButton)
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
            if view === self.providerSelectorButton {
                let intrinsic = view.intrinsicContentSize
                return NSSize(width: max(Self.providerSelectorMinWidth, intrinsic.width),
                              height: Self.controlHeight)
            }
            if view === self.modelSelectorButton {
                let intrinsic = view.intrinsicContentSize
                return NSSize(width: max(Self.modelSelectorMinWidth, intrinsic.width),
                              height: Self.controlHeight)
            }
            if view === self.reasoningEffortButton ||
               view === self.serviceTierButton {
                let intrinsic = view.intrinsicContentSize
                return NSSize(width: max(94, intrinsic.width),
                              height: Self.controlHeight)
            }
            if view === self.thinkingButton ||
               view === self.webSearchButton ||
               view === self.sessionButton {
                let intrinsic = view.intrinsicContentSize
                return NSSize(width: max(Self.buttonMinWidth, intrinsic.width),
                              height: Self.controlHeight)
            }
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
        return FloatingChatToolbarView(providerSelectorButton: providerSelectorButton,
                                       modelSelectorButton: modelSelectorButton,
                                       reasoningEffortButton: reasoningEffortButton,
                                       serviceTierButton: serviceTierButton,
                                       thinkingButton: thinkingButton,
                                       webSearchButton: webSearchButton,
                                       sessionButton: sessionButton)
    }

    func createOrUpdateProviderSelector() {
        let options = dataSource?.availableProviderOptions ?? []
        let selector = providerSelectorButton ?? NSPopUpButton()
        providerSelectorButton = selector
        selector.removeAllItems()
        selector.target = self
        selector.action = #selector(selectProvider(_:))
        selector.isBordered = false
        selector.bezelStyle = .inline
        selector.font = NSFont.systemFont(ofSize: 13)

        for option in options {
            selector.addItem(withTitle: option.title)
            selector.lastItem?.representedObject = option.identifier
        }

        selector.isHidden = options.count <= 1
        selector.isEnabled = !options.isEmpty && (dataSource?.canChangeProvider == true)
        selector.toolTip = selector.isEnabled
            ? "Select the AI provider for this chat before sending the first message."
            : "The provider is fixed after the first real message in a chat."
        if let selectedIdentifier = dataSource?.effectiveProviderIdentifier {
            select(selector, representedObject: selectedIdentifier)
        } else if !options.isEmpty {
            selector.selectItem(at: 0)
        }
    }

    func createOrUpdateModelSelector() {
        modelSelectorButton?.removeAllItems()

        let availableModels = dataSource?.availableModels ?? []
        let modelSelector = modelSelectorButton ?? NSPopUpButton()
        modelSelectorButton = modelSelector
        modelSelector.target = self
        modelSelector.action = #selector(selectModel(_:))
        modelSelector.toolTip = "Select a model for this chat. The provider is fixed after the chat is created."

        modelSelector.isBordered = false
        modelSelector.bezelStyle = .inline
        modelSelector.font = NSFont.systemFont(ofSize: 16)

        for model in availableModels {
            modelSelector.addItem(withTitle: model.name)
            modelSelector.lastItem?.representedObject = model.name
        }

        modelSelector.isEnabled = availableModels.count > 1
        modelSelector.toolTip = modelSelector.isEnabled
            ? "Select a model for this chat. Manual Configs chats can switch among saved manual models."
            : "Only one model is available for this chat."
        if let selectedModel = dataSource?.effectiveModel {
            modelSelector.selectItem(withTitle: selectedModel)
        } else if !availableModels.isEmpty {
            modelSelector.selectItem(at: 0)
        }
    }

    func createOrUpdateReasoningEffortSelector() {
        let selector = reasoningEffortButton ?? NSPopUpButton()
        reasoningEffortButton = selector
        selector.removeAllItems()
        selector.target = self
        selector.action = #selector(selectReasoningEffort(_:))
        selector.isBordered = false
        selector.bezelStyle = .inline
        selector.font = NSFont.systemFont(ofSize: 13)
        selector.toolTip = "Select reasoning effort for models that support it"

        let efforts = dataSource?.provider?.model.reasoningEfforts ?? []
        for effort in efforts {
            selector.addItem(withTitle: Self.reasoningEffortTitle(effort))
            selector.lastItem?.representedObject = effort.rawValue
        }
        selector.isHidden = efforts.isEmpty
        selector.isEnabled = !efforts.isEmpty
        if let selectedEffort = dataSource?.selectedReasoningEffort,
           efforts.contains(selectedEffort) {
            select(selector, representedObject: selectedEffort.rawValue)
        } else if !efforts.isEmpty {
            selector.selectItem(at: 0)
        }
    }

    func createOrUpdateServiceTierSelector() {
        let selector = serviceTierButton ?? NSPopUpButton()
        serviceTierButton = selector
        selector.removeAllItems()
        selector.target = self
        selector.action = #selector(selectServiceTier(_:))
        selector.isBordered = false
        selector.bezelStyle = .inline
        selector.font = NSFont.systemFont(ofSize: 13)
        selector.toolTip = "Select OpenAI service tier. Priority is faster; Flex is lower-cost and slower."

        let tiers = dataSource?.provider?.model.serviceTiers ?? []
        for tier in tiers {
            selector.addItem(withTitle: Self.serviceTierTitle(tier))
            selector.lastItem?.representedObject = tier.rawValue
        }
        selector.isHidden = tiers.isEmpty
        selector.isEnabled = !tiers.isEmpty
        let selectedTier = dataSource?.selectedServiceTier ?? .auto
        if tiers.contains(selectedTier) {
            select(selector, representedObject: selectedTier.rawValue)
        } else if !tiers.isEmpty {
            selector.selectItem(at: 0)
        }
    }

    func update() {
        let provider = dataSource?.provider
        webSearchButton?.isEnabled = provider?.supportsHostedWebSearch == true
        thinkingButton?.isEnabled = (provider?.model.features.contains(.configurableThinking) == true)
        thinkingButton?.contentTintColor = dataSource?.thinkingEnabled == true ? .controlAccentColor : nil
        createOrUpdateProviderSelector()
        createOrUpdateModelSelector()
        createOrUpdateReasoningEffortSelector()
        createOrUpdateServiceTierSelector()

        dataSource?.toolbarDidUpdate()
    }

    var selectedModelIdentifier: String? {
        return modelSelectorButton?.selectedItem?.representedObject as? String
    }

    var selectedProviderIdentifier: String? {
        return providerSelectorButton?.selectedItem?.representedObject as? String
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

    @objc private func selectProvider(_ sender: Any?) {
        dataSource?.selectedProviderDidChange()
        update()
    }

    @objc private func selectReasoningEffort(_ sender: Any?) {
        dataSource?.selectedReasoningEffortDidChange()
        update()
    }

    @objc private func selectServiceTier(_ sender: Any?) {
        dataSource?.selectedServiceTierDidChange()
        update()
    }

    private func select(_ selector: NSPopUpButton, representedObject: String) {
        for item in selector.itemArray where item.representedObject as? String == representedObject {
            selector.select(item)
            return
        }
    }

    private static func reasoningEffortTitle(_ effort: ResponsesRequestBody.ReasoningOptions.Effort) -> String {
        let value = switch effort {
        case .none: "None"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        }
        return "Effort: \(value)"
    }

    private static func serviceTierTitle(_ tier: ResponsesRequestBody.ServiceTier) -> String {
        let value = switch tier {
        case .auto: "Auto"
        case .default: "Standard"
        case .priority: "Priority (Fast)"
        case .flex: "Flex (Slow)"
        }
        return "Tier: \(value)"
    }
}
