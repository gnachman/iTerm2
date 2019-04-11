//
//  SystemFontsDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

protocol SystemFontsDataSourceDelegate : class {
    func systemFontsDataSourceDidChange(_ dataSource: SystemFontsDataSource)
}

fileprivate extension BidirectionalCollection where Element == String {
    func sortedLocalized() -> Array<String> {
        return sorted(by: { (s1: String, s2: String) -> Bool in
            return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
        })
    }
}

@objc(BFPSystemFontsDataSource)
class SystemFontsDataSource: NSObject, FontListDataSource {
    private static var monospaceAndVariableFamilyNames: ([String], [String]) = {  // monospace, variable pitch
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
        return (Array(monospace).sortedLocalized(),
                Array(variable).sortedLocalized())
    }()
    private let pointSize = CGFloat(12)
    private lazy var matchingFonts: [String] = {
        switch traitMask {
        case .all:
            return NSFontManager.shared.availableFontFamilies.sortedLocalized()
        case .fixedPitch:
            return SystemFontsDataSource.monospaceAndVariableFamilyNames.0

        case .variablePitch:
            return SystemFontsDataSource.monospaceAndVariableFamilyNames.1
        }
    }()

    weak var delegate: SystemFontsDataSourceDelegate?
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

    private func postInit() {
        NotificationCenter.default.addObserver(forName: NSFont.fontSetChangedNotification,
                                               object: nil,
                                               queue: nil) { [weak self] (notification) in
                                                self?.reload()
        }
    }

    private func reload() {
        names = loadNames()
        delegate?.systemFontsDataSourceDidChange(self)
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
