//
//  iTermColorScopeVariables.swift
//  iTerm2SharedARC
//
//  Exposes a session's live colors as variables under a `colors` scope so a
//  color setting can be bound to an expression such as `colors.ansi.yellow` or
//  `colors.indexed[3]` and track the palette instead of holding a frozen RGB.
//
//  Values are hex strings (for example "#ffff00", or "p3#...." for a Display P3
//  color), which is what a color binding expects: iTermProfilePreferences
//  converts a bound string with +[NSColor colorFromHexString:].
//
//  Indices 0-15 of `colors.indexed` are the 16 ANSI colors and are also exposed
//  by name under `colors.ansi.*`. Indices 16-255 are the fixed 6x6x6 cube and
//  grayscale ramp. Array-element references (colors.indexed[N]) are recorded at
//  array granularity by the expression evaluator, so any indexed change re-fires
//  every colors.indexed[*] binding. That is coarse but correct; with a handful
//  of bindings the extra re-evaluations are harmless.

import Foundation

@objc(iTermColorScopeVariables)
class iTermColorScopeVariables: NSObject {
    private let scope: iTermVariableScope
    private let colors: iTermVariables
    private let ansi: iTermVariables

    // The last hex string pushed for each of the 256 indexed colors. The whole
    // array is re-set on any element change because element references link to
    // the array as a whole.
    private var indexed: [String]

    // ANSI index (0-15) -> child name under colors.ansi.
    private static let ansiNames = [
        "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        "brightBlack", "brightRed", "brightGreen", "brightYellow",
        "brightBlue", "brightMagenta", "brightCyan", "brightWhite"
    ]

    // color-map key -> child name under colors, for the non-indexed colors.
    private static let namedKeys: [Int32: String] = [
        kColorMapForeground: "foreground",
        kColorMapBackground: "background",
        kColorMapBold: "bold",
        kColorMapLink: "link",
        kColorMapMatch: "match",
        kColorMapSelection: "selectionBackground",
        kColorMapSelectedText: "selectionText",
        kColorMapCursor: "cursor",
        kColorMapCursorText: "cursorText",
        kColorMapUnderline: "underline",
    ]

    // The expression that reads palette index `index`. Indices 0-15 use the
    // named ANSI form; 16-255 use the indexed array. Keep this authoritative so
    // callers (for example the OSC SetColors=i:N path) stay in sync with the
    // variables this class publishes.
    @objc(expressionForPaletteIndex:)
    static func expression(forPaletteIndex index: Int) -> String {
        if index >= 0 && index < ansiNames.count {
            return "colors.ansi.\(ansiNames[index])"
        }
        return "colors.indexed[\(index)]"
    }

    @objc(initWithScope:owner:)
    init(scope: iTermVariableScope, owner: iTermObject) {
        self.scope = scope
        colors = iTermVariables(context: [], owner: owner)
        ansi = iTermVariables(context: [], owner: owner)
        indexed = Array(repeating: "", count: 256)
        super.init()
        scope.setValue(colors, forVariableNamed: "colors")
        scope.setValue(ansi, forVariableNamed: "colors.ansi")
        scope.setValue(indexed, forVariableNamed: "colors.indexed")
    }

    // Populate every color variable from the current color map. Call after colors
    // load so bindings evaluate against real values.
    @objc(reloadFromColorMap:)
    func reload(from colorMap: iTermColorMapReading) {
        let base = kColorMap8bitBase
        // Start from empty so an index the new map lacks is cleared rather than
        // carrying the previous profile's value. Array elements can't be nil, so a
        // missing slot becomes "" (which colorFromHexString: rejects, so a binding
        // no-ops) instead of a stale color.
        var newIndexed = [String](repeating: "", count: 256)
        for i in 0..<256 {
            if let color = colorMap.color(forKey: base + Int32(i)) {
                newIndexed[i] = color.hexString()
            }
        }
        indexed = newIndexed
        scope.setValue(newIndexed, forVariableNamed: "colors.indexed")
        // Clear (nil) an ANSI or named scalar the new map lacks so a profile switch
        // can't leave a stale value published under colors.*.
        for i in 0..<16 {
            scope.setValue(colorMap.color(forKey: base + Int32(i))?.hexString(),
                           forVariableNamed: "colors.ansi.\(Self.ansiNames[i])")
        }
        for (key, name) in Self.namedKeys {
            scope.setValue(colorMap.color(forKey: key)?.hexString(), forVariableNamed: "colors.\(name)")
        }
    }

    // Update the variable(s) backing a single color-map key. The nil-color branch
    // clears the value (empty string for an indexed slot, nil for a scalar) to match
    // reload(from:). Note the live color map removes a key and returns before firing
    // its change delegate, so in production this is only ever called with a non-nil
    // color; the nil branch is defensive (and exercised by tests). A genuine removal
    // is reconciled by the next reload(from:), not incrementally.
    @objc(didChangeColorForKey:to:)
    func didChangeColor(forKey key: Int32, to color: NSColor?) {
        let hex = color?.hexString()
        let base = kColorMap8bitBase
        if key >= base && key < base + 256 {
            let idx = Int(key - base)
            indexed[idx] = hex ?? ""
            scope.setValue(indexed, forVariableNamed: "colors.indexed")
            if idx < 16 {
                scope.setValue(hex, forVariableNamed: "colors.ansi.\(Self.ansiNames[idx])")
            }
        } else if let name = Self.namedKeys[key] {
            scope.setValue(hex, forVariableNamed: "colors.\(name)")
        }
    }
}
