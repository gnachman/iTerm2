//
//  iTermBrowserToolbar.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

@available(macOS 11.0, *)
@objc protocol iTermBrowserToolbarDelegate {
    func browserToolbarDidTapBack()
    func browserToolbarDidTapForward()
    func browserToolbarDidTapReload()
    func browserToolbarDidSubmitURL(_ url: String)
}

@available(macOS 11.0, *)
@objc(iTermBrowserToolbar)
class iTermBrowserToolbar: NSView {
    weak var delegate: iTermBrowserToolbarDelegate?
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var urlField: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButtons()
        setupConstraints()
    }

    private func setupButtons() {
        backButton = NSButton()
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backButton)

        forwardButton = NSButton()
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(forwardButton)

        reloadButton = NSButton()
        reloadButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reloadButton)
        
        urlField = NSTextField()
        urlField.placeholderString = "Enter URL"
        urlField.target = self
        urlField.action = #selector(urlFieldSubmitted)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlField)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            forwardButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 32),
            forwardButton.heightAnchor.constraint(equalToConstant: 32),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 8),
            reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 32),
            reloadButton.heightAnchor.constraint(equalToConstant: 32),
            
            urlField.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 12),
            urlField.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            urlField.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @objc private func backTapped() {
        delegate?.browserToolbarDidTapBack()
    }

    @objc private func forwardTapped() {
        delegate?.browserToolbarDidTapForward()
    }

    @objc private func reloadTapped() {
        delegate?.browserToolbarDidTapReload()
    }
    
    @objc private func urlFieldSubmitted() {
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.isEmpty {
            delegate?.browserToolbarDidSubmitURL(urlString)
        }
    }
    
    // MARK: - Public Interface
    
    func updateURL(_ url: String?) {
        urlField.stringValue = url ?? ""
    }
}

