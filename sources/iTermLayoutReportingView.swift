//
//  iTermLayoutReportingView.swift
//  iTerm2
//
//  Created by George Nachman on 9/5/25.
//

@objc
protocol iTermViewLayoutDelegate: AnyObject {
    func viewDidLayoutReliable(_ sender: NSView)
}

@available(macOS 26, *)
@objc
class iTermLayoutReportingView: NSView {
    @objc weak var layoutDelegate: iTermViewLayoutDelegate?

    @objc
    override func resizeSubviews(withOldSize: NSSize) {
        super.resizeSubviews(withOldSize: withOldSize)
        layoutDelegate?.viewDidLayoutReliable(self)
    }
}
