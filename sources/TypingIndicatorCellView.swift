//
//  TypingIndicatorCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

@objc
class TypingIndicatorCellView: NSView {
    private let activityIndicator = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Bubble View Setup
        activityIndicator.isIndeterminate = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.style = .spinning
        activityIndicator.controlSize = .regular
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            activityIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            activityIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(equalToConstant: 20.0)
        ])
        activityIndicator.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        activityIndicator.startAnimation(nil)
    }
}

