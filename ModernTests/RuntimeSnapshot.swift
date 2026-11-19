//
//  RuntimeSnapshot.swift
//  ModernTests
//
//  Prints what the Objective-C runtime knows about a class, in a stable,
//  sorted, line-oriented text format meant to be diffed. This is the runtime
//  snapshot of docs/swift-migration/phase0.md section 9: a port must leave the
//  snapshot unchanged, which proves that callers reaching the class through
//  selector strings, xibs, the responder chain, key-value coding, or method
//  enumeration still find what they found before.
//
//  It runs inside the test host because that is where the app's classes are
//  loaded. tools/swift_migration/runtime_snapshot.sh drives it through
//  RuntimeSnapshotTool.swift, and RuntimeSnapshotComparison.swift compares two
//  snapshots.
//
//  Messages and +initialize. The snapshot reads runtime metadata with
//  functions that send no messages. The one exception is Swift's cast of
//  objc_getMetaClass's result to a class: it sends +retain, +class, and
//  +release, and they go to the root class at the top of the inspected
//  class's superclass chain, not to the class itself. They run the root
//  class's +initialize if it has not run yet, and nobody else's. So the
//  snapshot first walks the superclass chain, which sends nothing, and
//  refuses a class whose root is not NSObject or NSProxy before the cast. For
//  every class it accepts, the only messages it sends go to NSObject or
//  NSProxy; no class below the root receives any, and the +initialize of no
//  class below the root runs. A test checks both halves with fixtures:
//  an NSObject subclass whose +initialize records that it ran, and a root
//  class with no methods but +initialize, which crashes the process if it is
//  sent anything else. The metaclass is looked up by name because
//  object_getClass(_:), which takes an object, runs +initialize for every
//  class.
//
//  A snapshot records the process as it is when the snapshot is taken.
//  System frameworks can add methods and classes at run time, so what a class
//  holds can depend on what the process has done. runtime_snapshot.sh runs
//  the snapshot as the only test in its run so that other tests cannot change
//  the process first.
//
//  Labels describe declarations, not storage. A property's ownership is what
//  its declaration's attribute string says, which can differ from how its
//  value is really held: a category property or an @dynamic one has no
//  storage of its own, a property declared assign can be backed by a strong
//  ivar, and Swift marks a computed property strong although it stores
//  nothing.
//
//  Format: a header, then one class section per class, sorted by class name.
//  Square brackets mark what can be absent:
//
//    # Objective-C runtime snapshot, format 2
//    architecture <arm64 or x86_64>
//    build-configuration [<name of the directory the app was built into>]
//    build-variant [<sanitizer variant, such as ASan, inferred from the
//                   directory layout of the build products>]
//    class <name>
//      DUPLICATE <kind> <name> count=<n>        (only when there is one)
//      language <objc, swift, or unknown>
//      superclass [<name>]
//      image [<file name of the binary that defines the class>]
//      protocol <name>                           (directly adopted, sorted, once per adopting list)
//      ivar <name> types=[<encoding>]
//      class-method +<selector> types=[<encoding>] [also-implemented-by=<+ or -><class>] [image=[<file name>]]
//      instance-method -<selector> types=[<encoding>] [also-implemented-by=-<class>] [image=[<file name>]]
//      class-property <name> <attributes>
//      instance-property <name> <attributes>
//    end class <name>
//
//  Every line ends with a line feed, the last one included. Lines inside a
//  class section are indented by two spaces, and fields are separated by
//  exactly one space. Every name and value is written through
//  RuntimeSnapshotFormat.escape, which percent-escapes every byte that is
//  not printable ASCII, and every %, so a C++ type encoding that contains
//  spaces, or a selector made at run time with any unusual character, still
//  makes an unambiguous line, and non-ASCII names appear escaped byte by
//  byte. A property line is
//    <kind> <name> type=[<T>] ownership=<label> <atomic or nonatomic>
//      [readonly] [dynamic] [optional] [getter=[<G>]] [setter=[<S>]]
//      ivar=[<V>] raw=[<attribute string>]
//  with its fields in that order, on one line.
//
//  Empty and absent values. No placeholder word is ever written for a
//  missing value, because any word could also be a real name or encoding.
//  Instead an empty or absent value is written as nothing:
//    - A header, superclass, or image line with no value is its keyword
//      alone: build-configuration when the app's directory has no name,
//      build-variant when the build products are not in a Variant-<name>
//      directory, superclass for a root class, and image for a class in no
//      loaded binary (one made at run time). architecture and language
//      always have a value.
//    - A key=value field with an empty or absent value is the key and = with
//      nothing after: types= for an encoding the runtime gives as empty or
//      not at all, type= for a property type that is absent or cannot be
//      read, ivar= for a property with no V code or an empty one, getter=
//      and setter= for a G or S code with no name, and image= for a method
//      whose code is in no loaded binary.
//  This cannot collide with a real value because every value the writer puts
//  in one of these positions is nonempty when present: a class with an empty
//  class, superclass, protocol, ivar, selector, or property name is refused;
//  an image whose file name would be empty is treated as no image; and a
//  build configuration or variant with an empty name is treated as none. So
//  a value that is present is never written as nothing, and a value spelled
//  like a placeholder, such as a class named (none), is just that name. Where an empty field stands for more than one thing
//  the runtime distinguishes (no T code, or one that cannot be read; no V
//  code, or an empty one), raw= holds the whole attribute string, which
//  tells them apart. The runtime's nil and empty encodings mean the same
//  thing, that it has no type, so types= does not tell them apart.
//  Optional fields that are absent are omitted: also-implemented-by= when
//  no superclass has the selector, image= when the method is in the class's
//  binary, and getter= and setter= when there is no G or S code.
//
//  Type encodings differ between architectures and macros differ between
//  build configurations, so the comparison refuses to compare snapshots whose
//  header lines differ. The tool snapshots whatever the ModernTests scheme
//  builds (today Development, with the address sanitizer variant); it has no
//  way to choose another configuration.
//
//  "language" says which compiler defined the class. String(reflecting:)
//  qualifies a class defined in Swift with its module (ModernTests.Foo), even
//  when it has an @objc(Foo) name or is a subclass of an Objective-C class.
//  A class defined in Objective-C, including one with Swift extensions, has no
//  module there. (The `__C` module that Swift uses for imported declarations
//  does not show up in this name, so it cannot be used.) So:
//    objc     the name has no period. This includes classes made at run
//             time, such as key-value observing subclasses, which come from
//             the Objective-C runtime.
//    swift    the name has a period and differs from the runtime name, or
//             equals it and the class comes from a binary. It differs for a
//             class with an @objc(Name) name, and for a nested, private, or
//             generic Swift class, whose runtime name is mangled; such a
//             class, a generic one in particular, can have its metadata made
//             at run time and so come from no binary. It equals it for a
//             top-level Swift class with no Objective-C name, whose runtime
//             name, as class_getName returns it, is Module.Name.
//    unknown  the name has a period, equals the runtime name, and the class
//             comes from no binary: a class made at run time with a period in
//             its name, which could have been made by either language's code
//  unknown is not a language but the absence of one. The labels that depend
//  on the language, such as weak versus weak-or-unowned, take the cautious
//  reading for it, and the comparison gives no verdict for a class that is
//  unknown in either snapshot.
//
//  Lines within a kind are sorted by name, byte-wise. Ivars are sorted too, so
//  a change in their declaration order, which decides the order in which ARC
//  releases them at teardown, is not visible in a snapshot. A selector that the
//  class's own method list holds more than once (for example a method in both
//  the Objective-C @implementation and a Swift extension) gets one line per
//  occurrence and a DUPLICATE line at the top of the section. The exception is
//  +load: a class and each of its categories may have one, the runtime calls
//  every one of them, and none replaces another, so repeated +load entries are
//  listed but not reported as duplicates. Every other selector, +initialize
//  included, is a duplicate when repeated: the runtime sends +initialize to
//  only one of a class's and its categories' implementations.
//
//  A method line has "image=" only when the method's implementation is in a
//  different binary from the class, found from the address of its IMP. That
//  makes methods that the test bundle (image=ModernTests) adds to an app
//  class visible, so a test helper cannot hide a method the app dropped. Only
//  the file name is recorded, so snapshots from different checkouts compare
//  equal. "image=" with no value means dladdr finds no loaded binary
//  containing the address, which is the case for code made at run time, as
//  imp_implementationWithBlock makes it. System frameworks can add such
//  methods to app classes; they appear in no source file but are part of
//  what the runtime sees, so they are listed. A class made at run time is in
//  no binary either, so its image line has no value, and a method made at
//  run time in it gets no "image=", since it is in no binary just as the
//  class is.
//
//  Instance variables are listed by name and type encoding, without offsets,
//  which change for unrelated reasons. Key-value coding falls back to ivars
//  and xibs connect outlets to them, so a renamed or dropped ivar matters.
//
//  Property ownership is reported only as far as the property's attribute
//  string states it:
//    copy, strong          from the C and & codes
//    weak                  from the W code, in a class whose language is
//                          objc. A property that a Swift extension declares
//                          on such a class also gets W when Swift declares
//                          it unowned, and the runtime does not say which
//                          language declared a property, so this label can
//                          be wrong for one; the pass caveat says so
//    weak-or-unowned       from the W code, in a Swift class or one whose
//                          language is unknown, because Swift writes W for
//                          weak, unowned, and unowned(unsafe) alike, and
//                          nothing the runtime holds tells them apart without
//                          an instance
//    unsafe_unretained     a readwrite id or block property of an
//                          Objective-C class with no code, since clang writes
//                          a code for every readwrite strong, copy, or weak
//                          one
//    unrecorded            an object property for which none of the above
//                          applies: a readonly one with no code (clang writes
//                          C, & and W for readonly copy, retain and weak
//                          properties, but no code for a strong one, whether
//                          strong by default or explicitly), a readwrite
//                          Class property with no code
//                          (clang writes none for an unsafe_unretained or
//                          assign Class property, nor for a Class property
//                          compiled without ARC), or one of a Swift class, or
//                          of a class whose language is unknown, with no code,
//                          such as a Swift `let`
//    assign                a property of a non-object type (not an id, a
//                          block, or a Class)
//
//  A property line has a getter field only when the attribute string has a G
//  code, and a setter field only when it has an S code, each holding exactly
//  the name in the code. The snapshot derives no accessor names: Swift
//  writes no G code for a getter with a custom Objective-C name, such as
//  isFlipped, so a name derived from the property's name would be wrong. The
//  accessors themselves are listed as method lines.
//
//  A property can also appear more than once in a class's property list. The
//  compiler emits the NSObject protocol's properties (description, hash, and
//  so on) once for each category or extension that adopts a protocol derived
//  from it, so PTYSession, for example, lists each of them twice. Those
//  repeats are identical metadata with no implementation behind them, so they
//  get one line per occurrence but no DUPLICATE line. A property listed more
//  than once with different attributes does get a DUPLICATE line.
//
//  "also-implemented-by" names the nearest superclass whose own method list
//  has the same selector, so the method is an override. Its value is a sign
//  and the escaped class name: + when the selector is that class's class
//  method, - when it is its instance method. A class method can be either,
//  because the root metaclass inherits from the root class, so its override
//  can be the root class's instance method (for example -NSObject). An
//  instance method's is always -. The sign is outside the name, so no class
//  name can be mistaken for the other kind of method.
//
//  Direct methods and properties (objc_direct) are not registered with the
//  runtime, so they do not appear as methods or properties. That is the point
//  of using them for migration scaffolding
//  (docs/swift-migration/objc-state.md section 2). A direct property's
//  backing ivar is an ordinary ivar and is listed.
//
//  Names are compared and sorted as UTF-8 bytes, never as Swift strings,
//  because Swift treats strings that are equal under Unicode normalization as
//  equal, while the runtime treats them as different selectors and names.
//

import Foundation
import MachO
import ObjectiveC
@testable import iTerm2SharedARC

enum RuntimeSnapshot {
    enum SnapshotError: Error, CustomStringConvertible {
        case classNotFound(String)
        case noClasses
        case unsupportedRootClass(className: String, rootName: String)
        case sameClassTwice(String, String)
        case shadowedClass(String)
        // `what` is a phrase such as "an ivar".
        case emptyName(className: String, what: String)

        var description: String {
            switch self {
            case .classNotFound(let name):
                return "No Objective-C class named \(name) is loaded in the test host"
            case .noClasses:
                return "No class names were given"
            case let .unsupportedRootClass(className, rootName):
                return "Cannot snapshot \(className): its root class is \(rootName), not NSObject or NSProxy, and taking a snapshot would send it messages it may not implement"
            case let .sameClassTwice(first, second):
                return "\(first) and \(second) name the same class; give only one of them"
            case let .shadowedClass(name):
                return "Cannot snapshot this \(name): the runtime resolves the name \(name) to a different class, so its class methods cannot be looked up by name"
            case let .emptyName(className, what):
                if className.isEmpty {
                    return "Cannot snapshot a class with no name, which a snapshot cannot write"
                }
                return "Cannot snapshot \(className): it has \(what) with no name, which a snapshot cannot write"
            }
        }
    }

    // Splits a list of class names separated by commas or white space.
    // Throws if it names no classes.
    static func classNames(fromList list: String) throws -> [String] {
        let names = list
            .components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
        guard !names.isEmpty else {
            throw SnapshotError.noClasses
        }
        return names
    }

    // A snapshot of several classes, looked up by their runtime names, in one
    // text. Repeated names are taken once. Two different names for the same
    // class, such as a Swift class's module-qualified name and its mangled
    // name, are refused, since the snapshot would hold the class twice.
    static func snapshot(classNames: [String]) throws -> String {
        guard !classNames.isEmpty else {
            throw SnapshotError.noClasses
        }
        var classes = [AnyClass]()
        var seen = Set<[UInt8]>()
        // ObjectIdentifier(_:) takes a metatype, so it sends no message.
        var nameOfClass = [ObjectIdentifier: String]()
        for name in classNames.sorted(by: utf8Less) where seen.insert(Array(name.utf8)).inserted {
            guard let cls = NSClassFromString(name) else {
                throw SnapshotError.classNotFound(name)
            }
            if let other = nameOfClass[ObjectIdentifier(cls)] {
                throw SnapshotError.sameClassTwice(other, name)
            }
            nameOfClass[ObjectIdentifier(cls)] = name
            classes.append(cls)
        }
        return try snapshot(classes: classes)
    }

    static func snapshot(classes: [AnyClass]) throws -> String {
        var seen = [ObjectIdentifier: String]()
        for cls in classes {
            if let other = seen[ObjectIdentifier(cls)] {
                throw SnapshotError.sameClassTwice(other, className(cls))
            }
            seen[ObjectIdentifier(cls)] = className(cls)
            try checkRootClass(of: cls)
            // The metaclass is looked up by name, so the name must lead back
            // to this class. objc_lookUpClass returns a Class and sends no
            // message.
            guard let named = objc_lookUpClass(className(cls)), ObjectIdentifier(named) == ObjectIdentifier(cls) else {
                throw SnapshotError.shadowedClass(className(cls))
            }
        }
        var lines = headerLines(architecture: architecture,
                                buildConfiguration: buildConfiguration,
                                buildVariant: buildVariant)
        let sorted = classes.sorted { utf8Less(className($0), className($1)) }
        for cls in sorted {
            lines.append(contentsOf: try section(for: cls))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // The lines before the first class section. A nil value leaves its
    // keyword alone on the line.
    // Internal rather than private so that tests can reach it.
    static func headerLines(architecture: String, buildConfiguration: String?, buildVariant: String?) -> [String] {
        return [RuntimeSnapshotFormat.headerLine,
                valueLine(RuntimeSnapshotFormat.architectureKeyword, architecture),
                valueLine(RuntimeSnapshotFormat.buildConfigurationKeyword, buildConfiguration),
                valueLine(RuntimeSnapshotFormat.buildVariantKeyword, buildVariant)]
    }

    // A line holding a keyword and at most one value: the keyword alone when
    // the value is nil, and otherwise the keyword, a space, and the escaped
    // value. The value must not be empty, or the line would end in a space.
    // Internal rather than private so that tests can reach it.
    static func valueLine(_ keyword: String, _ value: String?) -> String {
        guard let value else {
            return keyword
        }
        it_assert(!value.isEmpty, "Empty value for \(keyword)")
        return keyword + " " + e(value)
    }

    // Throws unless the class's root class is NSObject or NSProxy. See the
    // comment at the top of this file. Uses only class_getSuperclass and
    // class_getName, which send no messages.
    private static func checkRootClass(of cls: AnyClass) throws {
        var root: AnyClass = cls
        while let superclass = class_getSuperclass(root) {
            root = superclass
        }
        let supported = [ObjectIdentifier(NSObject.self), ObjectIdentifier(NSProxy.self)]
        guard supported.contains(ObjectIdentifier(root)) else {
            throw SnapshotError.unsupportedRootClass(className: className(cls), rootName: className(root))
        }
    }

    // MARK: - Sections

    // The test bundle is loaded into the app's process, so it was compiled
    // for the same architecture as the app's code being inspected.
    private static var architecture: String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        #error("The runtime snapshot knows only the arm64 and x86_64 architectures")
        #endif
    }

    // xcodebuild puts the app in a directory named after the build
    // configuration (for example Build/Development/iTerm2.app, or
    // Build/Variant-ASan/Development/iTerm2.app with a sanitizer), so the name
    // of the directory holding the running app is the configuration it was
    // built with, and a sanitizer variant is the name of the directory above
    // that, after Variant-. Both are inferred from this layout. Each is nil
    // when there is no such name: a directory with an empty name, or one
    // above it not named Variant- followed by at least one character.
    static var buildConfiguration: String? {
        return buildConfiguration(appURL: Bundle.main.bundleURL)
    }

    static var buildVariant: String? {
        return buildVariant(appURL: Bundle.main.bundleURL)
    }

    static func buildConfiguration(appURL: URL) -> String? {
        let name = appURL.deletingLastPathComponent().lastPathComponent
        return name.isEmpty ? nil : name
    }

    static func buildVariant(appURL: URL) -> String? {
        let name = appURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let prefix = "Variant-"
        guard name.hasPrefix(prefix), name.count > prefix.count else {
            return nil
        }
        return String(name.dropFirst(prefix.count))
    }

    // "objc", "swift", or "unknown". See the comment at the top of this file.
    static func language(of cls: AnyClass) -> String {
        let reflected = String(reflecting: cls)
        if !reflected.contains(".") {
            return "objc"
        }
        if reflected != className(cls) {
            // The Swift name differs from the runtime name: an @objc(Name)
            // class, or a nested, private, or generic Swift class whose
            // runtime name is mangled. Only Swift metadata gives a reflected
            // name that differs, so this holds even with no binary.
            return "swift"
        }
        // A Swift class without an @objc name (whose runtime name is
        // Module.Name), or a class made at run time with a period in its
        // name. Only the former comes from a binary.
        return class_getImageName(cls) == nil ? "unknown" : "swift"
    }

    private struct MethodEntry {
        var selector: String
        var types: String
        // The file name of the binary holding the implementation, or nil if
        // no loaded binary holds it.
        var image: String?
        // A sign and a class name, as described at the top of this file.
        var alsoImplementedBy: String?
    }

    private struct PropertyEntry {
        var name: String
        var description: String
    }

    private struct IvarEntry {
        // Nil when the runtime has no name.
        var name: String?
        // Empty when the runtime has no encoding.
        var encoding: String
    }

    private static func section(for cls: AnyClass) throws -> [String] {
        let name = className(cls)
        // Every name written in a value position is nonempty, so that an
        // empty field always means an empty or absent value. See the comment
        // at the top of this file.
        func requireName(_ value: String?, _ what: String) throws {
            guard let value, !value.isEmpty else {
                throw SnapshotError.emptyName(className: name, what: what)
            }
        }
        try requireName(name, "a class")
        // Not object_getClass(cls): turning the class into an object to pass
        // it there runs +initialize. Looking the metaclass up by name does
        // not, except for a root class (see the comment at the top of this
        // file).
        guard let metaclass = objc_getMetaClass(name) as? AnyClass, class_isMetaClass(metaclass) else {
            it_fatalError("Class \(name) has no metaclass")
        }
        let locator = ImageLocator(cls)
        let image = locator.classImage
        let classMethods = methods(of: metaclass, superclassChain: superclassChain(ofMetaclass: metaclass), locator: locator)
        let instanceMethods = methods(of: cls, superclassChain: superclassChain(ofClass: cls), locator: locator)
        let classLanguage = language(of: cls)
        let classIvars = ivars(of: cls)
        let classProperties = properties(of: metaclass, language: classLanguage)
        let instanceProperties = properties(of: cls, language: classLanguage)
        let superclassName = class_getSuperclass(cls).map { className($0) }
        let classProtocols = protocols(of: cls)
        if superclassName != nil {
            try requireName(superclassName, "a superclass")
        }
        for protocolName in classProtocols {
            try requireName(protocolName, "a protocol")
        }
        for ivar in classIvars {
            try requireName(ivar.name, "an ivar")
        }
        for method in classMethods + instanceMethods {
            try requireName(method.selector, "a method")
        }
        for property in classProperties + instanceProperties {
            try requireName(property.name, "a property")
        }

        var body = [String]()
        // +load is not a duplicate: see the comment at the top of this file.
        body.append(contentsOf: duplicateLines(kind: "class-method",
                                               entries: classMethods.filter { !sameBytes($0.selector, "load") }.map { ("+" + $0.selector, $0.types) },
                                               onlyWhenDetailsDiffer: false))
        body.append(contentsOf: duplicateLines(kind: "instance-method",
                                               entries: instanceMethods.map { ("-" + $0.selector, $0.types) },
                                               onlyWhenDetailsDiffer: false))
        body.append(contentsOf: duplicateLines(kind: "class-property",
                                               entries: classProperties.map { ($0.name, $0.description) },
                                               onlyWhenDetailsDiffer: true))
        body.append(contentsOf: duplicateLines(kind: "instance-property",
                                               entries: instanceProperties.map { ($0.name, $0.description) },
                                               onlyWhenDetailsDiffer: true))

        body.append(valueLine(RuntimeSnapshotFormat.languageKeyword, classLanguage))
        body.append(valueLine(RuntimeSnapshotFormat.superclassKeyword, superclassName))
        body.append(valueLine(RuntimeSnapshotFormat.imageKeyword, image))
        body.append(contentsOf: classProtocols.map { "protocol " + e($0) })
        // Every name was checked above.
        body.append(contentsOf: classIvars.map { (name: $0.name ?? "", encoding: $0.encoding) }
            .sorted { utf8Less($0.name, $1.name) }
            .map { "ivar \(e($0.name)) types=\(e($0.encoding))" })
        body.append(contentsOf: classMethods.map { methodLine(kind: "class-method", sign: "+", entry: $0, classImage: image) })
        body.append(contentsOf: instanceMethods.map { methodLine(kind: "instance-method", sign: "-", entry: $0, classImage: image) })
        body.append(contentsOf: classProperties.map { "class-property \(e($0.name)) \($0.description)" })
        body.append(contentsOf: instanceProperties.map { "instance-property \(e($0.name)) \($0.description)" })

        return ["class " + e(name)] + body.map { "  " + $0 } + ["end class " + e(name)]
    }

    // Escapes a name or value for a line. See RuntimeSnapshotFormat.escape.
    private static func e(_ value: String) -> String {
        return RuntimeSnapshotFormat.escape(value)
    }

    private static func methodLine(kind: String, sign: String, entry: MethodEntry, classImage: String?) -> String {
        return methodLine(kind: kind,
                          sign: sign,
                          selector: entry.selector,
                          types: entry.types,
                          alsoImplementedBy: entry.alsoImplementedBy,
                          image: entry.image,
                          classImage: classImage)
    }

    // A method line. image and classImage are file names, or nil for no
    // binary. image= is written only when the two differ, with no value when
    // image is nil.
    // Internal rather than private so that tests can reach it.
    static func methodLine(kind: String,
                           sign: String,
                           selector: String,
                           types: String,
                           alsoImplementedBy: String?,
                           image: String?,
                           classImage: String?) -> String {
        var line = "\(kind) \(sign)\(e(selector)) types=\(e(types))"
        if let alsoImplementedBy {
            line += " also-implemented-by=" + e(alsoImplementedBy)
        }
        if image != classImage {
            line += " image=" + (image.map(e) ?? "")
        }
        return line
    }

    // DUPLICATE lines for names that occur more than once. With
    // onlyWhenDetailsDiffer, repeats whose details are all the same are not
    // reported.
    // Internal rather than private so that tests can reach it.
    static func duplicateLines(kind: String,
                                       entries: [(name: String, detail: String)],
                                       onlyWhenDetailsDiffer: Bool) -> [String] {
        let groups = Dictionary(grouping: entries, by: { Array($0.name.utf8) })
        return groups
            .filter { _, group in
                group.count > 1 && (!onlyWhenDetailsDiffer || Set(group.map { Array($0.detail.utf8) }).count > 1)
            }
            .map { _, group in (name: group[0].name, count: group.count) }
            .sorted { utf8Less($0.name, $1.name) }
            .map { "\(RuntimeSnapshotFormat.duplicateKeyword) \(kind) \(RuntimeSnapshotFormat.escape($0.name)) count=\($0.count)" }
    }

    // MARK: - Methods

    // Each element is a class whose own method list is searched, and the
    // also-implemented-by value to report when it has the selector: + and
    // the class's name for a metaclass, whose methods are class methods, and
    // - and the name for a class, whose methods are instance methods.
    private typealias Chain = [(cls: AnyClass, label: String)]

    private static func superclassChain(ofClass cls: AnyClass) -> Chain {
        var chain = Chain()
        var current: AnyClass? = class_getSuperclass(cls)
        while let c = current {
            chain.append((c, "-" + className(c)))
            current = class_getSuperclass(c)
        }
        return chain
    }

    // The superclasses of a metaclass are the superclasses' metaclasses, and
    // then the root class itself, whose instance methods are therefore
    // reachable as class methods.
    private static func superclassChain(ofMetaclass metaclass: AnyClass) -> Chain {
        var chain = Chain()
        var current: AnyClass? = class_getSuperclass(metaclass)
        while let c = current {
            chain.append((c, (class_isMetaClass(c) ? "+" : "-") + className(c)))
            current = class_getSuperclass(c)
        }
        return chain
    }

    // The class's own methods, sorted.
    private static func methods(of cls: AnyClass, superclassChain chain: Chain, locator: ImageLocator) -> [MethodEntry] {
        let ancestorSelectors = chain.map { (selectors: ownSelectors(of: $0.cls), label: $0.label) }
        return ownMethods(of: cls, locator: locator)
            .map { method in
                var entry = method
                let selector = Array(method.selector.utf8)
                entry.alsoImplementedBy = ancestorSelectors.first { $0.selectors.contains(selector) }?.label
                return entry
            }
            .sorted { lhs, rhs in
                if !sameBytes(lhs.selector, rhs.selector) {
                    return utf8Less(lhs.selector, rhs.selector)
                }
                return utf8Less(lhs.types, rhs.types)
            }
    }

    // Just the selectors, which is much faster than ownMethods(of:) because it
    // does not look up images. Used for superclasses, which can have
    // thousands of methods (NSObject does).
    private static func ownSelectors(of cls: AnyClass) -> Set<[UInt8]> {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else {
            return []
        }
        defer {
            free(list)
        }
        var result = Set<[UInt8]>()
        for i in 0..<Int(count) {
            result.insert(Array(NSStringFromSelector(method_getName(list[i])).utf8))
        }
        return result
    }

    private static func ownMethods(of cls: AnyClass, locator: ImageLocator) -> [MethodEntry] {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else {
            return []
        }
        defer {
            free(list)
        }
        var result = [MethodEntry]()
        for i in 0..<Int(count) {
            let method = list[i]
            let selector = NSStringFromSelector(method_getName(method))
            // An empty or missing encoding is printed as an empty value.
            let types = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
            result.append(MethodEntry(selector: selector,
                                      types: types,
                                      image: locator.imageName(of: method_getImplementation(method)),
                                      alsoImplementedBy: nil))
        }
        return result
    }

    // MARK: - Images

    // Finds the binary that holds a method's implementation. dladdr answers
    // that but costs about a millisecond a call, because it also searches for
    // the nearest symbol, and a large class has thousands of methods. Nearly
    // all of them are in the class's own binary, so an address inside that
    // binary's __TEXT segment is answered directly and only the rest go to
    // dladdr.
    // Image names are file names, or nil for no loaded binary. A path whose
    // file name is empty names no file, so it is nil too, which keeps every
    // image name the snapshot writes nonempty.
    private struct ImageLocator {
        let classImage: String?
        private let text: Range<UInt>?

        init(_ cls: AnyClass) {
            guard let pathPointer = class_getImageName(cls) else {
                classImage = nil
                text = nil
                return
            }
            let path = String(cString: pathPointer)
            classImage = RuntimeSnapshot.fileName(path)
            text = classImage == nil ? nil : RuntimeSnapshot.textSegment(ofImageAtPath: path)
        }

        func imageName(of imp: IMP) -> String? {
            let address = UInt(bitPattern: unsafeBitCast(imp, to: UnsafeRawPointer.self))
            if let text, text.contains(address) {
                return classImage
            }
            var info = Dl_info()
            guard dladdr(unsafeBitCast(imp, to: UnsafeRawPointer.self), &info) != 0,
                  let path = info.dli_fname else {
                return nil
            }
            return RuntimeSnapshot.fileName(String(cString: path))
        }
    }

    // The address range of the __TEXT segment of a loaded image, or nil if no
    // loaded image has that path.
    private static func textSegment(ofImageAtPath path: String) -> Range<UInt>? {
        for i in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(i),
                  String(cString: name) == path,
                  let header = _dyld_get_image_header(i) else {
                continue
            }
            var size: UInt = 0
            let start = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                getsegmentdata($0, "__TEXT", &size)
            }
            guard let start, size > 0 else {
                return nil
            }
            let base = UInt(bitPattern: start)
            return base..<(base + size)
        }
        return nil
    }

    private static func fileName(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    // MARK: - Ivars

    private static func ivars(of cls: AnyClass) -> [IvarEntry] {
        var count: UInt32 = 0
        guard let list = class_copyIvarList(cls, &count) else {
            return []
        }
        defer {
            free(list)
        }
        var result = [IvarEntry]()
        for i in 0..<Int(count) {
            // The runtime stores no name for an ivar added with an empty one.
            let name = ivar_getName(list[i]).map { String(cString: $0) }
            let encoding = ivar_getTypeEncoding(list[i]).map { String(cString: $0) } ?? ""
            result.append(IvarEntry(name: name, encoding: encoding))
        }
        return result
    }

    // MARK: - Protocols

    private static func protocols(of cls: AnyClass) -> [String] {
        var count: UInt32 = 0
        guard let list = class_copyProtocolList(cls, &count) else {
            return []
        }
        defer {
            free(UnsafeMutableRawPointer(list))
        }
        var result = [String]()
        for i in 0..<Int(count) {
            result.append(String(cString: protocol_getName(list[i])))
        }
        return result.sorted(by: utf8Less)
    }

    // MARK: - Properties

    private static func properties(of cls: AnyClass, language: String) -> [PropertyEntry] {
        var count: UInt32 = 0
        guard let list = class_copyPropertyList(cls, &count) else {
            return []
        }
        defer {
            free(list)
        }
        var result = [PropertyEntry]()
        for i in 0..<Int(count) {
            let property = list[i]
            result.append(PropertyEntry(name: String(cString: property_getName(property)),
                                        description: describe(property, language: language)))
        }
        return result.sorted { lhs, rhs in
            if !sameBytes(lhs.name, rhs.name) {
                return utf8Less(lhs.name, rhs.name)
            }
            return utf8Less(lhs.description, rhs.description)
        }
    }

    // Decodes the attributes the compiler recorded for a property. The meaning
    // of each code is in Apple's "Declared Properties" section of the
    // Objective-C Runtime Programming Guide. The raw attribute string is
    // appended so nothing is lost if a code is not decoded here.
    private static func describe(_ property: objc_property_t, language: String) -> String {
        let raw = property_getAttributes(property).map { String(cString: $0) } ?? ""
        let attributes = attributeCodes(raw)
        let type = attributes["T"]
        // An id, a block, or a Class.
        let isObject = type.map { $0.hasPrefix("@") || $0.hasPrefix("#") } ?? false
        let readonly = attributes["R"] != nil
        let ownership: String
        if raw.hasPrefix("T") && type == nil {
            // The type could not be read, so neither can the ownership.
            ownership = "unrecorded"
        } else if attributes["C"] != nil {
            ownership = "copy"
        } else if attributes["&"] != nil {
            ownership = "strong"
        } else if attributes["W"] != nil {
            // Swift writes W for unowned and unowned(unsafe) too.
            ownership = language == "objc" ? "weak" : "weak-or-unowned"
        } else if type == nil {
            // Nothing says what kind of value the property holds.
            ownership = "unrecorded"
        } else if !isObject {
            ownership = "assign"
        } else if language != "objc" {
            // Swift writes no code for a `let`, and a class whose language is
            // unknown may follow either compiler's rules.
            ownership = "unrecorded"
        } else if !readonly && (type?.hasPrefix("@") ?? false) {
            // Clang writes a code for every readwrite strong, copy, or weak
            // id or block property.
            ownership = "unsafe_unretained"
        } else {
            // A readonly property with no code (clang writes C, & and W for
            // readonly copy, retain and weak properties, but no code for a
            // strong one, whether strong by default or explicitly), or a
            // readwrite Class property with no code. Clang
            // writes & for a strong Class property and no code for an
            // unsafe_unretained or assign one, or for one compiled without
            // ARC, so the code alone does not say which of those it is.
            ownership = "unrecorded"
        }
        var fields = [
            "type=" + e(type ?? ""),
            "ownership=" + ownership,
            attributes["N"] != nil ? "nonatomic" : "atomic",
        ]
        if readonly {
            fields.append("readonly")
        }
        if attributes["D"] != nil {
            fields.append("dynamic")
        }
        if attributes["?"] != nil {
            // Declared @optional in a protocol.
            fields.append("optional")
        }
        if let getter = attributes["G"] {
            fields.append("getter=" + e(getter))
        }
        if let setter = attributes["S"] {
            fields.append("setter=" + e(setter))
        }
        // Empty for no V code and for an empty one; raw= tells them apart.
        fields.append("ivar=" + e(attributes["V"] ?? ""))
        fields.append("raw=" + e(raw))
        return fields.joined(separator: " ")
    }

    // The codes of a property attribute string, each with its value.
    // property_copyAttributeList splits the string at every comma, which cuts
    // a type encoding that contains one, such as a C++ template type, so the
    // string is split here instead: the value of T runs to the first comma
    // outside double quotes and outside {}, [], (), and <> pairs. The other
    // codes hold names or single letters, which have no commas. A type with
    // an unbalanced quote or bracket is left out; describe then prints it as
    // empty and the ownership as unrecorded.
    // Internal rather than private so that tests can reach it.
    static func attributeCodes(_ raw: String) -> [String: String] {
        var result = [String: String]()
        let characters = Array(raw)
        var start = 0
        if characters.first == "T" {
            var depth = 0
            var quoted = false
            var end = characters.count
            var balanced = false
            for i in 1..<characters.count {
                let c = characters[i]
                if quoted {
                    quoted = c != "\""
                } else if c == "\"" {
                    quoted = true
                } else if "{[(<".contains(c) {
                    depth += 1
                } else if "}])>".contains(c) {
                    depth -= 1
                } else if c == "," && depth == 0 {
                    end = i
                    balanced = true
                    break
                }
            }
            balanced = balanced || (!quoted && depth == 0)
            if balanced {
                result["T"] = String(characters[1..<end])
                start = min(end + 1, characters.count)
            } else {
                // An unbalanced quote or bracket: the type cannot be read, so
                // it is left out, and the other codes are read after the
                // first comma.
                start = characters.firstIndex(of: ",").map { $0 + 1 } ?? characters.count
            }
        }
        // The runtime reads the first occurrence of a repeated code.
        for code in String(characters[start...]).split(separator: ",", omittingEmptySubsequences: true) where result[String(code.prefix(1))] == nil {
            result[String(code.prefix(1))] = String(code.dropFirst())
        }
        return result
    }

    // MARK: - Utilities

    private static func className(_ cls: AnyClass) -> String {
        return String(cString: class_getName(cls))
    }

    // Byte-wise, because Swift's String == treats strings that are equal under
    // Unicode normalization as equal and the runtime does not.
    private static func sameBytes(_ lhs: String, _ rhs: String) -> Bool {
        return lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
