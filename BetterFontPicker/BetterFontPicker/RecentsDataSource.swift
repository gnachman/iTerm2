//
//  RecentsDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

protocol RecentsDataSourceDelegate: class {
    func recentsDataSourceDidChange(_ dataSource: RecentsDataSource,
                                    netAdditions: Int)
}

@objc(BFPRecentsDataSource)
class RecentsDataSource: NSObject, FontListDataSource {
    private let userDefaultsKey = "NoSyncBFPRecents"
    private let capacity = 4
    lazy var recentsNames: Array<String> = {
        return loadNames()
    }()
    var isSeparator: Bool {
        return false
    }
    var names: [String] {
        return recentsNames
    }
    private var internalFilter = ""
    var filter: String {
        get {
            return internalFilter
        }
        set {
            internalFilter = newValue
            recentsNames = loadNames()
        }
    }
    weak var delegate: RecentsDataSourceDelegate?

    override init() {
        super.init()
    }

    func makeRecent(_ name: String) {
        guard !recentsNames.contains(name) else {
            return
        }
        let beforeCount = recentsNames.count
        recentsNames.insert(name, at: 0)
        removeLeastRecentIfNeeded()
        UserDefaults.standard.set(recentsNames, forKey: userDefaultsKey)
        delegate?.recentsDataSourceDidChange(self,
                                             netAdditions: recentsNames.count - beforeCount)
    }

    func removeLeastRecentIfNeeded() {
        while recentsNames.count > capacity {
            recentsNames.removeLast()
        }
    }

    private func loadNames() -> [String] {
        let userDefault = UserDefaults.standard.object(forKey: userDefaultsKey)
        if let array = userDefault as? [String] {
            let queryTokens = filter.normalizedTokens
            return array.filter({ (name) -> Bool in
                return name.matchesTableViewSearchQueryTokens(queryTokens) && fontFamilyExists(name)
            })
        } else {
            return []
        }
    }

    private func fontFamilyExists(_ name: String) -> Bool {
        return NSFontManager.shared.availableFontFamilies.contains(name)
    }

    func reload() {
        recentsNames = loadNames()
    }
}
