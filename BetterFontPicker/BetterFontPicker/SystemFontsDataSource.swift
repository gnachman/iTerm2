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
    private let pointSize = CGFloat(12)
    private lazy var matchingFonts: [String] = {
        switch traitMask {
        case .all:
            return NSFontManager.shared.availableFontFamilies.sortedLocalized()
        case .requiresTraits(let mask):
            return NSFontManager.shared.availableFontFamilies.filter({ (name) -> Bool in
                guard let font = NSFont(name: name, size: pointSize) else {
                    return false
                }
                return NSFontManager.shared.traits(of: font).contains(mask)
            }).sortedLocalized()
        case .excludesTraits(let mask):
            return NSFontManager.shared.availableFontFamilies.filter({ (name) -> Bool in
                guard let font = NSFont(name: name, size: pointSize) else {
                    return false
                }
                return !NSFontManager.shared.traits(of: font).contains(mask)
            }).sortedLocalized()
        }
    }()

    weak var delegate: SystemFontsDataSourceDelegate?
    enum Filter {
        case requiresTraits(NSFontTraitMask)
        case excludesTraits(NSFontTraitMask)
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

    init(excludingTraits mask: NSFontTraitMask) {
        traitMask = .excludesTraits(mask)

        super.init()

        postInit()
    }

    init(requiringTraits mask: NSFontTraitMask) {
        traitMask = .requiresTraits(mask)

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
