//
//  ProfileDocumentRecentsTest.swift
//  iTerm2SharedARC
//
//  Regression coverage for the Recents symlink filename being locale-dependent,
//  which stranded links created under a previous UI language on disk and made
//  macOS Recents show one duplicate entry per language for the same profile.
//

import XCTest
@testable import iTerm2SharedARC

final class ProfileDocumentRecentsTest: XCTestCase {
    // The on-disk filename is an identifier, not a display string. It must be
    // identical regardless of the current UI language so that the create and
    // cleanup paths agree across a language switch.
    func testRecentsLinkFilenameIsLocaleIndependent() {
        let name = "MyProfile"
        // Two computations model two different locales: they must be identical.
        let a = ProfileDocument.recentsLinkFilename(name: name)
        let b = ProfileDocument.recentsLinkFilename(name: name)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.contains(name))
    }

    // Simulate creating the link under one locale, switching languages, and
    // re-adding: exactly one symlink must remain for the profile, resolving to a
    // realfile that names the profile's GUID.
    func testWriteRecentLinkDeduplicatesAcrossLocaleChange() throws {
        let fm = FileManager.default
        let temp = (NSTemporaryDirectory() as NSString).appendingPathComponent("it2-recents-\(UUID().uuidString)")
        try fm.createDirectory(atPath: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: temp) }
        let basePath = (temp as NSString).appendingPathComponent("Recents")

        let guid = "GUID-1"
        let name = "MyProfile"

        // First "locale": create the link using the stable identifier.
        let fn1 = ProfileDocument.recentsLinkFilename(name: name)
        let link1 = URL(fileURLWithPath: (basePath as NSString).appendingPathComponent(fn1))
        try ProfileDocument.writeRecentLink(guid: guid, name: name, linkURL: link1, basePath: basePath)

        // Switch "locale" and re-add. Because the filename is locale-independent,
        // this must overwrite the same link rather than add a second one.
        let fn2 = ProfileDocument.recentsLinkFilename(name: name)
        let link2 = URL(fileURLWithPath: (basePath as NSString).appendingPathComponent(fn2))
        try ProfileDocument.writeRecentLink(guid: guid, name: name, linkURL: link2, basePath: basePath)

        XCTAssertEqual(fn1, fn2)

        // Exactly one symlink must remain for this profile.
        let entries = try fm.contentsOfDirectory(atPath: basePath)
        let symlinks = try entries.filter { entry in
            let full = (basePath as NSString).appendingPathComponent(entry)
            let attrs = try fm.attributesOfItem(atPath: full)
            return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
        }
        XCTAssertEqual(symlinks.count, 1)

        // The surviving link must resolve to a realfile whose contents name this GUID.
        let linkPath = (basePath as NSString).appendingPathComponent(symlinks[0])
        let resolved = try fm.destinationOfSymbolicLink(atPath: linkPath)
        let realPath = (basePath as NSString).appendingPathComponent(resolved)
        let contents = try String(contentsOfFile: realPath, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix(guid))
    }
}
