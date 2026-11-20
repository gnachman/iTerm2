//
//  StatusBarComponentFactoryClassCheckTests.swift
//  ModernTests
//
//  -[iTermStatusBarBuiltInComponentFactory initWithCoder:] reads a class name
//  from an archive that can come from the drag pasteboard, so another
//  application can name any class. The factory later sends that class
//  +statusBarComponentDefaultKnobs and alloc/initWithConfiguration:scope:.
//  Decoding must accept only classes that conform to iTermStatusBarComponent
//  (the protocol that declares both) and must keep accepting every real
//  component class.
//
//  The archives are made and read with the same helpers the status bar
//  setup UI uses (+[NSData it_dataWithArchivedObject:] and
//  -[NSData it_unarchivedObjectOfClasses:]), with the factory as the root
//  object instead of the setup element that wraps it on the pasteboard.
//  Nothing here instantiates a component.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class StatusBarComponentFactoryClassCheckTests: XCTestCase {
    // An archive of a factory naming `theClass`, as the setup UI writes it.
    private func archive(naming theClass: AnyClass) -> Data {
        let factory = iTermStatusBarBuiltInComponentFactory(with: theClass)
        return NSData.it_data(withArchivedObject: factory) as Data
    }

    // An archive of a factory whose "class" key holds `className`, which need
    // not name a class that exists.
    private func archive(namingClassNamed className: String) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName(NSStringFromClass(iTermStatusBarBuiltInComponentFactory.self),
                              for: ClassNameOnlyFactory.self)
        archiver.encode(ClassNameOnlyFactory(archivedName: className), forKey: "object")
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func decode(_ data: Data) -> iTermStatusBarBuiltInComponentFactory? {
        let object = (data as NSData).it_unarchivedObject(ofClasses: [iTermStatusBarBuiltInComponentFactory.self])
        return object as? iTermStatusBarBuiltInComponentFactory
    }

    // MARK: - Rejected

    func testArchiveNamingANonComponentClassDecodesToNil() {
        for theClass: AnyClass in [NSObject.self, Process.self] {
            XCTAssertNil(decode(archive(naming: theClass)),
                         "\(NSStringFromClass(theClass)) is not a status bar component and must not decode")
        }
    }

    func testArchiveNamingANonexistentClassDecodesToNil() {
        XCTAssertNil(decode(archive(namingClassNamed: "iTermNoSuchStatusBarComponentClass")))
    }

    // The hand-built archive above is only meaningful if the same form with a
    // real component class does decode.
    func testHandBuiltArchiveNamingARealComponentDecodes() {
        let name = "iTermStatusBarClockComponent"
        XCTAssertEqual(decode(archive(namingClassNamed: name))?.componentDescription(), name)
    }

    // MARK: - Accepted

    // Every class of the app that conforms to iTermStatusBarComponent, found
    // at run time (the setup palette's list is a local in
    // -[iTermStatusBarSetupViewController loadElements] and cannot be reached
    // from a test). This includes the abstract base classes, which also
    // conform; accepting them is today's behavior.
    func testEveryComponentClassRoundTrips() throws {
        let names = BindingObjCRuntime.shared.appClassesConforming(to: "iTermStatusBarComponent")
        XCTAssertGreaterThan(names.count, 20, "the run-time enumeration found too few component classes: \(names)")
        XCTAssertTrue(names.contains("iTermStatusBarClockComponent"))
        XCTAssertTrue(names.contains("iTermStatusBarRPCProvidedTextComponent"))
        for name in names {
            let theClass: AnyClass = try XCTUnwrap(NSClassFromString(name), name)
            let decoded = decode(archive(naming: theClass))
            XCTAssertNotNil(decoded, "\(name) was rejected")
            XCTAssertEqual(decoded?.componentDescription(), name)
        }
    }

    // Every component class named by a status bar layout in a profile of the
    // stored-state corpus survives a drag archive. Layouts in profiles are
    // dictionaries loaded by +[iTermStatusBarLayout
    // componentsArrayFromDictionary:scope:], which this change does not touch;
    // the factory archive itself never occurs in the corpus.
    func testComponentClassesOfCorpusLayoutsRoundTrip() throws {
        let corpus = BindingRepository.url("tests/stored-state-corpus")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: corpus, includingPropertiesForKeys: nil))
        var names = Set<String>()
        for case let url as URL in enumerator where url.lastPathComponent == "com.googlecode.iterm2.plist" && url.path.contains("/Library/Preferences/") {
            let data = try Data(contentsOf: url)
            let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            for profile in plist["New Bookmarks"] as? [[String: Any]] ?? [] {
                let layout = profile["Status Bar Layout"] as? [String: Any]
                for component in layout?["components"] as? [[String: Any]] ?? [] {
                    if let name = component["class"] as? String {
                        names.insert(name)
                    }
                }
            }
        }
        XCTAssertFalse(names.isEmpty, "no status bar layout found in the corpus")
        for name in names.sorted() {
            let theClass: AnyClass = try XCTUnwrap(NSClassFromString(name), name)
            XCTAssertEqual(decode(archive(naming: theClass))?.componentDescription(), name)
        }
    }
}

// Encodes only the "class" key, under the factory's archived class name, so
// that a test can write a name that does not resolve.
@objc(StatusBarComponentFactoryClassCheckTestsClassNameOnlyFactory)
private final class ClassNameOnlyFactory: NSObject, NSCoding {
    let archivedName: String

    init(archivedName: String) {
        self.archivedName = archivedName
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func encode(with coder: NSCoder) {
        coder.encode(archivedName as NSString, forKey: "class")
    }
}
