//
//  iTermPreferencesBaseViewController.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

fileprivate let terminalModeKey = "terminal mode"
fileprivate let browserModeKey = "browser mode"
fileprivate let hiddenModeKey = "hidden mode"
fileprivate let sharedProfilesModeKey = "shared profiles mode"
fileprivate let key = "frames"

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
            guard let tabViewItemView = tabViewItem.view else {
                return false
            }
            let configuration = SavedFrames.Configuration(terminal: terminal,
                                                          browser: browser,
                                                          hidden: hidden,
                                                          sharedProfiles: sharedProfiles)
            if savedFrames?.configuration == configuration {
                // Nothing has changed
                let result = hasVisibleControls(tabViewItemView)
                return result
            }

            var reveal = [ModalEnclosure]()
            var remove = [ModalEnclosure]()
            var nestedTabViews = [NSTabView]()
            var enclosures = [ModalEnclosure]()
            tabViewItemView.walk { either in
                switch either {
                case .left(let subview):
                    if let enclosure = subview as? TerminalModeEnclosure {
                        enclosures.append(subview as! ModalEnclosure)
                        if terminal {
                            reveal.append(enclosure)
                        } else {
                            remove.append(enclosure)
                        }
                        return false
                    }
                    if let enclosure = subview as? BrowserModeEnclosure {
                        enclosures.append(subview as! ModalEnclosure)
                        if browser {
                            reveal.append(enclosure)
                        } else {
                            remove.append(enclosure)
                        }
                        return false
                    }
                    if let enclosure = subview as? HiddenModeEnclosure {
                        enclosures.append(subview as! ModalEnclosure)
                        if hidden {
                            reveal.append(enclosure)
                        } else {
                            remove.append(enclosure)
                        }
                        return false
                    }
                    if let enclosure = subview as? SharedProfileEnclosure {
                        enclosures.append(subview as! ModalEnclosure)
                        if sharedProfiles {
                            reveal.append(enclosure)
                        } else {
                            remove.append(enclosure)
                        }
                        return false
                    }
                    return true

                case .right(let tabView):
                    nestedTabViews.append(tabView)
                    return true
                }
            }
            // On the first call, save a bunch of state. On subsequent calls, restore it.
            saveOrRestoreFrames(enclosures,
                                nestedTabViews,
                                configuration)
            let groupedRemove = Dictionary(grouping: remove,
                                           by: { $0.superview?.it_addressString ?? "(nil)" })
            for enclosure in reveal {
                enclosure.isHidden = false
            }
            // Remove what doesn't belong.
            updateViews(remove: Array(groupedRemove.values),
                        nestedTabViews: nestedTabViews)
            let result = hasVisibleControls(tabViewItemView)
            return result
        }
}

extension iTermPreferencesBaseViewController {
    private class SavedFrames: NSObject {
        struct Configuration: Equatable {
            var terminal = false
            var browser = false
            var hidden = false
            var sharedProfiles = false
        }
        var frames = [(NSView, NSRect)]()
        var tabViewItems = [(NSTabView, [NSTabViewItem])]()
        var configuration = Configuration()
    }

    private var savedFrames: SavedFrames? {
        internalState[key] as? SavedFrames
    }

    private func saveOrRestoreFrames(_ enclosures: [ModalEnclosure],
                                     _ tabViews: [NSTabView],
                                     _ configuration: SavedFrames.Configuration) {
        if let savedFrames {
            // Restore all the original frames
            for tuple in savedFrames.frames {
                /*
                if tuple.0.identifier?.rawValue == "debug" {
                    print("Restoring frame of debug view. It is \(tuple.1)")
                }
                 */
                tuple.0.frame = tuple.1
            }
            // Put back formerly removed tab view items
            for tuple in savedFrames.tabViewItems {
                let tabView = tuple.0
                var i = 0
                for item in tuple.1 {
                    if i == tabView.tabViewItems.count || tabView.tabViewItems[i] != item {
                        tabView.insertTabViewItem(item, at: i)
                    }
                    i += 1
                }
            }
            savedFrames.configuration = configuration
        } else {
            let siblings = Set(enclosures.flatMap { $0.superview?.subviews ?? [] })
            /*
            if let debug = siblings.first(where: { $0.identifier?.rawValue == "debug" }) {
                fuckingPrint("Saving frame of debug view \(debug.description). It is \(debug.frame)")
            }
             */
            let savedFrames = SavedFrames()
            savedFrames.frames = siblings.map { ($0, $0.frame) }
            savedFrames.tabViewItems = tabViews.map { ($0, $0.tabViewItems) }
            savedFrames.configuration = configuration
            internalState[key] = savedFrames
        }
    }

    // Both sets of views are grouped by parent, so it's an array of sibling views.
    private func updateViews(remove: [[NSView]],
                             nestedTabViews: [NSTabView]) {
        // For each group of siblings go bottom to top removing and shifting up
        for siblingsToRemove in remove {
            let parent = siblingsToRemove.first!.superview!
            let sortedSiblings = parent.subviews.sorted { $0.frame.minY < $1.frame.minY }

            var shift = CGFloat(0)
            for view in sortedSiblings.reversed() {
                var frame = view.frame
                frame.origin.y += shift
                view.frame = frame
                /*
                if view.identifier?.rawValue == "debug" {
                    print("Shift debug view by \(shift) to \(frame)")
                }
                 */
                if siblingsToRemove.contains(view) {
                    shift += view.frame.height
                    view.isHidden = true
                }
            }
        }


        // If any nested tab view items had no visible controls, remove them from their enclosing tab view.
        for tabView in nestedTabViews {
            for tabViewItem in tabView.tabViewItems {
                if let view = tabViewItem.view, !hasVisibleControls(view) {
                    tabView.removeTabViewItem(tabViewItem)
                }
            }
        }
    }

    private func hasVisibleControls(_ view: NSView) -> Bool {
        if view.isHidden {
            return false
        }
        var result = false
        view.walk { either in
            switch either {
            case .left(let view as NSControl):
                if !result {
                    result = !view.isHidden
                }
                return false

            case .left(let view):
                return !view.isHidden

            case .right:
                return !result
            }
        }
        return result
    }
}
