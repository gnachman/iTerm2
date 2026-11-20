//
//  BindingTestSupport.swift
//  ModernTests
//
//  Shared pieces of the binding tests of docs/swift-migration/phase0.md
//  section 3: a small XML tree, the problem type every checker reports, the
//  comparison against a checked-in table of known failures, and the
//  abstraction of the Objective-C runtime that the checkers ask.
//
//  The checkers (BindingCheckers.swift) are pure functions of a parsed file
//  and a BindingRuntime. BindingObjCRuntime answers from the real runtime of
//  the test host, where every class of the app is loaded; the fixture tests
//  (BindingCheckerFixtureTests.swift) pass BindingFakeRuntime instead, so that
//  each checker is shown to report exactly the problem a fixture contains.
//
//  Messages and +initialize. The runtime is read with functions that send no
//  messages to the class being asked about: class_copyMethodList,
//  class_copyIvarList, class_copyPropertyList and class_getSuperclass, walked
//  by hand. That is why "responds to" is computed from method lists rather
//  than with instancesRespondToSelector: (a message, which would run the
//  class's +initialize and could consult +resolveInstanceMethod:). The answer
//  is the same for every class that does not add methods lazily; none of the
//  classes these tests ask about does. The one message sent directly is
//  Swift's cast of objc_getMetaClass's result to a class, which goes to the
//  root class only (see RuntimeSnapshot.swift for the same reasoning).
//
//  Looking a class up is not free of +initialize, though. NSClassFromString
//  and objc_lookUpClass on a Swift class run Swift's metadata setup, which
//  sends +initialize to that class. A review run observed this for one app
//  Swift class (iTermBaseString, which has the default +initialize) and for
//  a few system classes, and for no Objective-C app class that implements
//  its own +initialize. This is not checked by a test: the runtime has no
//  public way to ask whether a class is initialized without messaging it.
//
//

import Foundation
import ObjectiveC
import MachO

// MARK: - Repository

enum BindingRepository {
    // The repository root, from the path of this source file baked in at
    // build time. Other ModernTests find repository files the same way.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func url(_ relativePath: String) -> URL {
        return root.appendingPathComponent(relativePath)
    }

    static func relativePath(_ url: URL) -> String {
        let rootPath = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath) {
            return String(path.dropFirst(rootPath.count))
        }
        return path
    }
}

// MARK: - Timing

enum BindingTiming {
    // Prints how long a test method took, so that the log records it next to
    // xcodebuild's own figure.
    static func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let start = Date()
        defer {
            print(String(format: "BINDING-TIMING %@ %.3f s", name, Date().timeIntervalSince(start)))
        }
        return try body()
    }
}

// MARK: - XML

// A parsed XML element. Only what the checkers need: tag, attributes,
// children in document order.
final class BindingXMLElement {
    let tag: String
    let attributes: [String: String]
    private(set) var children: [BindingXMLElement] = []
    private(set) weak var parent: BindingXMLElement?

    init(tag: String, attributes: [String: String]) {
        self.tag = tag
        self.attributes = attributes
    }

    subscript(_ name: String) -> String? {
        return attributes[name]
    }

    fileprivate func append(_ child: BindingXMLElement) {
        child.parent = self
        children.append(child)
    }

    // Every element below this one, depth first, in document order.
    func descendants() -> [BindingXMLElement] {
        var result = [BindingXMLElement]()
        var stack = Array(children.reversed())
        while let element = stack.popLast() {
            result.append(element)
            stack.append(contentsOf: element.children.reversed())
        }
        return result
    }

    func children(named tag: String) -> [BindingXMLElement] {
        return children.filter { $0.tag == tag }
    }

    func firstChild(named tag: String) -> BindingXMLElement? {
        return children.first { $0.tag == tag }
    }
}

enum BindingXMLError: Error, CustomStringConvertible {
    case parse(String, String)

    var description: String {
        switch self {
        case let .parse(path, message):
            return "\(path): XML parse error: \(message)"
        }
    }
}

final class BindingXMLParser: NSObject, XMLParserDelegate {
    private var stack = [BindingXMLElement]()
    private var root: BindingXMLElement?

    static func parse(_ data: Data, path: String) throws -> BindingXMLElement {
        let delegate = BindingXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // The sdef names a DTD by URL. Nothing is fetched.
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = delegate.root else {
            throw BindingXMLError.parse(path, parser.parserError.map { "\($0)" } ?? "no root element")
        }
        return root
    }

    static func parse(contentsOf url: URL) throws -> BindingXMLElement {
        return try parse(try Data(contentsOf: url), path: BindingRepository.relativePath(url))
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let element = BindingXMLElement(tag: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.append(element)
        } else {
            root = element
        }
        stack.append(element)
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}

// MARK: - Problems

// One thing that did not resolve. `key` identifies it in the known-failures
// table: file, kind, element id and name, which do not change when unrelated
// parts of the file are edited.
struct BindingProblem: Hashable, CustomStringConvertible {
    let file: String
    let kind: String
    let elementID: String
    let label: String?
    let name: String
    let detail: String

    var key: String {
        return "\(file)|\(kind)|\(elementID)|\(name)"
    }

    var description: String {
        let labelText = label.map { " (\($0))" } ?? ""
        return "\(file): \(kind) at element id=\(elementID)\(labelText): “\(name)” \(detail)"
    }
}

enum BindingKnownFailures {
    struct Comparison {
        var unexpected: [BindingProblem]
        var nowPassing: [String]
    }

    // A problem not in `known` is unexpected. A key of `known` that no
    // problem has is now passing, which also fails the test, so that the
    // table cannot keep entries that no longer apply. Only keys whose file
    // is in `scope` count as now passing, so a test can share one table.
    static func compare(_ problems: [BindingProblem],
                        known: [String: String],
                        scope: (String) -> Bool) -> Comparison {
        let keys = Set(problems.map(\.key))
        let unexpected = problems.filter { known[$0.key] == nil }
        let nowPassing = known.keys
            .filter { scope($0) && !keys.contains($0) }
            .sorted()
        return Comparison(unexpected: unexpected, nowPassing: nowPassing)
    }

    static func message(_ comparison: Comparison) -> String? {
        if comparison.unexpected.isEmpty && comparison.nowPassing.isEmpty {
            return nil
        }
        var lines = [String]()
        if !comparison.unexpected.isEmpty {
            lines.append("\(comparison.unexpected.count) new problem(s). Fix them, or if one is a deliberate finding add its key to BindingTestTables.knownFailures with a one-line reason:")
            for problem in comparison.unexpected {
                lines.append("  \(problem)")
                lines.append("    key: \"\(problem.key)\"")
            }
        }
        if !comparison.nowPassing.isEmpty {
            lines.append("\(comparison.nowPassing.count) known failure(s) no longer happen. Remove them from BindingTestTables.knownFailures:")
            for key in comparison.nowPassing {
                lines.append("  \"\(key)\"")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Runtime abstraction

// What a class itself declares: not inherited members.
struct BindingClassInfo {
    var superclass: String?
    var instanceMethods: Set<String>
    var classMethods: Set<String>
    var ivars: Set<String>
    // Property name to the class named in its type encoding (T@"Name"), or
    // nil when the property's type is not a named object class.
    var propertyTypes: [String: String?]
    var protocols: Set<String>

    init(superclass: String? = nil,
         instanceMethods: Set<String> = [],
         classMethods: Set<String> = [],
         ivars: Set<String> = [],
         propertyTypes: [String: String?] = [:],
         protocols: Set<String> = []) {
        self.superclass = superclass
        self.instanceMethods = instanceMethods
        self.classMethods = classMethods
        self.ivars = ivars
        self.propertyTypes = propertyTypes
        self.protocols = protocols
    }
}

struct BindingImplementers: Equatable {
    // Classes whose own method list holds the selector with an
    // implementation in the app's binaries (including app categories on
    // system classes).
    var app: [String]
    // Classes whose own method list holds it with an implementation outside
    // the app (AppKit, Foundation).
    var system: [String]
}

protocol BindingRuntime: AnyObject {
    // NSClassFromString(name), and if found, NSStringFromClass of the result.
    func resolveClass(_ name: String) -> String?
    // What the class with this runtime name declares itself, or nil.
    func classInfo(_ runtimeName: String) -> BindingClassInfo?
    // True if the class is defined in one of the app's own binaries.
    func isAppClass(_ runtimeName: String) -> Bool
    // nil if there is no such protocol; else whether the selector is a
    // required or optional instance method of it.
    func protocolHasInstanceMethod(_ protocolName: String, _ selector: String) -> Bool?
    // App classes that conform to the protocol, themselves or through a
    // superclass.
    func appClassesConforming(to protocolName: String) -> [String]
    // For each selector, the classes whose own method list holds it.
    func implementers(of selectors: Set<String>) -> [String: BindingImplementers]
}

// Lookups built on BindingRuntime: inheritance, responds-to, and key-value
// coding's search order. Results are cached per class.
final class BindingRuntimeQueries {
    let runtime: BindingRuntime
    private var instanceMethodCache = [String: Set<String>]()
    private var classMethodCache = [String: Set<String>]()

    init(_ runtime: BindingRuntime) {
        self.runtime = runtime
    }

    // The class and its superclasses, nearest first.
    func chain(_ runtimeName: String) -> [(name: String, info: BindingClassInfo)] {
        var result = [(name: String, info: BindingClassInfo)]()
        var current: String? = runtimeName
        var seen = Set<String>()
        while let name = current, !seen.contains(name), let info = runtime.classInfo(name) {
            seen.insert(name)
            result.append((name, info))
            current = info.superclass
        }
        return result
    }

    func allInstanceMethods(_ runtimeName: String) -> Set<String> {
        if let cached = instanceMethodCache[runtimeName] {
            return cached
        }
        var result = Set<String>()
        for entry in chain(runtimeName) {
            result.formUnion(entry.info.instanceMethods)
        }
        instanceMethodCache[runtimeName] = result
        return result
    }

    // Class methods of the class and its superclasses, plus the root class's
    // instance methods, which the runtime also finds for class messages.
    func allClassMethods(_ runtimeName: String) -> Set<String> {
        if let cached = classMethodCache[runtimeName] {
            return cached
        }
        let entries = chain(runtimeName)
        var result = Set<String>()
        for entry in entries {
            result.formUnion(entry.info.classMethods)
        }
        if let root = entries.last {
            result.formUnion(root.info.instanceMethods)
        }
        classMethodCache[runtimeName] = result
        return result
    }

    func instancesRespond(_ runtimeName: String, to selector: String) -> Bool {
        return allInstanceMethods(runtimeName).contains(selector)
    }

    func classResponds(_ runtimeName: String, to selector: String) -> Bool {
        return allClassMethods(runtimeName).contains(selector)
    }

    func isSubclass(_ runtimeName: String, of base: String) -> Bool {
        return chain(runtimeName).contains { $0.name == base }
    }

    private func hasIvar(_ runtimeName: String, _ name: String) -> Bool {
        return chain(runtimeName).contains { $0.info.ivars.contains(name) }
    }

    static func capitalized(_ key: String) -> String {
        guard let first = key.first else {
            return key
        }
        return first.uppercased() + key.dropFirst()
    }

    // Instance variables key-value coding tries, in order, when
    // +accessInstanceVariablesDirectly returns YES (the default; no class in
    // the app overrides it).
    private func ivarCandidates(_ key: String) -> [String] {
        let cap = Self.capitalized(key)
        return ["_\(key)", "_is\(cap)", key, "is\(cap)"]
    }

    // How setValue:forKey: would set `key`, or nil. Its documented search
    // order: the methods set<Key>: and _set<Key>:, then the instance
    // variables _<key>, _is<Key>, <key>, is<Key>. A declared property counts
    // through its setter method only: key-value coding looks methods up by
    // name, so a property with a custom setter name, or a readonly one, is
    // not settable by key unless an instance variable matches.
    func kvcSetter(_ runtimeName: String, key: String) -> String? {
        guard !key.isEmpty else {
            return nil
        }
        let cap = Self.capitalized(key)
        let methods = allInstanceMethods(runtimeName)
        for selector in ["set\(cap):", "_set\(cap):"] where methods.contains(selector) {
            return "-\(selector)"
        }
        for ivar in ivarCandidates(key) where hasIvar(runtimeName, ivar) {
            return "ivar \(ivar)"
        }
        return nil
    }

    // How valueForKey: would read `key`, or nil. Its documented search
    // order: the methods get<Key>, <key>, is<Key>, _<key>; then the indexed
    // array accessors countOf<Key> with objectIn<Key>AtIndex: or
    // <key>AtIndexes:; then the set accessors countOf<Key>,
    // enumeratorOf<Key> and memberOf<Key>:; then the instance variables
    // _<key>, _is<Key>, <key>, is<Key>.
    func kvcGetter(_ runtimeName: String, key: String) -> String? {
        guard !key.isEmpty else {
            return nil
        }
        let cap = Self.capitalized(key)
        let methods = allInstanceMethods(runtimeName)
        for selector in ["get\(cap)", key, "is\(cap)", "_\(key)"] where methods.contains(selector) {
            return "-\(selector)"
        }
        if methods.contains("countOf\(cap)") {
            if methods.contains("objectIn\(cap)AtIndex:") || methods.contains("\(key)AtIndexes:") {
                return "-countOf\(cap) (indexed)"
            }
            if methods.contains("enumeratorOf\(cap)") && methods.contains("memberOf\(cap):") {
                return "-countOf\(cap) (unordered)"
            }
        }
        for ivar in ivarCandidates(key) where hasIvar(runtimeName, ivar) {
            return "ivar \(ivar)"
        }
        return nil
    }

    // The class named by the type of a declared property `key`, searching
    // superclasses; nil if there is no such property or its type is not a
    // named class.
    func propertyClass(_ runtimeName: String, key: String) -> String? {
        for entry in chain(runtimeName) {
            if let type = entry.info.propertyTypes[key] {
                return type
            }
        }
        return nil
    }

    enum KeyPathResult: Equatable {
        // Every key resolved. `checkedKeys` of them were checked; the rest
        // (`uncheckedKeys`) could not be, because the class of the value of
        // the key before them is not known from the runtime.
        case resolved(checkedKeys: Int, uncheckedKeys: Int)
        case failed(key: String, onClass: String)
    }

    // Checks a key path the way valueForKeyPath: (or setValue:forKeyPath:
    // when `settingLast`) walks it. The first key is always checked. A later
    // key is checked when the previous key is `self` (same object) or a
    // declared property whose type names a class; otherwise the walk stops
    // and the remaining keys are counted as unchecked.
    func checkKeyPath(_ keyPath: String, on runtimeName: String, settingLast: Bool) -> KeyPathResult {
        let keys = keyPath.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var current = runtimeName
        for (index, key) in keys.enumerated() {
            let isLast = index == keys.count - 1
            let resolved: Bool
            if isLast && settingLast {
                resolved = kvcSetter(current, key: key) != nil
            } else {
                resolved = kvcGetter(current, key: key) != nil
            }
            if !resolved {
                return .failed(key: key, onClass: current)
            }
            if isLast {
                return .resolved(checkedKeys: keys.count, uncheckedKeys: 0)
            }
            if key == "self" {
                continue
            }
            guard let next = propertyClass(current, key: key), runtime.classInfo(next) != nil else {
                return .resolved(checkedKeys: index + 1, uncheckedKeys: keys.count - index - 1)
            }
            current = next
        }
        return .resolved(checkedKeys: keys.count, uncheckedKeys: 0)
    }
}

// MARK: - Fake runtime for fixture tests

final class BindingFakeRuntime: BindingRuntime {
    var classes: [String: BindingClassInfo]
    // Names that NSClassFromString would map to a different runtime name,
    // such as a mangled Swift name.
    var aliases: [String: String]
    var appClasses: Set<String>
    var protocols: [String: Set<String>]
    var implementerTable: [String: BindingImplementers]

    init(classes: [String: BindingClassInfo],
         aliases: [String: String] = [:],
         appClasses: Set<String> = [],
         protocols: [String: Set<String>] = [:],
         implementers: [String: BindingImplementers] = [:]) {
        self.classes = classes
        self.aliases = aliases
        self.appClasses = appClasses
        self.protocols = protocols
        self.implementerTable = implementers
    }

    func resolveClass(_ name: String) -> String? {
        if let alias = aliases[name] {
            return alias
        }
        return classes[name] == nil ? nil : name
    }

    func classInfo(_ runtimeName: String) -> BindingClassInfo? {
        return classes[runtimeName]
    }

    func isAppClass(_ runtimeName: String) -> Bool {
        return appClasses.contains(runtimeName)
    }

    func protocolHasInstanceMethod(_ protocolName: String, _ selector: String) -> Bool? {
        return protocols[protocolName].map { $0.contains(selector) }
    }

    func appClassesConforming(to protocolName: String) -> [String] {
        let queries = BindingRuntimeQueries(self)
        return appClasses.filter { name in
            queries.chain(name).contains { $0.info.protocols.contains(protocolName) }
        }.sorted()
    }

    func implementers(of selectors: Set<String>) -> [String: BindingImplementers] {
        var result = [String: BindingImplementers]()
        for selector in selectors {
            result[selector] = implementerTable[selector] ?? BindingImplementers(app: [], system: [])
        }
        return result
    }
}

// MARK: - The real runtime

final class BindingObjCRuntime: BindingRuntime {
    static let shared = BindingObjCRuntime()

    private var classCache = [String: AnyClass]()
    private var infoCache = [String: BindingClassInfo?]()
    private let bundlePath: String
    private let plugInsPath: String
    // __TEXT ranges of the app's own binaries: the executable, the debug
    // dylib, and the frameworks embedded in the app. The test bundle lives in
    // Contents/PlugIns and is excluded.
    private let appTextRanges: [Range<UInt>]
    private let appImagePaths: [String]

    private init() {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let plugInsPath = bundlePath + "Contents/PlugIns/"
        self.bundlePath = bundlePath
        self.plugInsPath = plugInsPath
        var ranges = [Range<UInt>]()
        var paths = [String]()
        for i in 0..<_dyld_image_count() {
            guard let namePointer = _dyld_get_image_name(i) else {
                continue
            }
            let path = Self.resolved(String(cString: namePointer))
            guard Self.isApp(path, bundlePath: bundlePath, plugInsPath: plugInsPath),
                  let header = _dyld_get_image_header(i) else {
                continue
            }
            paths.append(String(cString: namePointer))
            var size: UInt = 0
            let start = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                getsegmentdata($0, "__TEXT", &size)
            }
            if let start, size > 0 {
                let base = UInt(bitPattern: start)
                ranges.append(base..<(base + size))
            }
        }
        appTextRanges = ranges
        appImagePaths = paths
    }

    private static func resolved(_ path: String) -> String {
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isApp(_ path: String, bundlePath: String, plugInsPath: String) -> Bool {
        return path.hasPrefix(bundlePath) && !path.hasPrefix(plugInsPath)
    }

    private func lookUp(_ runtimeName: String) -> AnyClass? {
        if let cls = classCache[runtimeName] {
            return cls
        }
        guard let cls = NSClassFromString(runtimeName) else {
            return nil
        }
        classCache[runtimeName] = cls
        return cls
    }

    func resolveClass(_ name: String) -> String? {
        guard let cls = NSClassFromString(name) else {
            return nil
        }
        let runtimeName = NSStringFromClass(cls)
        classCache[runtimeName] = cls
        return runtimeName
    }

    func classInfo(_ runtimeName: String) -> BindingClassInfo? {
        if let cached = infoCache[runtimeName] {
            return cached
        }
        let info = lookUp(runtimeName).map { makeInfo($0) }
        infoCache[runtimeName] = info
        return info
    }

    private func makeInfo(_ cls: AnyClass) -> BindingClassInfo {
        var info = BindingClassInfo()
        if let superclass = class_getSuperclass(cls) {
            let name = NSStringFromClass(superclass)
            classCache[name] = superclass
            info.superclass = name
        }
        info.instanceMethods = Self.selectors(of: cls)
        if let metaclass = objc_getMetaClass(class_getName(cls)) as? AnyClass, class_isMetaClass(metaclass) {
            info.classMethods = Self.selectors(of: metaclass)
        }
        var ivarCount: UInt32 = 0
        if let ivars = class_copyIvarList(cls, &ivarCount) {
            for i in 0..<Int(ivarCount) {
                // A Swift stored property without @objc is listed under its
                // own name with an empty type encoding, and key-value coding
                // does not use it: setValue:forKey: and valueForKey: raise.
                // Only an ivar with a type encoding counts.
                guard let name = ivar_getName(ivars[i]),
                      let encoding = ivar_getTypeEncoding(ivars[i]),
                      encoding.pointee != 0 else {
                    continue
                }
                info.ivars.insert(String(cString: name))
            }
            free(ivars)
        }
        var propertyCount: UInt32 = 0
        if let properties = class_copyPropertyList(cls, &propertyCount) {
            for i in 0..<Int(propertyCount) {
                let name = String(cString: property_getName(properties[i]))
                let attributes = property_getAttributes(properties[i]).map { String(cString: $0) } ?? ""
                info.propertyTypes[name] = Self.objectClass(fromAttributes: attributes)
            }
            free(properties)
        }
        var protocolCount: UInt32 = 0
        if let protocols = class_copyProtocolList(cls, &protocolCount) {
            for i in 0..<Int(protocolCount) {
                info.protocols.insert(String(cString: protocol_getName(protocols[i])))
            }
            free(UnsafeMutableRawPointer(protocols))
        }
        return info
    }

    // T@"NSString" gives NSString; T@"NSView<Foo>" gives NSView; T@ (id),
    // T@"<Foo>" and scalar types give nil.
    static func objectClass(fromAttributes attributes: String) -> String? {
        guard let type = attributes.split(separator: ",").first, type.hasPrefix("T@\"") else {
            return nil
        }
        var name = type.dropFirst(3)
        if name.hasSuffix("\"") {
            name = name.dropLast()
        }
        if let angle = name.firstIndex(of: "<") {
            name = name[..<angle]
        }
        return name.isEmpty ? nil : String(name)
    }

    private static func selectors(of cls: AnyClass) -> Set<String> {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else {
            return []
        }
        defer {
            free(list)
        }
        var result = Set<String>()
        for i in 0..<Int(count) {
            result.insert(String(cString: sel_getName(method_getName(list[i]))))
        }
        return result
    }

    func isAppClass(_ runtimeName: String) -> Bool {
        guard let cls = lookUp(runtimeName), let image = class_getImageName(cls) else {
            return false
        }
        return Self.isApp(Self.resolved(String(cString: image)), bundlePath: bundlePath, plugInsPath: plugInsPath)
    }

    func protocolHasInstanceMethod(_ protocolName: String, _ selector: String) -> Bool? {
        guard let proto = objc_getProtocol(protocolName) else {
            return nil
        }
        let sel = sel_registerName(selector)
        for required in [true, false] {
            if protocol_getMethodDescription(proto, sel, required, true).name != nil {
                return true
            }
        }
        return false
    }

    private func classNames(inImage path: String) -> [String] {
        var count: UInt32 = 0
        guard let names = objc_copyClassNamesForImage(path, &count) else {
            return []
        }
        defer {
            free(names)
        }
        return (0..<Int(count)).map { String(cString: names[$0]) }
    }

    func appClassesConforming(to protocolName: String) -> [String] {
        guard let proto = objc_getProtocol(protocolName) else {
            return []
        }
        var result = [String]()
        for path in appImagePaths {
            for name in classNames(inImage: path) {
                guard let cls = objc_lookUpClass(name) else {
                    continue
                }
                var current: AnyClass? = cls
                while let c = current {
                    if class_conformsToProtocol(c, proto) {
                        result.append(NSStringFromClass(cls))
                        break
                    }
                    current = class_getSuperclass(c)
                }
            }
        }
        return result.sorted()
    }

    private func isAppAddress(_ imp: IMP) -> Bool {
        let address = UInt(bitPattern: unsafeBitCast(imp, to: UnsafeRawPointer.self))
        return appTextRanges.contains { $0.contains(address) }
    }

    // Walks the classes of the app's binaries and of AppKit, Foundation and
    // libobjc (where categories of the app on NSObject, NSResponder, NSView
    // and friends are attached) and records, for each selector asked about,
    // the classes whose own method list holds it, split by where the
    // implementation lives. Classes made at run time (key-value observing
    // subclasses) belong to no image and are not walked.
    func implementers(of selectors: Set<String>) -> [String: BindingImplementers] {
        var wanted = [Selector: String]()
        for selector in selectors {
            wanted[sel_registerName(selector)] = selector
        }
        var app = [String: Set<String>]()
        var system = [String: Set<String>]()
        var images = appImagePaths
        var imageCount: UInt32 = 0
        let allImageNames: UnsafeMutablePointer<UnsafePointer<CChar>>? = objc_copyImageNames(&imageCount)
        if let allImages = allImageNames {
            for i in 0..<Int(imageCount) {
                let path = String(cString: allImages[i])
                if path.hasSuffix("/AppKit") || path.hasSuffix("/Foundation") || path.hasSuffix("/libobjc.A.dylib") {
                    images.append(path)
                }
            }
            free(allImages)
        }
        for path in images {
            for name in classNames(inImage: path) {
                guard let cls = objc_lookUpClass(name) else {
                    continue
                }
                var count: UInt32 = 0
                guard let list = class_copyMethodList(cls, &count) else {
                    continue
                }
                for i in 0..<Int(count) {
                    let method = list[i]
                    guard let selector = wanted[method_getName(method)] else {
                        continue
                    }
                    let className = NSStringFromClass(cls)
                    if isAppAddress(method_getImplementation(method)) {
                        app[selector, default: []].insert(className)
                    } else {
                        system[selector, default: []].insert(className)
                    }
                }
                free(list)
            }
        }
        var result = [String: BindingImplementers]()
        for selector in selectors {
            result[selector] = BindingImplementers(app: (app[selector] ?? []).sorted(),
                                                   system: (system[selector] ?? []).sorted())
        }
        return result
    }
}
