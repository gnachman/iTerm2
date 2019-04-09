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

@objc(BFPSystemFontsDataSource)
class SystemFontsDataSource: NSObject, FontListDataSource {
    private let pointSize = CGFloat(12)
    weak var delegate: SystemFontsDataSourceDelegate?
    enum Filter {
        case requiresTraits(NSFontTraitMask)
        case excludesTraits(NSFontTraitMask)
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

    init(excludingTraits mask: NSFontTraitMask) {
        traitMask = .excludesTraits(mask)

        super.init()

        NotificationCenter.default.addObserver(forName: NSFont.fontSetChangedNotification,
                                               object: nil,
                                               queue: nil) { [weak self] (notification) in
                                                self?.reload()
        }
    }

    init(requiringTraits mask: NSFontTraitMask) {
        traitMask = .requiresTraits(mask)

        super.init()

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

    private func matchingFonts() -> [String]? {
        switch traitMask {
        case .requiresTraits(let mask):
            return NSFontManager.shared.availableFontFamilies.filter({ (name) -> Bool in
                guard let font = NSFont(name: name, size: pointSize) else {
                    return false
                }
                return NSFontManager.shared.traits(of: font).contains(mask)
            }).sorted(by: { (s1, s2) -> Bool in
                return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
            })
        case .excludesTraits(let mask):
            return NSFontManager.shared.availableFontFamilies.filter({ (name) -> Bool in
                guard let font = NSFont(name: name, size: pointSize) else {
                    return false
                }
                return !NSFontManager.shared.traits(of: font).contains(mask)
            }).sorted(by: { (s1, s2) -> Bool in
                return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
            })
        }
    }

    private func loadNames() -> [String] {
        guard let names = matchingFonts() else {
            return []
        }
        let familyNames = names as Array<String>
        let queryTokens = filter.normalizedTokens
        return familyNames.filter({ (name) -> Bool in
            return name.matchesTableViewSearchQueryTokens(queryTokens)
        })

    }
}
