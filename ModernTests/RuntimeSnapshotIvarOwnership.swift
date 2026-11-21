//
//  RuntimeSnapshotIvarOwnership.swift
//  ModernTests
//
//  The ownership of each ivar as far as the Objective-C runtime can tell it,
//  for the runtime snapshot (docs/swift-migration/phase0.md section 9). The
//  runtime keeps two bitmaps per class, the strong and the weak ivar layout,
//  which say which pointer-sized words of the class's own ivars ARC retains
//  and which it holds weakly. Everything else about ownership is not in the
//  runtime, and the labels say so rather than guess. The standing rule: where
//  the runtime cannot answer, say what it cannot tell apart; never print
//  "not owned".
//
//  Where the facts come from, each checked against objc4 and clang sources
//  (objc-class.mm isScanned and _class_lookUpIvar; CGObjCMac.cpp
//  BuildIvarLayout and IvarLayoutBuilder::buildBitmap):
//
//  - The layout format. A layout is a C string of bytes. In each byte the high
//    nibble is a number of words to skip and the low nibble a number of words
//    to scan (that is, words in the layout), skip first; a zero byte ends it.
//    A run longer than 15 continues in the next byte (clang writes 0xF0 bytes
//    for long skips and 0x0F bytes for long scans). ARC layouts have no other
//    encoding: no special value for "all strong" or "all weak", and no
//    compact form packed into the pointer; those existed for the garbage
//    collector, which is gone. A null layout and an empty one (a lone zero
//    byte, as a class made at run time has) both scan nothing.
//  - Word zero is the class's instance start rounded up to a word. The
//    compiler sets the instance start to the offset of the class's first
//    ivar, and when the runtime slides a subclass's ivars because its
//    superclass grew, it moves the instance start by the same amount, so the
//    start is the smallest offset among the class's own ivars. The layouts
//    cover only the class's own ivars, never its superclasses'.
//  - What clang puts in the layouts. The strong layout has every __strong
//    object or block pointer, including unqualified ones, which ARC makes
//    strong, and the same inside structs, unions, C++ classes and fixed
//    arrays, word by word; the weak layout has the __weak ones. Nothing else:
//    not __unsafe_unretained pointers, not Class pointers with no qualifier
//    (ARC leaves them unretained), not C pointers of any kind (CFTypeRef,
//    id *, a pointer to a struct holding objects), not bitfields, not
//    pointers at offsets that are not a multiple of the word size, and not
//    memory a member owns elsewhere (the elements of a std::vector<id>).
//  - Without ARC clang writes no strong layout at all, and a weak layout
//    only for __weak ivars when -fobjc-weak is on. With ARC a class with no
//    strong ivar also has no strong layout. So a missing strong layout does
//    not say which; the class's ARC flag does. It is not public, so it is
//    read through the runtime's own _class_getIvarMemoryManagement (exported
//    SPI that key-value coding uses): for an ivar in neither layout it
//    answers "unretained" in a class compiled with ARC and "unknown"
//    otherwise. The flag is also clear for a class made at run time.
//  - A C++ member's destructor runs from the class's .cxx_destruct, which
//    the compiler adds when any ivar needs destruction (ARC strong and weak
//    ivars included).
//  - Swift classes. The runtime layouts do not describe Swift's own storage:
//    Swift writes no layouts and sets the ARC flag, so
//    _class_getIvarMemoryManagement answers "unretained" even for a strong
//    stored property. Ownership in a Swift class comes from the Swift
//    declaration, and the snapshot says so instead of reading the layouts.
//
//  The labels (one word each in the snapshot):
//
//    strong                 an object, block or Class pointer whose word is in
//                           the strong layout
//    weak                   one whose word is in the weak layout
//    unretained-or-manual   an object, block or Class pointer in neither
//                           layout, in a class compiled with ARC: declared
//                           __unsafe_unretained or assign, or a Class with no
//                           qualifier. ARC neither retains nor releases it;
//                           the runtime cannot tell a pointer that nothing
//                           retains from one the code retains by hand
//                           (CFRetain, CFBridgingRetain)
//    manual                 an object or block pointer, or a struct, in a class
//                           whose ARC flag is clear (compiled without ARC, or
//                           made at run time) and not in the weak layout:
//                           ownership is whatever the code does by hand and
//                           is not in the runtime
//    unretained-or-unknown  an object pointer in neither layout when the ARC
//                           flag cannot be read: unretained, or manually
//                           managed, or not known
//    arc-members            a struct, union, array or C++ object with at least
//                           one word in a layout; layout= says which; its
//                           other words are not ARC references, and may be
//                           scalars, C pointers, unretained pointers or C++
//                           members
//    cxx-object             a C++ object (its type name is qualified or a
//                           template) with no word in a layout, in a class
//                           with .cxx_destruct: a C++ object, whose
//                           destructor runs when the instance is destroyed;
//                           what its elements own depends on their types (a
//                           std::vector<Foo *> in a file compiled without ARC
//                           does not release its elements)
//    struct-or-cxx-object   a struct with no word in a layout, in a class with
//                           .cxx_destruct, whose type name does not show
//                           whether it is C++: a C++ object whose destructor
//                           runs when the instance is destroyed, or a C struct
//                           with no ARC references
//                           (any pointers in it managed by hand); the runtime
//                           cannot tell which
//    struct-no-destructor   a struct, union or array with no word in a layout
//                           in a class compiled with ARC that has no
//                           .cxx_destruct: no destructor runs for it, and ARC
//                           holds nothing in it; pointers in it, if any, are
//                           managed by hand
//    struct-unknown         a struct with no word in a layout when the ARC flag
//                           cannot be read
//    c-pointer              a C pointer (CFTypeRef, void *, id *, char *, a
//                           pointer to a struct): never in a layout; whether
//                           the code owns what it points to is not in the
//                           runtime
//    scalar                 a number, character or bool: no ownership
//    selector               a SEL: no ownership
//    bitfield               a bitfield: no ownership
//    unaligned-object       an object pointer at an offset that is not a
//                           multiple of the word size, which the layouts
//                           cannot describe: unknown
//    unknown-type           an ivar whose type encoding is empty or not one
//                           this tool recognizes: unknown
//    swift                  an ivar of a Swift class: ownership comes from the
//                           Swift declaration, not the runtime
//
//  layout= lists the ivar's words in order, s for a word in the strong
//  layout, w for one in the weak layout and - for one in neither, with the
//  trailing - removed, so it is empty for an ivar with no word in a layout.
//
//  Conflicts, each written as an OWNERSHIP-CONFLICT line, which fails every
//  comparison: they are either a bug in this tool or a real surprise.
//
//    runtime-disagrees        _class_getIvarMemoryManagement's answer for an
//                             ivar's first word differs from this decoding
//    word-in-both-layouts     a word is in the strong and the weak layout
//    layout-word-on-non-object  a word of a C pointer, scalar, selector or
//                             bitfield is in a layout
//    layout-word-without-ivar a layout word belongs to none of the class's
//                             ivars
//    arc-flag-inconsistent    _class_getIvarMemoryManagement answered
//                             "unretained" for one ivar and "unknown" for
//                             another of the same class
//

import Foundation
import ObjectiveC

enum RuntimeSnapshotIvarOwnership {
    static let wordSize = MemoryLayout<UnsafeRawPointer>.size

    // _class_getIvarMemoryManagement's answers (objc_ivar_memory_management_t
    // in objc4's objc-internal.h).
    enum MemoryManagement: Int32 {
        case unknown = 0
        case strong = 1
        case weak = 2
        case unretained = 3
    }

    enum ARCFlag: String {
        case set
        case clear
        case unknown
    }

    static let labels = ["strong", "weak", "unretained-or-manual", "manual", "unretained-or-unknown",
                         "arc-members", "cxx-object", "struct-or-cxx-object", "struct-no-destructor",
                         "struct-unknown", "c-pointer", "scalar", "selector", "bitfield",
                         "unaligned-object", "unknown-type", "swift"]

    static let conflictReasons = ["runtime-disagrees", "word-in-both-layouts", "layout-word-on-non-object",
                                  "layout-word-without-ivar", "arc-flag-inconsistent"]

    // What a class's runtime metadata says, gathered by facts(of:ivars:...)
    // or written by hand in tests.
    struct ClassFacts {
        var isSwift: Bool
        var hasCxxDestruct: Bool
        // The layouts without their terminating zero byte, or nil when the
        // runtime has none.
        var strongLayout: [UInt8]?
        var weakLayout: [UInt8]?
        // class_getInstanceSize: the end of the instance, word aligned.
        var instanceSize: Int
        // _class_getIvarMemoryManagement for each ivar name, when it could be
        // asked. Missing entries mean it could not.
        var memoryManagement: [String: MemoryManagement]
    }

    struct Ivar {
        var name: String
        var encoding: String
        var offset: Int
    }

    struct IvarOwnership: Equatable {
        var label: String
        var layout: String
    }

    struct Conflict: Equatable {
        var reason: String
        var subject: String
    }

    struct Result {
        var arcFlag: ARCFlag
        var ivars: [String: IvarOwnership]
        var conflicts: [Conflict]
    }

    // The words a layout scans, in order. layout excludes the terminating
    // zero byte; decoding stops at a zero byte anyway, as the runtime does.
    static func scannedWords(_ layout: [UInt8]) -> [Int] {
        var words = [Int]()
        var index = 0
        for byte in layout {
            if byte == 0 {
                break
            }
            index += Int(byte >> 4)
            let scans = Int(byte & 0x0F)
            words.append(contentsOf: index..<(index + scans))
            index += scans
        }
        return words
    }

    // The bytes of a layout up to its terminating zero, or nil for none.
    static func layoutBytes(_ pointer: UnsafePointer<UInt8>?) -> [UInt8]? {
        guard let pointer else {
            return nil
        }
        var bytes = [UInt8]()
        var p = pointer
        while p.pointee != 0 {
            bytes.append(p.pointee)
            p += 1
        }
        return bytes
    }

    // The value of a strong-ivar-layout or weak-ivar-layout line: the bytes in
    // uppercase hexadecimal, terminator included, or nil for no layout.
    static func layoutLineValue(_ layout: [UInt8]?) -> String? {
        return layout.map { ($0 + [0]).map { String(format: "%02X", $0) }.joined() }
    }

    enum Kind {
        case object
        case aggregate
        case cPointer
        case scalar
        case selector
        case bitfield
        case unknown
    }

    // The kind of value an ivar's type encoding describes. Leading type
    // qualifiers (const, in, out and so on, and A for _Atomic) are skipped.
    static func kind(ofEncoding encoding: String) -> Kind {
        let qualifiers = Set("rnNoORVA")
        guard let first = encoding.first(where: { !qualifiers.contains($0) }) else {
            return .unknown
        }
        switch first {
        case "@", "#":
            return .object
        case "{", "(", "[":
            return .aggregate
        case "^", "*":
            return .cPointer
        case ":":
            return .selector
        case "b":
            return .bitfield
        case "c", "i", "s", "l", "q", "C", "I", "S", "L", "Q", "f", "d", "D", "B":
            return .scalar
        default:
            return .unknown
        }
    }

    // Whether a struct's type encoding names a C++ class: its name, between
    // the opening brace and the first =, holds a template argument list or a
    // qualified name. A C++ class with a plain name is not recognized, which
    // is why struct-or-cxx-object exists.
    static func encodingNamesCxxClass(_ encoding: String) -> Bool {
        guard encoding.hasPrefix("{") else {
            return false
        }
        let name = encoding.dropFirst().prefix { $0 != "=" }
        return name.contains("<") || name.contains("::")
    }

    // The class's ARC flag, from _class_getIvarMemoryManagement's answers for
    // ivars whose first word is word aligned and in neither layout, and from
    // the strong layout, which only a class compiled with ARC has. Also
    // returns a conflict when two answers disagree.
    static func arcFlag(ivars: [Ivar], facts: ClassFacts, start: Int, strong: Set<Int>, weak: Set<Int>) -> (ARCFlag, Conflict?) {
        var sawUnretained = false
        var sawUnknown = false
        for ivar in ivars where (ivar.offset - start) % wordSize == 0 && ivar.offset >= start {
            let word = (ivar.offset - start) / wordSize
            if strong.contains(word) || weak.contains(word) {
                continue
            }
            switch facts.memoryManagement[ivar.name] {
            case .unretained:
                sawUnretained = true
            case .unknown:
                sawUnknown = true
            case .strong, .weak, .none:
                break
            }
        }
        if sawUnretained && sawUnknown {
            return (.unknown, Conflict(reason: "arc-flag-inconsistent", subject: "class"))
        }
        if sawUnretained || !strong.isEmpty {
            return (.set, nil)
        }
        if sawUnknown {
            return (.clear, nil)
        }
        return (.unknown, nil)
    }

    static func ownership(ivars: [Ivar], facts: ClassFacts) -> Result {
        guard let start = ivars.map({ $0.offset }).min().map({ alignUp($0) }) else {
            return Result(arcFlag: .unknown, ivars: [:], conflicts: [])
        }
        let strong = Set(scannedWords(facts.strongLayout ?? []))
        let weak = Set(scannedWords(facts.weakLayout ?? []))
        var conflicts = [Conflict]()
        for word in strong.intersection(weak).sorted() {
            conflicts.append(Conflict(reason: "word-in-both-layouts", subject: "word=\(word)"))
        }
        let (flag, flagConflict) = arcFlag(ivars: ivars, facts: facts, start: start, strong: strong, weak: weak)
        if let flagConflict {
            conflicts.append(flagConflict)
        }

        // Each ivar's span runs from its offset to the next larger offset, or
        // to the end of the instance. Ivars at the same offset (bitfields in
        // one storage unit) share a span.
        let offsets = Array(Set(ivars.map { $0.offset })).sorted()
        func end(of offset: Int) -> Int {
            return offsets.first { $0 > offset } ?? max(facts.instanceSize, offset)
        }
        // The layout words in an ivar's span: words whose start lies in it.
        func words(of ivar: Ivar) -> [Int] {
            let first = max(0, (ivar.offset - start + wordSize - 1) / wordSize)
            let limit = end(of: ivar.offset)
            var result = [Int]()
            var word = first
            while start + word * wordSize < limit {
                result.append(word)
                word += 1
            }
            return result
        }

        var claimed = Set<Int>()
        var result = [String: IvarOwnership]()
        for ivar in ivars {
            let span = words(of: ivar)
            claimed.formUnion(span)
            var chars = span.map { strong.contains($0) ? "s" : (weak.contains($0) ? "w" : "-") }
            while chars.last == "-" {
                chars.removeLast()
            }
            let layout = chars.joined()
            let inLayout = !layout.isEmpty
            let kind = kind(ofEncoding: ivar.encoding)
            let aligned = (ivar.offset - start) % wordSize == 0 && ivar.offset >= start

            // The runtime's own answer for the ivar's first word must match.
            if !facts.isSwift, aligned, let answer = facts.memoryManagement[ivar.name] {
                let word = (ivar.offset - start) / wordSize
                let expected: [MemoryManagement]
                if strong.contains(word) {
                    expected = [.strong]
                } else if weak.contains(word) {
                    expected = [.weak]
                } else {
                    switch flag {
                    case .set:
                        expected = [.unretained]
                    case .clear:
                        expected = [.unknown]
                    case .unknown:
                        expected = [.unretained, .unknown]
                    }
                }
                if !expected.contains(answer) {
                    conflicts.append(Conflict(reason: "runtime-disagrees", subject: ivar.name))
                }
            }

            let label: String
            if facts.isSwift {
                label = "swift"
            } else {
                switch kind {
                case .object:
                    if !aligned {
                        label = inLayout ? "arc-members" : "unaligned-object"
                    } else if layout == "s" {
                        label = "strong"
                    } else if layout == "w" {
                        label = "weak"
                    } else if inLayout {
                        // An object pointer is one word, so its span holds at
                        // most one layout word; more means padding words in a
                        // layout, which only a decoding error produces.
                        label = "arc-members"
                        conflicts.append(Conflict(reason: "layout-word-without-ivar", subject: ivar.name))
                    } else {
                        switch flag {
                        case .set:
                            label = "unretained-or-manual"
                        case .clear:
                            label = "manual"
                        case .unknown:
                            label = "unretained-or-unknown"
                        }
                    }
                case .aggregate:
                    if inLayout {
                        label = "arc-members"
                    } else if facts.hasCxxDestruct {
                        label = encodingNamesCxxClass(ivar.encoding) ? "cxx-object" : "struct-or-cxx-object"
                    } else {
                        switch flag {
                        case .set:
                            label = "struct-no-destructor"
                        case .clear:
                            label = "manual"
                        case .unknown:
                            label = "struct-unknown"
                        }
                    }
                case .cPointer, .scalar, .selector, .bitfield:
                    switch kind {
                    case .cPointer:
                        label = "c-pointer"
                    case .scalar:
                        label = "scalar"
                    case .selector:
                        label = "selector"
                    default:
                        label = "bitfield"
                    }
                    if inLayout {
                        conflicts.append(Conflict(reason: "layout-word-on-non-object", subject: ivar.name))
                    }
                case .unknown:
                    label = inLayout ? "arc-members" : "unknown-type"
                }
            }
            result[ivar.name] = IvarOwnership(label: label, layout: layout)
        }
        if !facts.isSwift {
            for word in strong.union(weak).subtracting(claimed).sorted() {
                conflicts.append(Conflict(reason: "layout-word-without-ivar", subject: "word=\(word)"))
            }
        }
        return Result(arcFlag: flag, ivars: result, conflicts: conflicts)
    }

    private static func alignUp(_ value: Int) -> Int {
        return (value + wordSize - 1) / wordSize * wordSize
    }

    // MARK: - Reading the runtime

    private typealias MemoryManagementFunction = @convention(c) (AnyClass, OpaquePointer) -> Int32
    private typealias IsSwiftFunction = @convention(c) (AnyClass) -> UInt8

    // RTLD_DEFAULT, which Swift does not import.
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    private static let memoryManagementFunction: MemoryManagementFunction? = {
        return dlsym(defaultHandle, "_class_getIvarMemoryManagement").map { unsafeBitCast($0, to: MemoryManagementFunction.self) }
    }()

    private static let isSwiftFunction: IsSwiftFunction? = {
        return dlsym(defaultHandle, "_class_isSwift").map { unsafeBitCast($0, to: IsSwiftFunction.self) }
    }()

    // Whether the runtime marks the class as a Swift class, or nil if its SPI
    // for that is missing.
    static func runtimeSaysSwift(_ cls: AnyClass) -> Bool? {
        return isSwiftFunction.map { $0(cls) != 0 }
    }

    // _class_getIvarMemoryManagement for one ivar, or nil if the function is
    // missing or its answer is not one of the four it documents. It sends no
    // messages.
    static func memoryManagement(of cls: AnyClass, ivar: ObjectiveC.Ivar) -> MemoryManagement? {
        guard let function = memoryManagementFunction else {
            return nil
        }
        return MemoryManagement(rawValue: function(cls, ivar))
    }
}
