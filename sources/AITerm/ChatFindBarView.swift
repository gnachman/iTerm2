//
//  ChatFindBarView.swift
//  iTerm2
//
//  The find bar shown at the top of the AI chat conversation for Cmd-F.
//  Manual frame layout (no auto layout). Styled to match the floating chat
//  toolbar (a hud-material pill) rather than the terminal session find bar.
//

import AppKit

protocol ChatFindBarViewDelegate: AnyObject {
    func chatFindBar(_ bar: ChatFindBarView,
                     didChangeQuery query: String,
                     mode: iTermFindMode)
    func chatFindBarFindNext(_ bar: ChatFindBarView)
    func chatFindBarFindPrevious(_ bar: ChatFindBarView)
    func chatFindBarClose(_ bar: ChatFindBarView)
}

class ChatFindBarView: NSView {
    // Match FloatingChatToolbarView: controlHeight 22 + verticalPadding 8*2.
    static let controlHeight: CGFloat = 22
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let barHeight: CGFloat = controlHeight + verticalPadding * 2

    weak var delegate: ChatFindBarViewDelegate?

    private let backdrop: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }()
    private let searchField = NSSearchField()
    private let counterLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let closeButton = NSButton()

    // Popup order must match this table.
    private static let modeOrder: [iTermFindMode] = [
        .smartCaseSensitivity,
        .caseInsensitiveSubstring,
        .caseSensitiveSubstring,
        .caseInsensitiveRegex,
    ]
    private static let modeTitles = [
        "Smart Case",
        "Ignore Case",
        "Match Case",
        "Regular Expression",
    ]

    private static let controlSpacing: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    var query: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    var mode: iTermFindMode {
        let index = modeButton.indexOfSelectedItem
        guard index >= 0, index < Self.modeOrder.count else {
            return .smartCaseSensitivity
        }
        return Self.modeOrder[index]
    }

    func selectMode(_ mode: iTermFindMode) {
        // Map both regex variants onto the single "Regular Expression" item.
        let normalized: iTermFindMode = (mode == .caseSensitiveRegex) ? .caseInsensitiveRegex : mode
        if let index = Self.modeOrder.firstIndex(of: normalized) {
            modeButton.selectItem(at: index)
        }
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func updateResults(current: Int?, total: Int) {
        if searchField.stringValue.isEmpty {
            counterLabel.stringValue = ""
        } else if total == 0 {
            counterLabel.stringValue = "No results"
        } else if let current {
            counterLabel.stringValue = "\(current + 1) of \(total)"
        } else {
            counterLabel.stringValue = "\(total)"
        }
        needsLayout = true
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = Self.barHeight / 2
        layer?.masksToBounds = true

        addSubview(backdrop)

        searchField.placeholderString = "Find in Conversation"
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        addSubview(searchField)

        // Same font as the search field so the counter shares its baseline
        // when both are vertically centered on the same line.
        counterLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        counterLabel.textColor = .secondaryLabelColor
        counterLabel.alignment = .right
        addSubview(counterLabel)

        configureChevron(previousButton,
                         symbol: SFSymbol.chevronUp,
                         accessibility: "Find Previous",
                         action: #selector(previousButtonClicked(_:)))
        addSubview(previousButton)

        configureChevron(nextButton,
                         symbol: SFSymbol.chevronDown,
                         accessibility: "Find Next",
                         action: #selector(nextButtonClicked(_:)))
        addSubview(nextButton)

        modeButton.addItems(withTitles: Self.modeTitles)
        modeButton.target = self
        modeButton.action = #selector(modeChanged(_:))
        modeButton.controlSize = .regular
        modeButton.bezelStyle = .roundRect
        modeButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        addSubview(modeButton)

        closeButton.image = NSImage.it_image(forSymbolName: SFSymbol.xmark.rawValue,
                                             accessibilityDescription: "Close find bar",
                                             fallbackImageName: "xmark",
                                             for: ChatFindBarView.self)
        closeButton.bezelStyle = .badge
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.refusesFirstResponder = true
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked(_:))
        addSubview(closeButton)
    }

    private func configureChevron(_ button: NSButton,
                                  symbol: SFSymbol,
                                  accessibility: String,
                                  action: Selector) {
        button.image = NSImage.it_image(forSymbolName: symbol.rawValue,
                                        accessibilityDescription: accessibility,
                                        fallbackImageName: symbol.rawValue,
                                        for: ChatFindBarView.self)
        button.bezelStyle = .badge
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        button.target = self
        button.action = action
    }

    override func layout() {
        super.layout()
        if backdrop.frame != bounds {
            backdrop.frame = bounds
        }
        let controlHeight = Self.controlHeight
        // Every control is centered on this line so the search field text and
        // the counter (which uses the same font) share a baseline.
        let lineCenterY = bounds.midY
        let centeredY = lineCenterY - controlHeight / 2
        var rightEdge = bounds.maxX - Self.horizontalPadding

        let closeSize = controlHeight
        closeButton.frame = NSRect(x: rightEdge - closeSize, y: centeredY,
                                   width: closeSize, height: controlHeight)
        rightEdge = closeButton.frame.minX - Self.controlSpacing

        let modeWidth: CGFloat = 150
        modeButton.frame = NSRect(x: rightEdge - modeWidth, y: centeredY,
                                  width: modeWidth, height: controlHeight)
        rightEdge = modeButton.frame.minX - Self.controlSpacing

        let chevronSize = controlHeight
        nextButton.frame = NSRect(x: rightEdge - chevronSize, y: centeredY,
                                  width: chevronSize, height: controlHeight)
        rightEdge = nextButton.frame.minX
        previousButton.frame = NSRect(x: rightEdge - chevronSize, y: centeredY,
                                      width: chevronSize, height: controlHeight)
        rightEdge = previousButton.frame.minX - Self.controlSpacing

        counterLabel.sizeToFit()
        let counterWidth = min(120, max(0, counterLabel.frame.width))
        let counterHeight = counterLabel.frame.height
        counterLabel.frame = NSRect(x: rightEdge - counterWidth,
                                    y: lineCenterY - counterHeight / 2,
                                    width: counterWidth,
                                    height: counterHeight)
        rightEdge = counterLabel.frame.minX - Self.controlSpacing

        let searchX = Self.horizontalPadding
        let searchWidth = max(0, rightEdge - searchX)
        searchField.frame = NSRect(x: searchX, y: centeredY,
                                   width: searchWidth, height: controlHeight)
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: Any) {
        // Enter in the search field advances to the next match.
        delegate?.chatFindBarFindNext(self)
    }

    @objc private func previousButtonClicked(_ sender: Any) {
        delegate?.chatFindBarFindPrevious(self)
    }

    @objc private func nextButtonClicked(_ sender: Any) {
        delegate?.chatFindBarFindNext(self)
    }

    @objc private func modeChanged(_ sender: Any) {
        delegate?.chatFindBar(self, didChangeQuery: searchField.stringValue, mode: mode)
    }

    @objc private func closeButtonClicked(_ sender: Any) {
        delegate?.chatFindBarClose(self)
    }
}

extension ChatFindBarView: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        delegate?.chatFindBar(self, didChangeQuery: searchField.stringValue, mode: mode)
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.chatFindBarClose(self)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            delegate?.chatFindBarFindPrevious(self)
            return true
        default:
            return false
        }
    }
}
