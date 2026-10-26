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
    static var callsToAction: [String] {
        return [String(localized: "Donate.CallToAction1", defaultValue: "Donate", comment: "Short donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction2", defaultValue: "Support iTerm2", comment: "Short donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction3", defaultValue: "iTerm2 is one person’s project. Donate now!", comment: "Donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction4", defaultValue: "Keep iTerm2 alive — Donate today!", comment: "Donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction5", defaultValue: "Love using iTerm2? Help keep it thriving!", comment: "Donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction6", defaultValue: "iTerm2 needs your support – Donate here.", comment: "Donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction7", defaultValue: "Help iTerm2 grow – Consider donating.", comment: "Donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction8", defaultValue: "Keep the iTerm2 dream alive – Donate!", comment: "Donation prompt shown in the Settings window"),
                String(localized: "Donate.CallToAction9", defaultValue: "Support the creator of iTerm2 – Donate now!", comment: "Donation prompt shown in the Settings window"),
        ]
    }

    // Room the accessory needs beyond its text: the link view's own padding
    // plus a gap before the centered window title.
    private static let overhead = 44.0

    // The widest call to action that leaves the centered title of a window
    // this wide untruncated.
    @objc(maxTextWidthForWindowWidth:title:)
    static func maxTextWidth(windowWidth: CGFloat, title: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.titleBarFont(ofSize: 0)]).width
        return (windowWidth - titleWidth) / 2 - overhead
    }

    // A random call to action no wider than `maxWidth`, or the narrowest one
    // if none is that narrow.
    static func callToAction(from candidates: [String],
                             maxWidth: CGFloat,
                             choose: ([String]) -> String? = { $0.randomElement() }) -> String {
        let width = { (text: String) in DismissableLinkViewController.width(of: text) }
        if let chosen = choose(candidates.filter { width($0) <= maxWidth }) {
            return chosen
        }
        return candidates.min { width($0) < width($1) }!
    }

    let innerVC: DismissableLinkViewController

    // `maxTextWidth` limits the call to action so it doesn't truncate the
    // window title or run off the edge of the title bar.
    @objc(initWithMaxTextWidth:)
    init(maxTextWidth: CGFloat) {
        innerVC = DismissableLinkViewController(userDefaultsKey: "NoSyncHideDonateLabel",
                                                text: DonateViewController.callToAction(from: DonateViewController.callsToAction,
                                                                                        maxWidth: maxTextWidth),
                                                url: URL(string: "https://iterm2.com/donate.html")!,
                                                clickToHide: true)
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
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
                                              constant: 7.5))
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
                                              constant: -4
                                             ))
    }
}
