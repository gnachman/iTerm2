//
//  SystemFontsDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

extension BidirectionalCollection where Element == String {
    func sortedLocalized() -> Array<String> {
        return sorted(by: { (s1: String, s2: String) -> Bool in
            return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
        })
    }
}

@objc(BFPSystemFontsDataSource)
class SystemFontsDataSource: NSObject, FontListDataSource {
    let classifier = SystemFontClassifier()

    private let pointSize = CGFloat(12)
    private var internalMatchingFonts: [String]?
    private var matchingFonts: [String] {
        if let result = internalMatchingFonts {
            return result
        }
        switch traitMask {
        case .all:
            internalMatchingFonts = NSFontManager.shared.availableFontFamilies.sortedLocalized()
        case .fixedPitch:
            internalMatchingFonts = Array(classifier.monospace).sortedLocalized()
        case .variablePitch:
            internalMatchingFonts = Array(classifier.variable).sortedLocalized()
        }
        return internalMatchingFonts!
    }

    enum Filter {
        case fixedPitch
        case variablePitch
        case all
    }
    private let traitMask: Filter
    lazy var names: Array<String> = {
        return loadNames()
    }()
    private var internalFilter = ""
    var filter: String {
        get {
            return internalFilter
        }
        set {
            internalFilter = newValue
            names = loadNames()
        }
    }
    var isSeparator: Bool {
        return false
    }

    override init() {
        traitMask = .all

        super.init()

        postInit()
    }

    init(filter: Filter) {
        traitMask = filter

        super.init()

        postInit()
    }

    func postInit() {
        classifier.sync()
    }

    func reload() {
        internalMatchingFonts = nil
        names = loadNames()
    }

    private func loadNames() -> [String] {
        classifier.sync()
        let familyNames = Array(matchingFonts)
        let queryTokens = filter.normalizedTokens
        return familyNames.filter({ (name) -> Bool in
            return name.matchesTableViewSearchQueryTokens(queryTokens)
        })
    }
}
