//
//  ComplexCharRegistryTests.swift
//  iTerm2
//
//  The registry maps strings of more than one code point (combining marks, emoji, and so on) to
//  16-bit codes stored in screen characters, and back.
//

import XCTest
@testable import iTerm2SharedARC

final class ComplexCharRegistryTests: XCTestCase {
    private func code(_ registry: ComplexCharRegistry, _ string: String) -> unichar {
        return registry.lazilyCreatedCode(for: string as NSString, isSpacingCombiningMark: .false)
    }

    func testTheSameStringGetsTheSameCode() {
        let registry = ComplexCharRegistry()
        let a = code(registry, "e\u{301}")
        let b = code(registry, "a\u{308}")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(code(registry, "e\u{301}"), a)
        XCTAssertEqual(code(registry, "a\u{308}"), b)
        XCTAssertEqual(registry.string(for: Int(a)), "e\u{301}")
        XCTAssertEqual(registry.code(for: "a\u{308}")?.intValue, Int(b))
    }

    // Strings whose hashes collide still get codes of their own, and each finds its own.
    func testStringsWithCollidingHashes() {
        let registry = ComplexCharRegistry(hash: { _ in 7 })
        let strings = ["e\u{301}", "a\u{308}", "o\u{302}", "n\u{303}", "👍🏽"]
        let codes = strings.map { code(registry, $0) }
        XCTAssertEqual(Set(codes).count, strings.count)
        for (string, expected) in zip(strings, codes) {
            XCTAssertEqual(code(registry, string), expected)
            XCTAssertEqual(registry.string(for: Int(expected)), string as NSString)
        }
    }

    // After the codes wrap, a new string takes the oldest code, and the string that had it no
    // longer maps to it.
    func testWrappingReassignsTheOldestCode() {
        let registry = ComplexCharRegistry(maxKey: 8)
        let first = code(registry, "s0")
        for i in 1..<12 {
            _ = code(registry, "s\(i)")
        }
        XCTAssertTrue(registry.hasWrapped)
        let reused = registry.string(for: Int(first))
        XCTAssertNotEqual(reused, "s0")
        XCTAssertNil(registry.code(for: "s0"))
        let again = code(registry, "s0")
        XCTAssertEqual(registry.string(for: Int(again)), "s0")
        XCTAssertEqual(code(registry, "s0"), again)
    }

    // A single code point is stored as itself; anything longer goes through the registry.
    func testSetComplexChar() {
        let registry = ComplexCharRegistry()
        var c = screen_char_t()
        registry.setComplexChar(in: &c, string: "x", normalization: .none, isSpacingCombiningMark: false)
        XCTAssertEqual(c.code, unichar(UInt8(ascii: "x")))
        XCTAssertEqual(c.complexChar, 0)

        registry.setComplexChar(in: &c, string: "e\u{301}", normalization: .none, isSpacingCombiningMark: false)
        XCTAssertEqual(c.complexChar, 1)
        XCTAssertEqual(registry.string(for: Int(c.code)), "e\u{301}")
    }

    func testSpacingCombiningMarksAreRemembered() {
        let registry = ComplexCharRegistry()
        let mark = registry.lazilyCreatedCode(for: "a\u{903}", isSpacingCombiningMark: .true)
        let other = code(registry, "e\u{301}")
        XCTAssertTrue(registry.codeIsSpacingCombiningMark(mark))
        XCTAssertFalse(registry.codeIsSpacingCombiningMark(other))
    }

    // What's saved with the window state restores the same mappings.
    func testSavedStateRestores() {
        let registry = ComplexCharRegistry()
        let a = code(registry, "e\u{301}")
        let mark = registry.lazilyCreatedCode(for: "a\u{903}", isSpacingCombiningMark: .true)

        let restored = ComplexCharRegistry()
        restored.load(charMap: registry.complexCharMap,
                      spacingCombiningMarks: Array(registry.spacingCombiningMarkCodeNumbers),
                      inverseMap: registry.inverseComplexCharMap,
                      nextKey: registry.peekNextCode,
                      hasWrapped: registry.hasWrapped)
        XCTAssertEqual(code(restored, "e\u{301}"), a)
        XCTAssertEqual(restored.string(for: Int(mark)), "a\u{903}")
        XCTAssertTrue(restored.codeIsSpacingCombiningMark(mark))
        XCTAssertEqual(restored.peekNextCode, registry.peekNextCode)
        XCTAssertNotEqual(code(restored, "o\u{302}"), a)
    }

    // Threads looking up and creating codes for overlapping strings all agree on each string's
    // code, every code maps back to its string, and racing to create one string's code allocates
    // only one.
    func testConcurrentLookupsAgree() {
        let registry = ComplexCharRegistry()
        let strings = (0..<200).map { "x\($0)\u{301}" }
        let firstCode = Int(registry.peekNextCode)
        let results = MutableAtomicObject([[unichar]]())
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            var codes = [unichar]()
            for round in 0..<20 {
                for (i, string) in strings.enumerated() where (i + round + worker) % 3 != 0 || round > 10 {
                    _ = code(registry, string)
                }
                if round == 19 {
                    codes = strings.map { code(registry, $0) }
                }
            }
            results.mutableAccess { $0.append(codes) }
        }
        let all = results.value
        XCTAssertEqual(all.count, 8)
        for codes in all {
            XCTAssertEqual(codes, all[0])
        }
        for (string, c) in zip(strings, all[0]) {
            XCTAssertEqual(registry.string(for: Int(c)), string as NSString)
        }
        XCTAssertEqual(Int(registry.peekNextCode) - firstCode, strings.count)
        XCTAssertEqual(registry.complexCharMap.count, strings.count)
        XCTAssertEqual(Set(registry.complexCharMap.values).count, strings.count)
    }
}
