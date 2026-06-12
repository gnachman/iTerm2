//
//  iTermLayoutReportingView.swift
//  iTerm2
//
//  Created by George Nachman on 9/8/25.
//

@objc
protocol iTermLayoutReportingViewDelegate: AnyObject {
    func layoutReportingViewDidLayout(_ view: iTermLayoutReportingView, oldSize: NSSize)
}
@objc
class iTermLayoutReportingView: NSView {
    @objc weak var layoutReportingDelegate: iTermLayoutReportingViewDelegate?

    override func resizeSubviews(withOldSize oldSize: CGSize) {
        layoutReportingDelegate?.layoutReportingViewDidLayout(self, oldSize: oldSize)
    }
}
