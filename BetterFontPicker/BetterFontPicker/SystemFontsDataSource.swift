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
        case .fixedPitch:
            let descriptors: [NSFontDescriptor] = NSFontCollection.withAllAvailableDescriptors.matchingDescriptors?.filter({ (descriptor) -> Bool in
                return descriptor.symbolicTraits.contains(.monoSpace)
            }) ?? []
            let maybeFamilyNames = descriptors.map { (descriptor) -> String in
                return descriptor.object(forKey: NSFontDescriptor.AttributeName.family) as? String ?? ""
            }
            return Array(Set(maybeFamilyNames.filter { (string) in
                return !string.isEmpty
            })).sortedLocalized()

        case .variablePitch:
            let descriptors: [NSFontDescriptor] = NSFontCollection.withAllAvailableDescriptors.matchingDescriptors?.filter({ (descriptor) -> Bool in
                return !descriptor.symbolicTraits.contains(.monoSpace)
            }) ?? []
            let maybeFamilyNames = descriptors.map { (descriptor) -> String in
                return descriptor.object(forKey: NSFontDescriptor.AttributeName.family) as? String ?? ""
            }
            return Array(Set(maybeFamilyNames.filter { (string) in
                return !string.isEmpty
            })).sortedLocalized()
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
