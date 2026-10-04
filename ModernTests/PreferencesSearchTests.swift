//
//  PreferencesSearchTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermPreferencesSearchTests.m. Covers document tokenization and
//  querying in iTermPreferencesSearchEngine.
//

import XCTest
@testable import iTerm2SharedARC

final class PreferencesSearchTests: XCTestCase {
    private var engine: iTermPreferencesSearchEngine!

    override func setUp() {
        super.setUp()
        engine = iTermPreferencesSearchEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    private func document(_ displayName: String,
                          identifier: String,
                          keywordPhrases: [String] = []) -> iTermPreferencesSearchDocument {
        return iTermPreferencesSearchDocument(displayName: displayName,
                                              identifier: identifier,
                                              keywordPhrases: keywordPhrases,
                                              profileTypes: .all)
    }

    private func index(_ documents: iTermPreferencesSearchDocument...) {
        for document in documents {
            engine.addDocument(toIndex: document)
        }
    }

    private func matches(_ query: String) -> [iTermPreferencesSearchDocument] {
        return engine.documents(matchingQuery: query, allowedProfileTypes: .all)
    }

    private func identifiersMatching(_ query: String) -> Set<String> {
        return Set(matches(query).map { $0.identifier })
    }

    func testDocumentTokenization() {
        let doc = document("foo bar",
                           identifier: "id1",
                           keywordPhrases: ["lorem ipsum dolor", "sit amet"])
        let expected = ["foo", "bar", "lorem", "ipsum", "dolor", "sit", "amet"].sorted()
        XCTAssertEqual(doc.allKeywords.sorted(), expected)
    }

    func testSimple() {
        let doc1 = document("1", identifier: "id1")
        let doc2 = document("2", identifier: "id2")
        index(doc1, doc2)

        XCTAssertEqual(matches("1"), [doc1])
    }

    func testMultiword() {
        index(document("foo bar", identifier: "id1"),
              document("bar baz foo", identifier: "id2"),
              document("baz foo", identifier: "id3"))

        XCTAssertEqual(identifiersMatching("bar foo"), ["id1", "id2"])
    }

    func testPrefixMatches_SingleLetterMatchesEveryWordStartingWithIt() {
        index(document("aa ab ba", identifier: "id1"),
              document("a", identifier: "id2"),
              document("abc", identifier: "id3"))

        XCTAssertEqual(identifiersMatching("a"), ["id1", "id2", "id3"])
    }

    func testPrefixMatches_EveryQueryTokenMustMatch() {
        index(document("aa ab ba", identifier: "id1"),
              document("a", identifier: "id2"),
              document("abc", identifier: "id3"))

        XCTAssertEqual(identifiersMatching("a b"), ["id1"])
    }

    func testPrefixMatches_LongerPrefix() {
        index(document("aa ab ba", identifier: "id1"),
              document("a", identifier: "id2"),
              document("abc", identifier: "id3"))

        XCTAssertEqual(identifiersMatching("ab"), ["id1", "id3"])
    }

    func testDocumentWithKey() {
        let doc1 = document("one", identifier: "id1")
        let doc2 = document("two", identifier: "id2")
        index(doc1, doc2)

        XCTAssertEqual(engine.document(withKey: "id2"), doc2)
        XCTAssertNil(engine.document(withKey: "id3"))
    }
}
