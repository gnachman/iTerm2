//
//  TypingIndicatorCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

@objc
class TypingIndicatorCellView: NSView {
    private let activityIndicator = NSProgressIndicator()

    private static let leadingInset: CGFloat = 8
    private static let indicatorSize: CGFloat = 16
    static let cellHeight: CGFloat = 20

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        activityIndicator.isIndeterminate = true
        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        addSubview(activityIndicator)
        activityIndicator.startAnimation(nil)
    }

    override func layout() {
        super.layout()
        // Hardcode the indicator size — NSProgressIndicator's fittingSize
        // and intrinsicContentSize both return the *current frame* (which
        // is .zero on init) rather than a measured natural size, so reading
        // them gives garbage. 16×16 matches the .small spinner.
        let y = floor((bounds.height - Self.indicatorSize) / 2)
        activityIndicator.frame = NSRect(x: Self.leadingInset,
                                         y: y,
                                         width: Self.indicatorSize,
                                         height: Self.indicatorSize)
    }
}
