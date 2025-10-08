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

        // Create the title label for toolbar use
        let label = NSTextField(labelWithString: "AI Chat")
        // Match the font size of our popup buttons (20pt)
        label.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
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
        sessionButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        sessionButton.translatesAutoresizingMaskIntoConstraints = false
        sessionButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sessionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        do {
            let webSearchButton = WebSearchButton(image: NSImage.it_image(forSymbolName: SFSymbol.globe.rawValue,
                                                                          accessibilityDescription: "Web search image",
                                                                          fallbackImageName: "globe",
                                                                          for: Self.self),
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
            webSearchButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            webSearchButton.translatesAutoresizingMaskIntoConstraints = false
            webSearchButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            webSearchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
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
            thinkingButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            thinkingButton.translatesAutoresizingMaskIntoConstraints = false
            thinkingButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            thinkingButton.setContentCompressionResistancePriority(.required, for: .horizontal)
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

extension ChatToolbar {
    @available(macOS 26, *)
    func createFloatingView() -> NSView {
        // Constants for control sizing
        let controlHeight: CGFloat = 22
        let buttonMinWidth: CGFloat = 22

        // Create all controls
        var controls: [NSView] = []

        // Title label
        controls.append(titleLabel)

        // AI controls
        var baselineAlignedViews = [NSView]()
        if let modelSelectorButton {
            modelSelectorButton.controlSize = .large
            modelSelectorButton.translatesAutoresizingMaskIntoConstraints = false
            baselineAlignedViews.append(modelSelectorButton)
            NSLayoutConstraint.activate([
                modelSelectorButton.heightAnchor.constraint(equalToConstant: controlHeight),
                modelSelectorButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)  // Wider for text
            ])
            controls.append(modelSelectorButton)
        }
        if let thinkingButton {
            thinkingButton.controlSize = .large
            thinkingButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                thinkingButton.heightAnchor.constraint(equalToConstant: controlHeight),
                thinkingButton.widthAnchor.constraint(greaterThanOrEqualToConstant: buttonMinWidth)
            ])
            controls.append(thinkingButton)
        }
        if let webSearchButton {
            webSearchButton.controlSize = .large
            webSearchButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webSearchButton.heightAnchor.constraint(equalToConstant: controlHeight),
                webSearchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: buttonMinWidth)
            ])
            controls.append(webSearchButton)
        }
        if let sessionButton {
            sessionButton.controlSize = .large
            sessionButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                sessionButton.heightAnchor.constraint(equalToConstant: controlHeight),
                sessionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: buttonMinWidth)
            ])
            controls.append(sessionButton)
        }

        // Create horizontal stack
        let stackView = NSStackView(views: controls)
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.distribution = .gravityAreas  // Let controls size naturally
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Create a container view to hold the stack with proper padding
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)

        // Add constraints to create padding
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])

        // Add vertical alignment constraints
        NSLayoutConstraint.activate(baselineAlignedViews.map { view in
            view.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor)
        })

        // Create glass effect view to wrap the container
        let glassView = NSGlassEffectView()
        glassView.contentView = containerView
        glassView.cornerRadius = 20
        glassView.translatesAutoresizingMaskIntoConstraints = false
        return glassView
    }

    func createOrUpdateModelSelector() {
        modelSelectorButton?.removeAllItems()

        // Create new model selector if multiple models are available
        let availableModels = AITermController.allProvidersForCurrentVendor.map({ $0.model })
        let modelSelector = modelSelectorButton ?? NSPopUpButton()
        modelSelectorButton = modelSelector
        modelSelector.translatesAutoresizingMaskIntoConstraints = false
        modelSelector.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        modelSelector.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        modelSelector.target = self
        modelSelector.action = #selector(selectModel(_:))

        // Use a minimal, borderless style
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
