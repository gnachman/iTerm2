//
//  iTermPreferencesBaseViewController.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//


extension NSView {
    // closure returns whether it should recurse down a subview.
    func walk(_ closure: (Either<NSView, NSTabView>) -> (Bool)) {
        if let tabView = self as? NSTabView {
            if closure(.right(tabView)) {
                for item in tabView.tabViewItems {
                    item.view?.walk(closure)
                }
            }
        }
        if let scrollView = self as? NSScrollView {
            // Avoid the clipview and scrollers
            if closure(.left(scrollView)) {
                scrollView.documentView?.walk(closure)
            }
            return
        }
        for subview in subviews {
            if closure(.left(subview)) {
                subview.walk(closure)
            }
        }
    }
}

@objc
extension iTermPreferencesBaseViewController {
    // Returns whether the tab view item can remain because it has visible subviews.
    @objc(setVisibilityForTerminalEnclosures:browserEnclosures:hiddenModeEnclosures:sharedProfilesEnclosures:tabViewItem:)
    func setVisibility(
        forTerminalEnclosures terminal: Bool,
        browserEnclosures browser: Bool,
        hiddenModeEnclosures hidden: Bool,
        sharedProfilesEnclosures sharedProfiles: Bool,
        tabViewItem: NSTabViewItem) -> Bool {
            guard let view = tabViewItem.view else {
                return false
            }
            return view.setVisibility(forTerminalEnclosures: terminal,
                                      browserEnclosures: browser,
                                      hiddenModeEnclosures: hidden,
                                      sharedProfilesEnclosures: sharedProfiles,
                                      stateStorage: internalState,
                                      shrinkage: nil)
        }
}
