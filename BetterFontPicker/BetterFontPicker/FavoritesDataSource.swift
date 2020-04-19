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
        return filteredFavoriteNames
    }
    var isSeparator: Bool {
        return false
    }
    private var filteredFavoriteNames: Array<String> {
        let queryTokens = filter.normalizedTokens
        return persistentFavoriteNames.filter {
            return $0.matchesTableViewSearchQueryTokens(queryTokens) && fontFamilyExists($0)
        }
    }
    private var cachedNames: [String]? = nil
    private var persistentFavoriteNames: [String] {
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            cachedNames = newValue
        }
        get {
            if let cachedNames = cachedNames {
                return cachedNames
            }
            let names = UserDefaults.standard.object(forKey: userDefaultsKey) as? [String] ?? []
            cachedNames = names
            return names
        }
    }
    private var unfilteredFavoriteNames: [String] {
        get {
            return persistentFavoriteNames
        }
        set {
            persistentFavoriteNames = newValue
        }
    }
    var filter: String = ""

    func makeFavorite(_ name: String) {
        guard !unfilteredFavoriteNames.contains(name) else {
            return
        }
        persistentFavoriteNames = persistentFavoriteNames + [name]
        guard let index = filteredFavoriteNames.firstIndex(of: name) else {
            return
        }
        delegate?.favoritesDataSource(self, didInsertRowAtIndex: index)
    }

    func removeFavorite(_ name: String) {
        let maybeTableIndex = filteredFavoriteNames.firstIndex(of: name)
        guard let index = unfilteredFavoriteNames.firstIndex(of: name) else {
            return
        }
        var temp = unfilteredFavoriteNames
        temp.remove(at: index)
        unfilteredFavoriteNames = temp
        guard let tableIndex = maybeTableIndex else {
            return
        }
        delegate?.favoritesDataSource(self, didDeleteRowAtIndex: tableIndex, name: name)
    }

    func toggleFavorite(_ name: String) {
        if unfilteredFavoriteNames.contains(name) {
            removeFavorite(name)
        } else {
            makeFavorite(name)
        }
    }

    func reload() {
        cachedNames = nil
    }

    private func fontFamilyExists(_ name: String) -> Bool {
        return NSFontManager.shared.availableFontFamilies.contains(name)
    }

}
