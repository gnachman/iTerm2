//
//  iTermBrowserVisitsFinder.swift
//  iTerm2
//
//  Created by George Nachman on 8/11/25.
//

@objc
class iTermBrowserVisitsFinder: NSObject {
    private static var cache: (String, [iTermTriple<NSString, NSURL, NSString>])?
    private static var busy = MutableAtomicObject(0)

    // Returns array of (Title, URL, browser user ID). Does not search /dev/null-mode instances.
    @objc(historyMatchingSubstring:)
    static func historyMatching(substring: String) -> [iTermTriple<NSString, NSURL, NSString>] {
        if busy.value > 0 {
            return cachedIfValid(for: substring)
        }
        let group = DispatchGroup()
        var results = [iTermTriple<NSString, NSURL, NSString>]()
        group.enter()

        busy.mutate { $0 + 1 }
        Task.detached(priority: .userInitiated) {
            defer {
                group.leave()
                busy.mutate { $0 - 1 }
            }
            results = await find(substring: substring)
        }

        switch group.wait(timeout: .now() + 0.05) {
        case .success:
            return results
        case .timedOut:
            return cachedIfValid(for: substring)
        }
    }

    private static func find(substring: String) async -> [iTermTriple<NSString, NSURL, NSString>] {
        var results = [iTermTriple<NSString, NSURL, NSString>]()
        for db in await BrowserDatabase.allPersistentInstances {
            let visit = await db.searchVisits(terms: substring, maxAge: 90 * 24 * 60 * 60, minCount: 2, offset: 0, limit: 50)
            let triples = visit.compactMap { visit -> iTermTriple<NSString, NSURL, NSString>? in
                return triple(for: visit, in: db)
            }
            results.append(contentsOf: triples)
        }
        return results
    }

    private static func triple(for visit: BrowserVisits,
                               in db: BrowserDatabase) -> iTermTriple<NSString, NSURL, NSString>? {
        guard let url = URL(string: visit.url) else {
            return nil
        }
        let title = (visit.title ?? "")
        let userID: String = db.userID!
        let triple = iTermTriple(object: title as NSString,
                                 andObject: url as NSURL,
                                 object: userID as NSString)
        return triple
    }

    private static func cachedIfValid(for substring: String) -> [iTermTriple<NSString, NSURL, NSString>] {
        if let cache, substring.range(of: cache.0) != nil {
            return cache.1
        }
        return []
    }
}
