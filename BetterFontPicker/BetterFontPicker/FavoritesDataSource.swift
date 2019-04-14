//
//  FavoritesDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

protocol FavoritesDataSourceDelegate: class {
    func favoritesDataSource(_ dataSource: FavoritesDataSource,
                             didInsertRowAtIndex index: Int)
    func favoritesDataSource(_ dataSource: FavoritesDataSource,
                             didDeleteRowAtIndex index: Int,
                             name: String)
}

@objc(BFPFavoritesDataSource)
class FavoritesDataSource: NSObject, FontListDataSource {
    private let userDefaultsKey = "NoSyncBFPFavorites"
    weak var delegate: FavoritesDataSourceDelegate?
    var names: [String] {
        return favoriteNames
    }
    override init() {
        super.init()
    }
    var isSeparator: Bool {
        return false
    }
    lazy var favoriteNames: Array<String> = {
        return loadNames()
    }()
    private var internalFilter = ""
    var filter: String {
        get {
            return internalFilter
        }
        set {
            internalFilter = newValue
            favoriteNames = loadNames()
        }
    }

    func makeFavorite(_ name: String) {
        if !favoriteNames.contains(name) {
            let index = favoriteNames.count
            favoriteNames.append(name)
            UserDefaults.standard.set(favoriteNames, forKey: userDefaultsKey)
            delegate?.favoritesDataSource(self, didInsertRowAtIndex: index)
        }
    }

    func removeFavorite(_ name: String) {
        if let index = favoriteNames.firstIndex(of: name) {
            favoriteNames.remove(at: index)
            UserDefaults.standard.set(favoriteNames, forKey: userDefaultsKey)
            delegate?.favoritesDataSource(self, didDeleteRowAtIndex: index, name: name)
        }
    }

    func toggleFavorite(_ name: String) {
        if favoriteNames.contains(name) {
            removeFavorite(name)
        } else {
            makeFavorite(name)
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

    func reload() {
        favoriteNames = loadNames()
    }

    private func fontFamilyExists(_ name: String) -> Bool {
        return NSFontManager.shared.availableFontFamilies.contains(name)
    }

}
