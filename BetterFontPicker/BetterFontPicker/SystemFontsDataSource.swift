//
//  SystemFontsDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

fileprivate extension BidirectionalCollection where Element == String {
    func sortedLocalized() -> Array<String> {
        return sorted(by: { (s1: String, s2: String) -> Bool in
            return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
        })
    }
}

private func ComputeMonospaceAndVariableFamilyNames() -> ([String], [String]) {
    var monospace: Set<String> = []
    var variable: Set<String> = []
    for descriptor in  NSFontCollection.withAllAvailableDescriptors.matchingDescriptors ?? [] {
        if let name = descriptor.object(forKey: NSFontDescriptor.AttributeName.family) as? String {
            if monospace.contains(name) || variable.contains(name) {
                // The call to symbolicTraits is slow so avoid doing it more than needed.
                continue
            }
            if descriptor.symbolicTraits.contains(.monoSpace) {
                monospace.insert(name)
            } else {
                variable.insert(name)
            }
        }
    }
    let newValue = (Array(monospace).sortedLocalized(),
                    Array(variable).sortedLocalized())
    return newValue
}

@objc(BFPSystemFontsDataSource)
class SystemFontsDataSource: NSObject, FontListDataSource {
    private static var suppressCacheInvalidation = false
    private static var internalMonospaceAndVariableFamilyNames: ([String], [String])? = nil

    private static var monospaceAndVariableFamilyNames: ([String], [String]) {  // monospace, variable pitch
        if let result = internalMonospaceAndVariableFamilyNames {
            return result
        }
        let newValue = ComputeMonospaceAndVariableFamilyNames()
        internalMonospaceAndVariableFamilyNames = newValue
        return newValue
    }

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
            internalMatchingFonts = SystemFontsDataSource.monospaceAndVariableFamilyNames.0
        case .variablePitch:
            internalMatchingFonts = SystemFontsDataSource.monospaceAndVariableFamilyNames.1
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
    }

    func reload() {
        if !SystemFontsDataSource.suppressCacheInvalidation {
            SystemFontsDataSource.internalMonospaceAndVariableFamilyNames = nil
            SystemFontsDataSource.suppressCacheInvalidation = true
            DispatchQueue.main.async {
                SystemFontsDataSource.suppressCacheInvalidation = false
            }
        }
        internalMatchingFonts = nil
        names = loadNames()
    }

    private func loadNames() -> [String] {
        let names = matchingFonts
        let familyNames = names as Array<String>
        let queryTokens = filter.normalizedTokens
        return familyNames.filter({ (name) -> Bool in
            return name.matchesTableViewSearchQueryTokens(queryTokens)
        })

    }
}
