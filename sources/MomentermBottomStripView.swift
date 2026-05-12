//
//  MomentermBottomStripView.swift
//  iTerm2
//
//  Slim bar pinned to the very bottom of the terminal window. Hosts the
//  toggle entries for the inline panels (Git Graph, Browser). Buttons
//  use frame + autoresizingMask so the strip respects the project rule
//  against auto layout in the terminal window.
//

import AppKit

@objc(MomentermBottomStripDelegate)
protocol MomentermBottomStripDelegate: AnyObject {
    func momentermBottomStripDidTapGitGraph()
    func momentermBottomStripDidTapBrowser()
}

@objc(MomentermBottomStripView)
final class MomentermBottomStripView: NSView {

    @objc weak var delegate: MomentermBottomStripDelegate?

    private let topLine = NSView()
    private let graphButton = NSButton()
    private let browserButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        topLine.wantsLayer = true
        topLine.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        addSubview(topLine)

        configure(button: graphButton,
                  symbolName: "point.3.connected.trianglepath.dotted",
                  title: "Git Graph",
                  selector: #selector(graphTapped))
        configure(button: browserButton,
                  symbolName: "globe",
                  title: "Browser",
                  selector: #selector(browserTapped))
        addSubview(graphButton)
        addSubview(browserButton)

        layoutContents()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    private func configure(button: NSButton, symbolName: String, title: String, selector: Selector) {
        let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.image = symbolImage?.withSymbolConfiguration(symbolConfig)
        button.title = title
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = selector
        button.toolTip = title
        button.alignment = .left
    }

    override func layout() {
        super.layout()
        layoutContents()
    }

    private func layoutContents() {
        let h = bounds.height
        topLine.frame = NSRect(x: 0, y: h - 0.5, width: bounds.width, height: 0.5)
        // Left-anchored buttons sized to their intrinsic content.
        let buttonH: CGFloat = h - 8
        let buttonY: CGFloat = 4
        let leftMargin: CGFloat = 10
        let gap: CGFloat = 12
        let graphSize = graphButton.intrinsicContentSize
        let browserSize = browserButton.intrinsicContentSize
        let graphW = max(72, graphSize.width + 8)
        let browserW = max(72, browserSize.width + 8)
        graphButton.frame = NSRect(x: leftMargin, y: buttonY, width: graphW, height: buttonH)
        browserButton.frame = NSRect(x: leftMargin + graphW + gap, y: buttonY, width: browserW, height: buttonH)
    }

    /// Mark which inline panel is currently visible so the button shows an
    /// "on" tint. Pass an empty string to clear both.
    @objc func setActivePanel(_ panel: String) {
        graphButton.contentTintColor = (panel == "gitgraph") ? .controlAccentColor : .secondaryLabelColor
        browserButton.contentTintColor = (panel == "browser") ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func graphTapped() { delegate?.momentermBottomStripDidTapGitGraph() }
    @objc private func browserTapped() { delegate?.momentermBottomStripDidTapBrowser() }
}
