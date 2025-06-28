//
//  TerminalModeEnclosure.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

@objc(iTermModalEnclosure)
@IBDesignable
class ModalEnclosure: NSView {
    var shiftsViewsBeneath: Bool = true
    var neighborToGrowRight: NSView?

    @objc
    var visibleForProfileTypes: ProfileType {
        return [.all]
    }
}

@objc(iTermTerminalModeEnclosure)
@IBDesignable
class TerminalModeEnclosure: ModalEnclosure {
    @IBInspectable
    override var shiftsViewsBeneath: Bool {
        get {
            super.shiftsViewsBeneath
        }
        set {
            super.shiftsViewsBeneath = newValue
        }
    }

    @IBOutlet override var neighborToGrowRight: NSView? {
        get {
            super.neighborToGrowRight
        }
        set {
            super.neighborToGrowRight = newValue
        }
    }

    @objc
    override var visibleForProfileTypes: ProfileType {
        return [.terminal]
    }
}

@objc(iTermBrowserModeEnclosure)
@IBDesignable
class BrowserModeEnclosure: ModalEnclosure {
    @objc
    override var visibleForProfileTypes: ProfileType {
        return [.browser]
    }
}

@objc(iTermHiddenModeEnclosure)
@IBDesignable
class HiddenModeEnclosure: ModalEnclosure {
    @objc
    override var visibleForProfileTypes: ProfileType {
        if iTermAdvancedSettingsModel.browserProfiles() {
            return [.all]
        } else {
            return []
        }
    }
}

@objc(iTermSharedProfileEnclosure)
@IBDesignable
class SharedProfileEnclosure: ModalEnclosure {
    @objc
    override var visibleForProfileTypes: ProfileType {
        return [.all]
    }
}

extension NSView {
    @objc
    var enclosingModalEnclosure: ModalEnclosure? {
        var current = self
        while true {
            if let enclosure = current as? ModalEnclosure {
                return enclosure
            }
            if let parent = current.superview {
                current = parent
            } else {
                return nil
            }
        }
    }
}

fileprivate let terminalModeKey = "terminal mode"
fileprivate let browserModeKey = "browser mode"
fileprivate let hiddenModeKey = "hidden mode"
fileprivate let sharedProfilesModeKey = "shared profiles mode"
fileprivate let key = "frames"

@objc
extension NSView {
    // Returns whether the tab view item can remain because it has visible subviews.
    @objc(setVisibilityForTerminalEnclosures:browserEnclosures:hiddenModeEnclosures:sharedProfilesEnclosures:stateStorage:shrinkage:)
    func setVisibility(forTerminalEnclosures terminal: Bool,
                       browserEnclosures browser: Bool,
                       hiddenModeEnclosures hidden: Bool,
                       sharedProfilesEnclosures sharedProfiles: Bool,
                       stateStorage: NSMutableDictionary,
                       shrinkage: UnsafeMutablePointer<NSSize>?) -> Bool {
        let tabViewItemView = self
        let configuration = SavedFrames.Configuration(terminal: terminal,
                                                      browser: browser,
                                                      hidden: hidden,
                                                      sharedProfiles: sharedProfiles)
        if savedFrames(stateStorage: stateStorage)?.configuration == configuration {
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
                            configuration,
                            stateStorage: stateStorage)
        let groupedRemove = Dictionary(grouping: remove,
                                       by: { $0.superview?.it_addressString ?? "(nil)" })
        for enclosure in reveal {
            enclosure.isHidden = false
        }
        // Remove what doesn't belong.
        let size = updateViews(remove: Array(groupedRemove.values),
                               nestedTabViews: nestedTabViews)
        if let shrinkage {
            shrinkage.pointee = size
        }
        let result = hasVisibleControls(tabViewItemView)
        return result
    }

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

    private func savedFrames(stateStorage: NSMutableDictionary) -> SavedFrames? {
        stateStorage[key] as? SavedFrames
    }

    @nonobjc
    private func saveOrRestoreFrames(_ enclosures: [ModalEnclosure],
                                     _ tabViews: [NSTabView],
                                     _ configuration: SavedFrames.Configuration,
                                     stateStorage: NSMutableDictionary) {
        if let savedFrames = savedFrames(stateStorage: stateStorage) {
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
            stateStorage[key] = savedFrames
        }
    }

    // Both sets of views are grouped by parent, so it's an array of sibling views.
    private func updateViews(remove: [[ModalEnclosure]],
                             nestedTabViews: [NSTabView]) -> NSSize {
        // For each group of siblings go bottom to top removing and shifting up
        var shrinkage = NSSize.zero
        for modalEnclosuresToRemove in remove {
            let parent = modalEnclosuresToRemove.first!.superview!
            let verticallySortedSiblings = parent.subviews.sorted { $0.frame.minY < $1.frame.minY }
            shrinkage.height += shift(sortedSiblings: verticallySortedSiblings, modalEnclosuresToRemove: modalEnclosuresToRemove, vertically: true)
            let horizontallySortedSiblings = parent.subviews.sorted { $0.frame.minX < $1.frame.minX }
            shrinkage.width += shift(sortedSiblings: horizontallySortedSiblings, modalEnclosuresToRemove: modalEnclosuresToRemove, vertically: false)

            // If any nested tab view items had no visible controls, remove them from their enclosing tab view.
            for tabView in nestedTabViews {
                for tabViewItem in tabView.tabViewItems {
                    if let view = tabViewItem.view, !hasVisibleControls(view) {
                        tabView.removeTabViewItem(tabViewItem)
                    }
                }
            }
        }
        return shrinkage
    }

    // Horizontal shifting isn't implemented becuase it's not needed. For now the horizontal pass
    // only grows neighbors that are linked by `neighborToGrowRight` and everything else happens in
    // the vertical pass.
    private func shift(sortedSiblings: [NSView],
                       modalEnclosuresToRemove: [ModalEnclosure],
                       vertically: Bool) -> CGFloat {
        var shift = CGFloat(0)
        for view in sortedSiblings.reversed() {
            var frame = view.frame
            if vertically {
                frame.origin.y += shift
                view.frame = frame
            }
            /*
             if view.identifier?.rawValue == "debug" {
             print("Shift debug view by \(shift) to \(frame)")
             }
             */
            if let thisEnclosure = view as? ModalEnclosure,
               modalEnclosuresToRemove.contains(thisEnclosure) {
                if vertically {
                    if thisEnclosure.shiftsViewsBeneath {
                        shift += view.frame.height
                    }
                    view.isHidden = true
                } else if let neighbor = thisEnclosure.neighborToGrowRight {
                    var frame = neighbor.frame
                    frame.size.width += view.frame.width
                    neighbor.frame = frame
                }
            }
        }
        return shift
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
