//
//  NSView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/28/25.
//

import Foundation

extension NSView {
    func containingTabView(under: NSView) -> NSTabView? {
        var v: NSView? = self
        while let view = v, view != under {
            if let tabView = view as? NSTabView {
                return tabView
            }
            v = view.superview
        }
        return nil
    }
}

extension NSView {
    // Does a depth-first search of subviews. When it finds a NSTabView, that adds a level to the
    // output. Levels are named after NSTabViewItem.label. The root's key is just [].
    // Only views that are keys in the mapTable will be added to the output.
    @objc
    func descendantsTabviewTree(belongingToKeysIn mapTable: NSMapTable<NSView, PreferenceInfo>) -> [[String]: [NSView]] {
        var result = [[String]: [NSView]]()
        updateDescendantsTabviewTree(belongingToKeysIn: mapTable, currentLevel: [], addTo: &result)
        return result
    }

    func updateDescendantsTabviewTree(belongingToKeysIn mapTable: NSMapTable<NSView, PreferenceInfo>,
                                      currentLevel: [String],
                                      addTo result: inout [[String]: [NSView]]) {
        for view in subviews {
            if mapTable.object(forKey: view) != nil {
                result[currentLevel, default: []].append(view)
                continue
            }
            // Handle containers. Tab views are special as they add a level.
            if let tabView = view as? NSTabView {
                for item in tabView.tabViewItems {
                    item.view?.updateDescendantsTabviewTree(belongingToKeysIn: mapTable,
                                                            currentLevel: currentLevel + [item.label],
                                                            addTo: &result)
                }
            } else if !view.subviews.isEmpty {
                view.updateDescendantsTabviewTree(belongingToKeysIn: mapTable,
                                                  currentLevel: currentLevel,
                                                  addTo: &result)
            }
        }
    }
}

