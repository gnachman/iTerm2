//
//  iTermTabGroup.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/26.
//

import AppKit

// A tab group's definition: its identity, name, and color. Identity is a UUID
// (not window-scoped) so a group keeps its identity when dragged into another
// window. The definition is not stored centrally: it rides each member tab
// (PTYTab.tabGroupID / tabGroupName / tabGroupColor). The window controller
// builds one of these on demand from a member tab to answer the tab bar's
// PSMTabGroupDataSource queries. Which tabs belong to the group, and their run
// order, come from the tabs themselves; nothing here holds a tab list.
@objc(iTermTabGroup)
final class iTermTabGroup: NSObject, PSMTabGroup {
    @objc let uniqueIdentifier: String
    @objc let name: String
    @objc let color: NSColor
    // The group this one is nested in, or nil for a top-level group. Nesting is
    // one level deep.
    @objc let parentIdentifier: String?

    @objc init(uniqueIdentifier: String, name: String, color: NSColor, parentIdentifier: String?) {
        self.uniqueIdentifier = uniqueIdentifier
        self.name = name
        self.color = color
        self.parentIdentifier = parentIdentifier
        super.init()
    }

    @objc convenience init(uniqueIdentifier: String, name: String, color: NSColor) {
        self.init(uniqueIdentifier: uniqueIdentifier, name: name, color: color, parentIdentifier: nil)
    }
}

// Chooses the color for a new tab group from a fixed palette.
@objc(iTermTabGroupColorChooser)
final class iTermTabGroupColorChooser: NSObject {
    // Returns the palette index to use. Prefers the first entry no group in the
    // window uses. When every entry is taken, falls back to cycling by
    // `groupCount`. Either way it never returns `parentIndex`, so a sub-group is
    // never the same color as its parent (unless the palette has one entry).
    static func index(paletteCount: Int,
                      inUse: Set<Int>,
                      parentIndex: Int?,
                      groupCount: Int) -> Int {
        it_assert(paletteCount > 0, "palette must not be empty")
        if let free = (0..<paletteCount).first(where: { !inUse.contains($0) && $0 != parentIndex }) {
            return free
        }
        let cycled = groupCount % paletteCount
        if cycled == parentIndex && paletteCount > 1 {
            return (cycled + 1) % paletteCount
        }
        return cycled
    }

    // `inUseColors` are the colors of the groups in the window; `parentColor` is
    // the color of the group the new one will be nested in, if any. A color
    // counts as a palette entry when it approximately matches the entry as it
    // looks in either light or dark appearance. The palette's system colors
    // differ between the two, and a stored group color was frozen in whichever
    // appearance was active when the group was made.
    @objc(colorFromPalette:inUseColors:parentColor:groupCount:)
    static func color(palette: [NSColor],
                      inUseColors: [NSColor],
                      parentColor: NSColor?,
                      groupCount: Int) -> NSColor {
        let resolved = palette.map { appearanceVariants(of: $0) }
        func paletteIndex(_ color: NSColor) -> Int? {
            guard let stored = color.usingColorSpace(.sRGB) else {
                return nil
            }
            return resolved.firstIndex { variants in
                variants.contains { $0.isApproximatelyEqual(to: stored, epsilon: 0.01) }
            }
        }
        let inUse = Set(inUseColors.compactMap(paletteIndex))
        let parentIndex = parentColor.flatMap(paletteIndex)
        return palette[index(paletteCount: palette.count,
                             inUse: inUse,
                             parentIndex: parentIndex,
                             groupCount: groupCount)]
    }

    // `color` in sRGB as it resolves in light and in dark appearance.
    private static func appearanceVariants(of color: NSColor) -> [NSColor] {
        return [NSAppearance.Name.aqua, .darkAqua].compactMap { name in
            var result: NSColor?
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                result = color.usingColorSpace(.sRGB)
            }
            return result
        }
    }
}
