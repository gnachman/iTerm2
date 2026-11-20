//
//  BindingTests.swift
//  ModernTests
//
//  The binding tests of docs/swift-migration/phase0.md section 3. They parse
//  the files that name classes, methods and keys as strings (xibs, the
//  scripting definition, Info.plist, the Core Data model, the stored-state
//  corpus, and the registry of names persisted or sent between processes)
//  and ask the Objective-C runtime of the test host, where every app class
//  is loaded, whether each name resolves. Nothing is instantiated.
//
//  Source files are found through the repository path baked in at build time
//  (BindingRepository, from #filePath), as other ModernTests do; nothing is
//  copied into the test bundle. Which xibs are compiled into the app is read
//  from the app bundle the tests run in: every compiled nib is matched to its
//  source, and every source under the roots of BindingTestTables is required
//  to be compiled.
//
//  Anything that does not resolve today is listed in
//  BindingTestTables.knownFailures. A test fails on a new problem and on a
//  known failure that no longer happens.
//
//  The checkers themselves are proven by BindingCheckerFixtureTests.
//

import XCTest
@testable import iTerm2SharedARC

// One of each kind of Swift stored property, for
// BindingTests.testSwiftStoredPropertiesMatchFoundationKVC. A stored property
// without @objc still appears in class_copyIvarList under its own name, but
// with an empty type encoding, and key-value coding does not use it.
final class BindingKVCProbe: NSObject {
    @IBOutlet weak var outlet: NSObject!
    @objc var objcVar: NSObject?
    var plainObject: NSObject?
    weak var plainWeak: NSObject?
    private var privateObject: NSObject?
    var plainInt: Int = 0
}

enum BindingTestInputs {
    struct NibInventory {
        // Repository-relative paths of the sources of the app's nibs.
        var sources = [String]()
        var problems = [BindingProblem]()
        var compiledNibCount = 0
    }

    static let runtime = BindingObjCRuntime.shared
    static let queries = BindingRuntimeQueries(runtime)

    static let applicationClass: String = {
        let principal = Bundle.main.infoDictionary?["NSPrincipalClass"] as? String ?? "NSApplication"
        return runtime.resolveClass(principal) ?? "NSApplication"
    }()

    static let nibInventory: NibInventory = BindingTiming.measure("nib inventory") { makeNibInventory() }

    private static func isCompiledNib(_ url: URL) -> Bool {
        return ["nib", "storyboardc"].contains(url.pathExtension)
    }

    private static func isSource(_ url: URL) -> Bool {
        return ["xib", "storyboard"].contains(url.pathExtension)
    }

    // Compiled nibs below `directory`, not descending into a nib (a nib can
    // be a directory) or into symbolic links (a framework's Resources and
    // Versions/Current), so each nib is found once.
    private static func compiledNibs(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var result = [URL]()
        for case let url as URL in enumerator {
            if url.lastPathComponent == "PlugIns" && url.deletingLastPathComponent().lastPathComponent == "Contents" {
                enumerator.skipDescendants()
                continue
            }
            if isCompiledNib(url) {
                result.append(url)
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private static func makeNibInventory() -> NibInventory {
        var inventory = NibInventory()
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        let bundlePath = bundle.path + "/"
        func location(of url: URL) -> String {
            return String(url.standardizedFileURL.path.dropFirst(bundlePath.count))
        }
        func problem(_ kind: String, _ element: String, _ name: String, _ detail: String) {
            inventory.problems.append(BindingProblem(file: "iTerm2.app", kind: kind, elementID: element, label: nil, name: name, detail: detail))
        }
        var used = Set<String>()
        var allSources = Set<String>()
        var nibsByLocation = [String: [URL]]()
        for nib in compiledNibs(in: bundle) {
            let path = location(of: nib)
            if BindingTestTables.excludedNibLocations.keys.contains(where: { path.hasPrefix($0 + "/") }) {
                continue
            }
            guard let entry = BindingTestTables.nibSourceRoots.first(where: { path.hasPrefix($0.bundleLocation + "/") }) else {
                problem("unmappedNib", path, nib.deletingPathExtension().lastPathComponent, "is a compiled nib in no location of BindingTestTables.nibSourceRoots or excludedNibLocations")
                continue
            }
            nibsByLocation[entry.bundleLocation, default: []].append(nib)
        }
        for entry in BindingTestTables.nibSourceRoots {
            var candidates = [String: [String]]()
            for root in entry.sourceRoots {
                guard let enumerator = FileManager.default.enumerator(at: BindingRepository.url(root), includingPropertiesForKeys: nil) else {
                    continue
                }
                for case let url as URL in enumerator where isSource(url) {
                    let relative = BindingRepository.relativePath(url)
                    candidates[url.deletingPathExtension().lastPathComponent, default: []].append(relative)
                    allSources.insert(relative)
                }
            }
            for nib in nibsByLocation[entry.bundleLocation] ?? [] {
                inventory.compiledNibCount += 1
                let name = nib.deletingPathExtension().lastPathComponent
                let found = (candidates[name] ?? []).sorted()
                switch found.count {
                case 0:
                    problem("nibWithoutSource", location(of: nib), name, "has no source xib or storyboard under \(entry.sourceRoots)")
                case 1:
                    if !used.contains(found[0]) {
                        used.insert(found[0])
                        inventory.sources.append(found[0])
                    }
                default:
                    problem("ambiguousSource", location(of: nib), name, "has several candidate sources: \(found)")
                }
            }
        }
        for source in allSources.subtracting(used).sorted() {
            problem("sourceNotCompiled", source, (source as NSString).lastPathComponent, "is under a source root but no compiled nib of that name is in the app")
        }
        inventory.sources.sort()
        return inventory
    }

    struct ParsedXibs {
        var documents = [BindingXibDocument]()
        var errors = [String]()
    }

    static let xibs: ParsedXibs = BindingTiming.measure("parse xibs") {
        var parsed = ParsedXibs()
        for source in nibInventory.sources {
            do {
                let data = try Data(contentsOf: BindingRepository.url(source))
                parsed.documents.append(try BindingXibDocument.parse(data, path: source))
            } catch {
                parsed.errors.append("\(source): \(error)")
            }
        }
        return parsed
    }

    static let xibResults: [BindingXibResult] = BindingTiming.measure("check xibs") {
        xibs.documents.map {
            BindingXibChecker.check($0, queries: queries, applicationClass: applicationClass)
        }
    }
}

final class BindingTests: XCTestCase {
    private func assertKnown(_ problems: [BindingProblem],
                             kinds: Set<String>,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        let comparison = BindingKnownFailures.compare(problems, known: BindingTestTables.knownFailures) { key in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            return parts.count > 1 && kinds.contains(String(parts[1]))
        }
        if let message = BindingKnownFailures.message(comparison) {
            XCTFail(message, file: file, line: line)
        }
    }

    // The checker's verdict on a key, through the real BindingObjCRuntime and
    // the real key-value coding search, equals what Foundation does when the
    // key is set and read on an instance. A Swift stored property that has
    // lost @IBOutlet or @objc must not count as a key.
    func testSwiftStoredPropertiesMatchFoundationKVC() throws {
        try BindingTiming.measure("testSwiftStoredPropertiesMatchFoundationKVC") {
            let runtime = BindingObjCRuntime.shared
            let queries = BindingRuntimeQueries(runtime)
            let className = try XCTUnwrap(runtime.resolveClass(NSStringFromClass(BindingKVCProbe.self)))
            let expected: [(key: String, isKey: Bool)] = [
                ("outlet", true),
                ("objcVar", true),
                ("plainObject", false),
                ("plainWeak", false),
                ("privateObject", false),
                ("plainInt", false),
            ]
            for (key, isKey) in expected {
                let probe = BindingKVCProbe()
                let value: Any = key == "plainInt" ? NSNumber(value: 3) : NSObject()
                let foundationSets = (try? ObjCTry { probe.setValue(value, forKey: key) }) != nil
                let foundationReads = (try? ObjCTry { _ = probe.value(forKey: key) }) != nil
                let checkerSetter = queries.kvcSetter(className, key: key)
                let checkerGetter = queries.kvcGetter(className, key: key)
                print("BINDING-KVC-PROBE \(key): checker set \(checkerSetter ?? "none"), Foundation set \(foundationSets); checker get \(checkerGetter ?? "none"), Foundation get \(foundationReads)")
                XCTAssertEqual(checkerSetter != nil, foundationSets, "settable \(key): checker says \(checkerSetter ?? "none")")
                XCTAssertEqual(checkerGetter != nil, foundationReads, "readable \(key): checker says \(checkerGetter ?? "none")")
                XCTAssertEqual(foundationSets, isKey, "Foundation setValue:forKey: \(key)")
                XCTAssertEqual(foundationReads, isKey, "Foundation valueForKey: \(key)")
            }
        }
    }

    // Every compiled nib in the app has exactly one source, and every source
    // under the roots is compiled.
    func testXibSourcesMatchCompiledNibs() {
        BindingTiming.measure("testXibSourcesMatchCompiledNibs") {
            let inventory = BindingTestInputs.nibInventory
            print("BINDING-COUNTS compiled nibs \(inventory.compiledNibCount), sources \(inventory.sources.count)")
            XCTAssertGreaterThan(inventory.sources.count, 0)
            assertKnown(inventory.problems, kinds: ["unmappedNib", "nibWithoutSource", "ambiguousSource", "sourceNotCompiled"])
        }
    }

    // Custom classes, outlets, actions with a target, bindings and
    // user-defined runtime attributes of every xib compiled into the app.
    func testXibBindings() {
        BindingTiming.measure("testXibBindings") {
            XCTAssertEqual(BindingTestInputs.xibs.errors, [])
            let results = BindingTestInputs.xibResults
            let counts = results.map(\.counts).reduce(BindingXibCounts(), +)
            print("BINDING-COUNTS xibs \(results.count), custom classes \(counts.customClasses), outlets \(counts.outlets), actions to objects \(counts.actionsToObjects), to File's Owner \(counts.actionsToFileOwner), to Application \(counts.actionsToApplication), to First Responder \(counts.actionsToFirstResponder), bindings \(counts.bindings), runtime attributes \(counts.runtimeAttributes), deeper keys unchecked \(counts.uncheckedDeeperKeys)")
            XCTAssertGreaterThan(counts.outlets, 0)
            assertKnown(results.flatMap(\.problems),
                        kinds: ["customClass", "elementClass", "outlet", "outletCollection", "outletDestination",
                                "outletCollectionDestination", "action", "actionTarget", "binding",
                                "bindingDestination", "runtimeAttribute"])
        }
    }

    // Every First Responder action has an implementer in the app or AppKit,
    // and the app's implementers equal BindingFirstResponderTable.
    func testFirstResponderActions() {
        BindingTiming.measure("testFirstResponderActions") {
            let actions = BindingTestInputs.xibResults.flatMap(\.firstResponderActions)
            let result = BindingTiming.measure("first responder implementers") {
                BindingFirstResponderChecker.check(actions,
                                                            runtime: BindingTestInputs.runtime,
                                                            recorded: BindingFirstResponderTable.recorded)
            }
            let selectors = Set(actions.map(\.selector))
            let appImplementers = Set(result.implementers.values.flatMap(\.app))
            print("BINDING-COUNTS first responder actions \(actions.count), distinct selectors \(selectors.count), recorded \(BindingFirstResponderTable.recorded.count), distinct app implementer classes \(appImplementers.count), selectors with no app implementer \(result.implementers.values.filter { $0.app.isEmpty }.count)")
            assertKnown(result.problems, kinds: ["firstResponderAction"])
            if !result.tableDifferences.isEmpty {
                XCTFail("The app classes implementing First Responder actions differ from BindingFirstResponderTable.recorded. If the change is intended, apply these lines to ModernTests/BindingFirstResponderTable.swift:\n"
                        + result.tableDifferences.joined(separator: "\n")
                        + "\n--- lines ---\n"
                        + result.pasteLines.joined(separator: "\n"))
            }
        }
    }

    // iTerm2.sdef: classes, keys, element accessors, command classes and the
    // methods that handle commands.
    func testScriptingDefinition() throws {
        try BindingTiming.measure("testScriptingDefinition") {
            let path = "iTerm2.sdef"
            let root = try BindingXMLParser.parse(contentsOf: BindingRepository.url(path))
            let queries = BindingTestInputs.queries
            var forwarding = [String: [String]]()
            for (className, protocolName) in BindingTestTables.sdefForwardingProtocols {
                let targets = BindingTestInputs.runtime.appClassesConforming(to: protocolName)
                XCTAssertFalse(targets.isEmpty, "no app class conforms to \(protocolName)")
                forwarding[className] = targets
            }
            let result = BindingSdefChecker.check(root, path: path, queries: queries) { forwarding[$0] }
            let c = result.counts
            print("BINDING-COUNTS sdef classes \(c.classes), properties \(c.properties), elements \(c.elements), responds-to \(c.respondsTo), commands \(c.commands) (with a cocoa class \(c.commandClasses)), value types \(c.valueTypes), forwarding targets \(forwarding)")
            XCTAssertNotNil(Bundle.main.url(forResource: "iTerm2", withExtension: "sdef"), "the app bundle has no iTerm2.sdef")
            assertKnown(result.problems,
                        kinds: ["commandClass", "valueTypeClass", "class", "propertyKey", "propertySetter",
                                "elementKey", "elementInsert", "respondsToCommand", "respondsToMethod"])
        }
    }

    // The app's Info.plist: principal class, services and document classes.
    func testInfoPlist() throws {
        try BindingTiming.measure("testInfoPlist") {
            let plist = try XCTUnwrap(Bundle.main.infoDictionary)
            let result = BindingInfoPlistChecker.check(plist,
                                                       file: "iTerm2.app/Contents/Info.plist",
                                                       queries: BindingTestInputs.queries,
                                                       servicesProvider: BindingTestTables.servicesProvider)
            let c = result.counts
            print("BINDING-COUNTS Info.plist principal class \(c.principalClass), services \(c.services), document types \(c.documentTypes), document classes \(c.documentClasses)")
            XCTAssertEqual(c.principalClass, 1)
            assertKnown(result.problems, kinds: ["principalClass", "servicesProvider", "serviceMessage", "documentClass"])
        }
    }

    // Every entity class of the Core Data model compiled into the app.
    func testCoreDataModel() throws {
        try BindingTiming.measure("testCoreDataModel") {
            // The only model in the repository; compiled to Model.momd.
            let path = "Model.xcdatamodeld/Model.xcdatamodel/contents"
            XCTAssertNotNil(Bundle.main.url(forResource: "Model", withExtension: "momd"), "the app bundle has no Model.momd")
            let root = try BindingXMLParser.parse(contentsOf: BindingRepository.url(path))
            let result = BindingCoreDataChecker.check(root, file: path, queries: BindingTestInputs.queries)
            print("BINDING-COUNTS Core Data entities \(result.entities)")
            XCTAssertGreaterThan(result.entities, 0)
            assertKnown(result.problems, kinds: ["entityClass"])
        }
    }

    // Classes persisted or sent between processes by name, the XPC
    // protocols' selectors, and the window restoration classes, from
    // docs/swift-migration/reflective-sites.md section 6.
    func testPersistedAndWireNames() {
        BindingTiming.measure("testPersistedAndWireNames") {
            let problems = BindingPersistedNamesChecker.check(names: BindingTestTables.persistedNames,
                                                              protocols: BindingTestTables.xpcProtocols,
                                                              restorationClasses: BindingTestTables.restorationClasses,
                                                              restorationSelector: BindingTestTables.restorationSelector,
                                                              queries: BindingTestInputs.queries)
            print("BINDING-COUNTS persisted or wire class names \(BindingTestTables.persistedNames.count), XPC selectors \(BindingTestTables.xpcProtocols.map(\.selectors.count).reduce(0, +)), restoration classes \(BindingTestTables.restorationClasses.count)")
            assertKnown(problems, kinds: ["persistedName", "xpcProtocol", "xpcSelector", "restorationClass"])
        }
    }

    // Every class name recorded in a keyed archive of the stored-state
    // corpus: top-level archive files, archives nested in property lists,
    // and archives in SQLite blobs.
    func testStoredStateCorpusArchiveClasses() throws {
        try BindingTiming.measure("testStoredStateCorpusArchiveClasses") {
            let corpus = BindingRepository.url("tests/stored-state-corpus")
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: corpus.path, isDirectory: &isDirectory)
            XCTAssertTrue(exists && isDirectory.boolValue, "the stored-state corpus is missing: no directory at \(corpus.path)")
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: corpus, includingPropertiesForKeys: [.isRegularFileKey]))
            var archives = [BindingArchive]()
            var files = 0
            var sqliteFiles = 0
            var urls = [URL]()
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                // -shm and -wal files are SQLite's, made by opening a corpus
                // database in place; they are not part of the corpus.
                if name.hasSuffix("-shm") || name.hasSuffix("-wal") {
                    continue
                }
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    urls.append(url)
                }
            }
            for url in urls.sorted(by: { $0.path < $1.path }) {
                let relative = BindingRepository.relativePath(url)
                let handle = try FileHandle(forReadingFrom: url)
                let head = try handle.read(upToCount: 16) ?? Data()
                try handle.close()
                files += 1
                if head == Data("SQLite format 3\0".utf8) {
                    sqliteFiles += 1
                    archives.append(contentsOf: try BindingArchiveScanner.archives(inSQLiteAt: url, file: relative))
                } else {
                    let data = try Data(contentsOf: url)
                    archives.append(contentsOf: BindingArchiveScanner.archives(inData: data, file: relative, location: "<root>"))
                }
            }
            let names = Set(archives.flatMap(\.classNames))
            let appNames = names.filter { name in
                BindingTestInputs.runtime.resolveClass(name).map { BindingTestInputs.runtime.isAppClass($0) } ?? false
            }
            print("BINDING-COUNTS corpus files \(files) (SQLite \(sqliteFiles)), keyed archives \(archives.count), distinct class names \(names.count): \(names.sorted()), of which app classes \(appNames.count): \(appNames.sorted())")
            if appNames.isEmpty {
                print("BINDING-WARNING the stored-state corpus covers zero app classes: no class name recorded in its keyed archives is an app class, so this test protects no app class's archived name")
            }
            XCTAssertGreaterThan(archives.count, 0)
            assertKnown(BindingArchiveScanner.check(archives, runtime: BindingTestInputs.runtime), kinds: ["archiveClass"])
        }
    }
}
