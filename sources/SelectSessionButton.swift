//
//  SelectSessionButton.swift
//  iTerm2
//
//  Created by George Nachman on 2/20/25.
//

@objc(iTermSelectSessionButton)
class SelectSessionButton: NSView {
    private let button = NSButton(title: "Select this Session", target: nil, action: nil)
    private let effectView = NSVisualEffectView()

    @objc var onButtonClicked: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 10.0
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 0.5, alpha: 1.0).cgColor
        layer?.masksToBounds = true

        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.material = .sheet
        addSubview(effectView)

        button.target = self
        button.action = #selector(buttonClicked(_:))
        addSubview(button)
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        button.frame = bounds.insetBy(dx: 16, dy: 16)
    }

    @objc func sizeToFit() {
        button.sizeToFit()
        let buttonSize = button.fittingSize
        self.frame.size = NSSize(width: buttonSize.width + 32, height: buttonSize.height + 32)
        needsLayout = true
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        onButtonClicked?()
    }
}
