//
//  DonateViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/27/22.
//

import Foundation

@objc
private class DonateView: NSView {
}

@objc(iTermDonateViewController)
class DonateViewController: NSTitlebarAccessoryViewController {
    let innerVC = DismissableLinkViewController(userDefaultsKey: "NoSyncHideDonateLabel",
                                                text: "Donate",
                                                url: URL(string: "https://iterm2.com/donate.html")!,
                                                clickToHide: true)
    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = DonateView()

        let subview = innerVC.view
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)

        view.frame = subview.frame

        view.addConstraint(NSLayoutConstraint(item: view,
                                              attribute: .width,
                                              relatedBy: .equal,
                                              toItem: subview,
                                              attribute: .width,
                                              multiplier: 1,
                                              constant: 0))
        view.addConstraint(NSLayoutConstraint(item: view,
                                              attribute: .height,
                                              relatedBy: .greaterThanOrEqual,
                                              toItem: subview,
                                              attribute: .height,
                                              multiplier: 1,
                                              constant: 0))
        view.addConstraint(NSLayoutConstraint(item: view,
                                              attribute: .leading,
                                              relatedBy: .equal,
                                              toItem: subview,
                                              attribute: .leading,
                                              multiplier: 1,
                                              constant: 0))
        view.addConstraint(NSLayoutConstraint(item: view,
                                              attribute: .top,
                                              relatedBy: .equal,
                                              toItem: subview,
                                              attribute: .top,
                                              multiplier: 1,
                                              constant: -7
                                             ))
    }
}
