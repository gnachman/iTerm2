//
//  RuntimeSnapshotComparison.swift
//  ModernTests
//
//  Compares two Objective-C runtime snapshots produced by RuntimeSnapshot.swift
//  (docs/swift-migration/phase0.md section 9). A port must leave the runtime
//  surface of a class unchanged, so any difference that is not on the
//  allow-list below fails the comparison, and so does a duplicate selector or
//  property that is new or changed between the snapshots, or that has an
//  entry in the app's own image (counted from the method lines themselves, not
//  only from DUPLICATE lines; a repeat with no DUPLICATE line always fails).
//  A duplicate identical in both snapshots with every entry in a system image
//  is reported and does not fail: see resolveDuplicates (the owner,
//  2026-11-25).
//
//  The comparison gives a verdict only for a class whose language is objc in
//  both snapshots or swift in both. A class that changed language, or whose
//  language is unknown in either snapshot, gets no verdict and the comparison
//  does not pass; its differences are listed separately for a person to
//  check.
//
//  Input that is not exactly what RuntimeSnapshot.swift writes is refused
//  rather than compared. The parser enforces:
//  - The first line is exactly the format line, and no other line starts
//    with #. Every line, the last included, ends with a line feed; there are
//    no empty lines, and the command-line driver refuses a byte-order mark
//    and bytes that are not UTF-8.
//  - Header lines (architecture, build-configuration, build-variant), each
//    once, come before the first class section. architecture has exactly
//    one value; the other two have one or none.
//  - Class sections are "class <name>" ... "end class <name>", not nested,
//    each class once, with exactly one language, superclass, and image line.
//    The language line has exactly one value, objc, swift, or unknown; the
//    superclass and image lines have one value or none.
//  - Lines inside a class section are indented by exactly two spaces, and
//    lines outside are not indented. Within a line, fields are separated by
//    exactly one space, and no field is empty.
//  - Every field is in the canonical form RuntimeSnapshotFormat.escape
//    produces: only printable ASCII, with every other byte and every %
//    percent-escaped, and every escape one that escape writes. So a tab,
//    carriage return, any non-ASCII character, or NUL written as is in a line
//    is refused, while a C++ type encoding, whose spaces are written as %20,
//    is accepted.
//  - Each kind of line has exactly the fields, in exactly the order, that
//    the writer produces for it, each at most once, and no value begins with
//    =: see memberProblem. A method's image= never equals the image line of
//    its class, since the writer omits it then. The order of lines within a
//    class section is not significant, and an ownership label is not checked
//    against raw=.
//  Snapshots whose header lines differ are also refused.
//
//  An empty or absent value is written as nothing, never as a placeholder
//  word (see the comment at the top of RuntimeSnapshot.swift), so every
//  value that is written is an ordinary escaped name or encoding, whatever
//  its spelling: superclass (none) names a class called (none). A snapshot
//  whose first line names another format number is refused.
//
//  Exit status of the command-line driver: 0 when the snapshots match, 1 when
//  they differ or some class gets no verdict, 2 when the inputs cannot be
//  compared (bad arguments, an unreadable file, malformed input, or snapshots
//  from different architectures, configurations, or variants).
//
//  This file uses only Foundation. Besides being part of ModernTests, it is
//  compiled on its own by tools/swift_migration/compare_runtime_snapshots.sh so
//  that two snapshot files can be compared without launching the test host.
//  Keep it free of dependencies on the app.
//

import Foundation


enum RuntimeSnapshotFormat {
    // The first line of every snapshot. Bump the number if the format changes
    // in a way that makes old and new snapshots incomparable.
    static let headerLine = "# Objective-C runtime snapshot, format 3"

    // Header lines that say what the snapshot was taken from. Snapshots that
    // differ in any of them cannot be compared.
    static let architectureKeyword = "architecture"
    static let buildConfigurationKeyword = "build-configuration"
    static let buildVariantKeyword = "build-variant"
    static let headerKeywords = [architectureKeyword, buildConfigurationKeyword, buildVariantKeyword]

    // The line in each class section that says which compiler defined it, and
    // its values.
    static let languageKeyword = "language"
    static let objcLanguage = "objc"
    static let swiftLanguage = "swift"
    static let unknownLanguage = "unknown"
    static let languages = [objcLanguage, swiftLanguage, unknownLanguage]

    // Lines with at most one value after the keyword, of which every class
    // section has exactly one.
    static let superclassKeyword = "superclass"
    static let imageKeyword = "image"
    // The class's ARC flag as the runtime reveals it (set, clear, or
    // unknown), and its strong and weak ivar layouts in hexadecimal with
    // their terminating zero byte, or no value when the runtime has none. See
    // RuntimeSnapshotIvarOwnership.swift.
    static let arcFlagKeyword = "ivar-arc-flag"
    static let strongLayoutKeyword = "strong-ivar-layout"
    static let weakLayoutKeyword = "weak-ivar-layout"
    static let arcFlags = ["set", "clear", "unknown"]
    static let singleValueKeywords = [languageKeyword, superclassKeyword, imageKeyword,
                                      arcFlagKeyword, strongLayoutKeyword, weakLayoutKeyword]

    // The keywords of header and class-section lines that are written with
    // no value when theirs is absent. The others always have one.
    static let optionalValueKeywords = [buildConfigurationKeyword, buildVariantKeyword, superclassKeyword, imageKeyword,
                                        strongLayoutKeyword, weakLayoutKeyword]

    // Lines of the form "<kind> <name> [<details>]", any number of each.
    static let memberKinds = ["protocol", "ivar", "class-method", "instance-method", "class-property", "instance-property"]

    // Prefix of the line that flags a selector or property appearing more than
    // once in a class's own list.
    static let duplicateKeyword = "DUPLICATE"

    // Prefix of the line that flags an ivar ownership conflict: the layouts
    // contradict each other, the ivar list, or the runtime's own answer.
    static let ownershipConflictKeyword = "OWNERSHIP-CONFLICT"

    // The labels an ivar line's ownership= can carry, and the reasons an
    // OWNERSHIP-CONFLICT line can give. Kept here, not taken from
    // RuntimeSnapshotIvarOwnership.swift, because this file is compiled on
    // its own; a test checks that the lists agree.
    static let ivarOwnerships = ["strong", "weak", "unretained-or-manual", "manual", "unretained-or-unknown",
                                 "arc-members", "cxx-object", "struct-or-cxx-object", "struct-no-destructor",
                                 "struct-unknown", "c-pointer", "scalar", "selector", "bitfield",
                                 "unaligned-object", "unknown-type", "swift"]
    static let ownershipConflictReasons = ["runtime-disagrees", "word-in-both-layouts", "layout-word-on-non-object",
                                           "layout-word-without-ivar", "arc-flag-inconsistent"]

    // The ownership labels a property line can carry.
    static let ownerships = ["copy", "strong", "weak", "weak-or-unowned", "unsafe_unretained", "unrecorded", "assign"]

    // Writes a name or value so that it contains no space or other character
    // that would make a line ambiguous or invisible. Every byte of its UTF-8
    // form that is not printable ASCII (below 0x21, 0x7F, or 0x80 and above),
    // and every %, is written as % and two uppercase hexadecimal digits. So
    // all non-ASCII text is escaped byte by byte. The rule uses no Unicode
    // tables, so it gives the same result on every OS version, and it is one
    // to one, so names that differ still differ.
    static func escape(_ value: String) -> String {
        var result = [UInt8]()
        let hex = Array("0123456789ABCDEF".utf8)
        for byte in value.utf8 {
            if byte < 0x21 || byte >= 0x7F || byte == UInt8(ascii: "%") {
                result.append(contentsOf: [UInt8(ascii: "%"), hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]])
            } else {
                result.append(byte)
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    // Whether a field is exactly what escape writes for some value: only
    // printable ASCII, every % followed by two uppercase hexadecimal digits,
    // the escaped bytes forming valid UTF-8, and no byte escaped that escape
    // would have left alone.
    static func isCanonical(_ field: String) -> Bool {
        let bytes = Array(field.utf8)
        var decoded = [UInt8]()
        var i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "%") {
                guard i + 2 < bytes.count,
                      let byte = UInt8(String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) else {
                    return false
                }
                decoded.append(byte)
                i += 3
            } else {
                decoded.append(bytes[i])
                i += 1
            }
        }
        guard let value = String(bytes: decoded, encoding: .utf8) else {
            return false
        }
        return Array(escape(value).utf8) == bytes
    }

    // What a passing comparison does not establish, printed with every pass.
    static let notCoveredByPass = [
        "A pass means only that the recorded lines match. Known gaps, which this tool does not compare:",
        "- what methods do, including methods that decide at run time which selectors or keys an object answers (respondsToSelector:, forwarding, method resolution, valueForUndefinedKey:), so selectors a class forwards or resolves dynamically are not covered",
        "- the contents of adopted protocols; only their names are recorded",
        "- classes not named in the snapshot, including the members of superclasses and subclasses",
        "- the ownership of an ivar labeled unretained-or-manual, manual, unretained-or-unknown, struct-or-cxx-object, struct-no-destructor, struct-unknown, c-pointer, unaligned-object or unknown-type, or the words of an arc-members ivar outside the layouts, which the runtime cannot tell; check them against the source or with tools/swift_migration/ivar_ownership_check.py",
        "- the ownership of the stored properties of a Swift class, which the runtime layouts do not describe",
        "- the type of an ivar whose encoding the runtime leaves unknown or empty",
        "- the class of an object parameter or return value, which every method encoding writes as plain @, so NSString * becoming NSArray *, or id becoming a class, is not seen; the reviewer compares the Swift signatures with the Objective-C declarations (for an Objective-C header, the Swift interface snapshot, tools/swift_migration/swift_interface.py, shows the types Swift sees)",
        "- nullability: a Swift parameter that is not optional where the Objective-C method accepted nil (a nil passed from Objective-C then traps) is not seen; nullability claims are made and proven by the annotate process (docs/swift-migration/nullability.md) and checked at run time by the nullability sanitizer configuration (phase0.md section 4)",
        "- ivar declaration order, which decides teardown order under ARC",
        "- the ownership of a property printed as unrecorded",
        "- weak versus unowned in Swift, including a property that a Swift extension declares on an Objective-C class, which is printed as weak even when Swift declared it unowned",
        "- for a Swift class, whether a member is dynamic",
        "- build configurations other than the one snapshotted",
    ].joined(separator: "\n")
}

// One expected difference between a before and an after snapshot. An entry
// allows only the line's appearance or disappearance: one snapshot has no line
// for the key and the other has exactly one. Any other change to the line is
// still a difference.
struct RuntimeSnapshotAllowedDifference: Equatable {
    // The line kind, such as "instance-method".
    var kind: String
    // The second field of the line, such as "-.cxx_destruct".
    var name: String
    // Why this difference is expected.
    var reason: String
}

struct RuntimeSnapshotComparisonResult {
    // Duplicate-selector lines found in either snapshot that are new or
    // changed between them or have an entry in the app's own image, and
    // repeats with no DUPLICATE line. Any entry fails the comparison.
    var duplicates: [String] = []
    // Duplicates identical in both snapshots with every entry in a system
    // image. Reported but not a failure.
    var ignoredDuplicates: [String] = []
    // OWNERSHIP-CONFLICT lines found in either snapshot. Any entry fails the
    // comparison.
    var ownershipConflicts: [String] = []
    // Differences not covered by the allow-list. Any entry fails the comparison.
    var differences: [String] = []
    // Differences covered by the allow-list. Reported but not a failure.
    var allowed: [String] = []
    // Reasons the inputs cannot be compared: malformed input, or snapshots
    // taken from different architectures, configurations, or variants. Any
    // entry fails the comparison.
    var errors: [String] = []
    // Classes defined in Objective-C in one snapshot and in Swift in the
    // other. Any entry fails the comparison: this tool does not yet classify
    // the differences such a change brings, so it cannot give a verdict.
    var languageChanges: [String] = []
    // Classes whose language is unknown in either snapshot. Any entry fails
    // the comparison: the snapshot cannot say which compiler's rules apply to
    // such a class, so this tool gives no verdict for it.
    var unknownLanguages: [String] = []
    // Classes with no valid language line in either snapshot. The parse
    // errors fail the comparison; this lists the classes that therefore get
    // no verdict.
    var invalidLanguages: [String] = []
    // Differences in classes that get no verdict, for a person to check.
    var unclassified: [String] = []
    // Classes that moved from Objective-C to Swift, compared by the rule
    // "identical in meaning" (docs/swift-migration/phase0.md section 9).
    var crossLanguageClasses: [String] = []
    // Differences such a move is known to bring, each with the reason it is
    // harmless. Reported but not a failure.
    var classified: [String] = []
    // Differences the runtime cannot judge, each saying what to check in the
    // source. Reported but not a failure: the reviewer checks each one.
    var checks: [String] = []

    var passed: Bool {
        return duplicates.isEmpty && ownershipConflicts.isEmpty && differences.isEmpty && errors.isEmpty && languageChanges.isEmpty && unknownLanguages.isEmpty && invalidLanguages.isEmpty
    }

    var report: String {
        var lines = [String]()
        let noVerdict = languageChanges + unknownLanguages + invalidLanguages
        if !noVerdict.isEmpty {
            lines.append("NO VERDICT for these classes:")
            lines.append(contentsOf: noVerdict.map { "  " + $0 })
            if !languageChanges.isEmpty {
                lines.append("  When a class moves between Objective-C and Swift, differences in property attribute order, ivar names, and ivar type encodings are expected. This tool does not yet tell those systematic differences from real ones, so for a class that changed language it gives no verdict.")
            }
            if !unknownLanguages.isEmpty {
                lines.append("  A class whose language is unknown was made at run time with a period in its name, so the snapshot cannot say which compiler's rules apply to it; for example, it cannot tell a weak property from an unowned one. This tool gives no verdict for such a class.")
            }
            if !invalidLanguages.isEmpty {
                lines.append("  A class with no valid language line comes from a snapshot that is not well formed; see ERRORS.")
            }
            if unclassified.isEmpty {
                lines.append("  No other differences were found in them, which this tool also cannot vouch for.")
            } else {
                lines.append("  Their differences are listed under UNCLASSIFIED DIFFERENCES for a person to check.")
            }
        }
        if !errors.isEmpty {
            lines.append("ERRORS:")
            lines.append(contentsOf: errors.map { "  " + $0 })
        }
        if !duplicates.isEmpty {
            lines.append("DUPLICATES (a selector listed more than once in one class's method list, so which implementation runs is undefined; or a property listed more than once with different attributes):")
            lines.append(contentsOf: duplicates.map { "  " + $0 })
        }
        if !ownershipConflicts.isEmpty {
            lines.append("OWNERSHIP CONFLICTS (the ivar layouts contradict each other, the ivar list, or the runtime's own answer: a bug in the snapshot tool or a real surprise):")
            lines.append(contentsOf: ownershipConflicts.map { "  " + $0 })
        }
        if !differences.isEmpty {
            lines.append("DIFFERENCES:")
            lines.append(contentsOf: differences.map { "  " + $0 })
        }
        if !unclassified.isEmpty {
            lines.append("UNCLASSIFIED DIFFERENCES (in classes that get no verdict):")
            lines.append(contentsOf: unclassified.map { "  " + $0 })
        }
        if !crossLanguageClasses.isEmpty {
            lines.append("MOVED FROM OBJECTIVE-C TO SWIFT, compared by the rule “identical in meaning”:")
            lines.append(contentsOf: crossLanguageClasses.map { "  class " + $0 })
        }
        if !checks.isEmpty {
            lines.append("CHECK AGAINST THE SOURCE (the runtime cannot tell whether these keep the meaning; the reviewer checks each one):")
            lines.append(contentsOf: checks.map { "  " + $0 })
        }
        if !classified.isEmpty {
            lines.append("Expected differences of a move to Swift:")
            lines.append(contentsOf: classified.map { "  " + $0 })
        }
        if !allowed.isEmpty {
            lines.append("Allowed differences:")
            lines.append(contentsOf: allowed.map { "  " + $0 })
        }
        if !ignoredDuplicates.isEmpty {
            lines.append("Duplicates present in both snapshots, not from this app: ignored (identical before and after, every entry in a system image; the owner, 2026-11-25):")
            lines.append(contentsOf: ignoredDuplicates.map { "  " + $0 })
        }
        if !noVerdict.isEmpty {
            lines.append("NO VERDICT for some classes, so the comparison does not pass.")
        }
        if !errors.isEmpty {
            lines.append("ERROR: the inputs cannot be compared.")
        } else if !duplicates.isEmpty || !ownershipConflicts.isEmpty || !differences.isEmpty {
            lines.append("FAIL: the snapshots do not match.")
        } else if passed {
            if crossLanguageClasses.isEmpty {
                lines.append("PASS: the snapshots match.")
            } else {
                lines.append("PASS: the snapshots match, and the classes that moved to Swift are identical in meaning apart from the expected differences" +
                             (checks.isEmpty ? "." : ", with \(checks.count) item\(checks.count == 1 ? "" : "s") to check against the source (see CHECK AGAINST THE SOURCE)."))
            }
            lines.append(RuntimeSnapshotFormat.notCoveredByPass)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum RuntimeSnapshotComparison {
    // The expected differences between a class's snapshot before and after a
    // port, each with the reason it is harmless. An entry is added only when a
    // real port has shown that the difference occurs and is harmless. The list
    // is empty: no such difference has been shown yet.
    static let allowedDifferences: [RuntimeSnapshotAllowedDifference] = []

    static func compare(before: String,
                        after: String,
                        allowedDifferences: [RuntimeSnapshotAllowedDifference] = allowedDifferences) -> RuntimeSnapshotComparisonResult {
        var result = RuntimeSnapshotComparisonResult()
        // Everything is parsed as UTF-8 bytes and compared as bytes: two
        // strings that Swift considers equal because they are equal under
        // Unicode normalization are different selectors to the runtime.
        let (beforeHeader, beforeClasses, beforeDuplicates) = parse(before, label: "before", result: &result)
        let (afterHeader, afterClasses, afterDuplicates) = parse(after, label: "after", result: &result)
        resolveDuplicates(before: beforeDuplicates,
                          beforeClasses: beforeClasses,
                          after: afterDuplicates,
                          afterClasses: afterClasses,
                          result: &result)

        let reasons = [
            RuntimeSnapshotFormat.architectureKeyword: "Type encodings differ between architectures",
            RuntimeSnapshotFormat.buildConfigurationKeyword: "Macros, and so methods, differ between build configurations",
            RuntimeSnapshotFormat.buildVariantKeyword: "Sanitizer variants are built with different macros",
        ]
        for keyword in RuntimeSnapshotFormat.headerKeywords {
            if let beforeValue = beforeHeader[Bytes(keyword)],
               let afterValue = afterHeader[Bytes(keyword)],
               beforeValue != afterValue {
                result.errors.append("The snapshots were taken with different \(keyword): before \(describeValue(beforeValue)), after \(describeValue(afterValue)). \(reasons[keyword] ?? ""), so they cannot be compared.")
            }
        }

        let classNames = Set(beforeClasses.keys).union(afterClasses.keys).sorted()
        for className in classNames {
            guard let beforeClass = beforeClasses[className] else {
                result.differences.append("class \(className): only in after")
                continue
            }
            guard let afterClass = afterClasses[className] else {
                result.differences.append("class \(className): only in before")
                continue
            }
            compare(className: className,
                    before: beforeClass,
                    after: afterClass,
                    allowedDifferences: allowedDifferences,
                    result: &result)
        }
        return result
    }

    // The command-line driver's behavior, here so that tests can reach it.
    // Exit status 0 means the snapshots match; 1 that they differ or that some
    // class gets no verdict; 2 that they cannot be compared: a usage error, an
    // unreadable file, input that is not a well-formed snapshot, or snapshots
    // with different header lines.
    static func runCommandLine(arguments: [String],
                               readFile: (String) throws -> Data) -> (output: String, error: String, status: Int32) {
        guard arguments.count == 3 else {
            return ("", "Usage: compare_runtime_snapshots <before-file> <after-file>\n", 2)
        }
        var contents = [String]()
        for path in arguments[1...] {
            do {
                let data = try readFile(path)
                if data.starts(with: [0xEF, 0xBB, 0xBF]) {
                    return ("", "\(path) begins with a byte-order mark, which a runtime snapshot never has\n", 2)
                }
                guard let text = String(bytes: data, encoding: .utf8) else {
                    return ("", "\(path) is not valid UTF-8\n", 2)
                }
                contents.append(text)
            } catch {
                return ("", "Cannot read \(path): \(error.localizedDescription)\n", 2)
            }
        }
        let result = compare(before: contents[0], after: contents[1])
        let status: Int32
        if !result.errors.isEmpty {
            status = 2
        } else if result.passed {
            status = 0
        } else {
            status = 1
        }
        return (result.report, "", status)
    }

    // MARK: - Private

    // A string compared, hashed, and sorted by its UTF-8 bytes.
    private struct Bytes: Hashable, Comparable, CustomStringConvertible {
        let utf8: [UInt8]

        init(_ string: String) {
            utf8 = Array(string.utf8)
        }

        init(_ bytes: ArraySlice<UInt8>) {
            utf8 = Array(bytes)
        }

        var description: String {
            return String(decoding: utf8, as: UTF8.self)
        }

        var isEmpty: Bool {
            return utf8.isEmpty
        }

        static func < (lhs: Bytes, rhs: Bytes) -> Bool {
            return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
    }

    private struct Key: Hashable {
        var kind: Bytes
        var name: Bytes

        init(kind: Bytes, name: Bytes) {
            self.kind = kind
            self.name = name
        }

        init(kind: String, name: String) {
            self.init(kind: Bytes(kind), name: Bytes(name))
        }
    }

    // For each key, the rest of the line, once per occurrence.
    private typealias ParsedClass = [Key: [Bytes]]

    // A duplicate found in one snapshot: a DUPLICATE line, or a repeat that
    // has none (declared false), which always fails.
    private struct DuplicateRecord {
        var className: Bytes
        var key: Key
        var text: String
        var declared: Bool
    }

    private struct ClassMember: Hashable {
        var className: Bytes
        var key: Key
    }

    // File names of the app's own images, besides any whose name begins with
    // iterm or ModernTests (in any case): the frameworks embedded in the app
    // and its other binaries. A snapshot records only an image's file name,
    // so a framework the app starts embedding must be added here; until it
    // is, a duplicate in it identical in both snapshots is ignored.
    static let appImageNames: Set<String> = ["__preview.dylib", "BetterFontPicker", "ColorPicker", "CoreParse",
                                             "Highlightr", "NMSSH", "PSMTabBarControl", "SearchableComboListView",
                                             "ShellLauncher", "Sparkle", "SwiftyMarkdown", "pidinfo"]

    // Whether an image is the app's own: one of appImageNames, a name
    // beginning with iterm or moderntests ignoring case, or a sanitizer
    // runtime the app bundle carries (libclang_rt.).
    static func isAppImage(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return appImageNames.contains(name) || lowered.hasPrefix("iterm") || lowered.hasPrefix("moderntests") ||
            lowered.hasPrefix("libclang_rt.")
    }

    // The sorted distinct images of a duplicate's entries, or nil when any
    // entry is in the app's own image or in no binary. An entry with no
    // image= is in the class's own image (the writer omits image= then); an
    // empty image=, or a class image line with no value, means no binary,
    // which is treated as the app's, the safe direction. Property lines have
    // no image=, so a property's entries are in the class's image.
    private static func systemImages(of details: [Bytes], in section: ParsedClass?) -> [String]? {
        let classImages = section?[Key(kind: RuntimeSnapshotFormat.imageKeyword, name: "")] ?? []
        let classImage: String? = classImages.count == 1 && !classImages[0].isEmpty ? classImages[0].description : nil
        var images = Set<String>()
        for detail in details {
            let field = detail.description.split(separator: " ").first { $0.hasPrefix("image=") }
            let image: String?
            if let field {
                let value = String(field.dropFirst("image=".count))
                image = value.isEmpty ? nil : value
            } else {
                image = classImage
            }
            guard let image, !isAppImage(image) else {
                return nil
            }
            images.insert(image)
        }
        return images.sorted(by: utf8Less)
    }

    // Decides which duplicates fail. A duplicate is ignored, and listed under
    // ignoredDuplicates, only when both snapshots have the same DUPLICATE
    // line for it, its entries are identical in both (so the count, the
    // encodings and the images match), and none of them is in the app's own
    // image. Every other duplicate fails, as does every repeat with no
    // DUPLICATE line. The owner, 2026-11-25, asked “may the comparison
    // ignore a duplicate that is present identically in both snapshots and
    // isn't in the unit's own code?”, answered “Yes, of course”.
    private static func resolveDuplicates(before: [DuplicateRecord],
                                          beforeClasses: [Bytes: ParsedClass],
                                          after: [DuplicateRecord],
                                          afterClasses: [Bytes: ParsedClass],
                                          result: inout RuntimeSnapshotComparisonResult) {
        var afterByMember = [ClassMember: DuplicateRecord]()
        for record in after where record.declared {
            afterByMember[ClassMember(className: record.className, key: record.key)] = record
        }
        var ignored = Set<ClassMember>()
        var ignoredLines = [String]()
        for record in before where record.declared {
            let member = ClassMember(className: record.className, key: record.key)
            guard let other = afterByMember[member], other.text == record.text else {
                continue
            }
            let beforeDetails = (beforeClasses[record.className]?[record.key] ?? []).sorted()
            let afterDetails = (afterClasses[record.className]?[record.key] ?? []).sorted()
            guard beforeDetails.count >= 2, beforeDetails == afterDetails,
                  let beforeImages = systemImages(of: beforeDetails, in: beforeClasses[record.className]),
                  let afterImages = systemImages(of: afterDetails, in: afterClasses[record.className]),
                  beforeImages == afterImages else {
                continue
            }
            ignored.insert(member)
            ignoredLines.append("class \(record.className): \(record.text) (images \(beforeImages.joined(separator: ", ")))")
        }
        result.ignoredDuplicates.append(contentsOf: ignoredLines.sorted(by: utf8Less))
        for (label, records) in [("before", before), ("after", after)] {
            for record in records where !ignored.contains(ClassMember(className: record.className, key: record.key)) || !record.declared {
                result.duplicates.append("\(label): class \(record.className): \(record.text)")
            }
        }
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func compare(className: Bytes,
                                before: ParsedClass,
                                after: ParsedClass,
                                allowedDifferences: [RuntimeSnapshotAllowedDifference],
                                result: inout RuntimeSnapshotComparisonResult) {
        let languageKey = Key(kind: RuntimeSnapshotFormat.languageKeyword, name: "")
        // A verdict needs the language to be objc in both snapshots or swift
        // in both. Anything else, including a missing or repeated language
        // line (which parse(_:label:result:) also reports as an error), gets
        // no verdict.
        let beforeLanguage = before[languageKey].flatMap { $0.count == 1 ? $0[0] : nil }
        let afterLanguage = after[languageKey].flatMap { $0.count == 1 ? $0[0] : nil }
        let known = [Bytes(RuntimeSnapshotFormat.objcLanguage), Bytes(RuntimeSnapshotFormat.swiftLanguage)]
        let valid = Set(RuntimeSnapshotFormat.languages.map { Bytes($0) })
        let beforeValid = beforeLanguage.map { valid.contains($0) } ?? false
        let afterValid = afterLanguage.map { valid.contains($0) } ?? false
        let noVerdict: Bool
        if !beforeValid || !afterValid {
            noVerdict = true
            if !beforeValid && !afterValid {
                result.invalidLanguages.append("class \(className): no valid language line in either snapshot")
            } else {
                result.invalidLanguages.append("class \(className): no valid language line \(beforeValid ? "after" : "before")")
            }
        } else if let beforeLanguage, let afterLanguage, known.contains(beforeLanguage), known.contains(afterLanguage) {
            if beforeLanguage == Bytes(RuntimeSnapshotFormat.objcLanguage) && afterLanguage == Bytes(RuntimeSnapshotFormat.swiftLanguage) {
                // A port: compared by the rule "identical in meaning".
                compareAcrossLanguages(className: className, before: before, after: after, result: &result)
                return
            }
            noVerdict = beforeLanguage != afterLanguage
            if noVerdict {
                result.languageChanges.append("class \(className) changed language from \(beforeLanguage) to \(afterLanguage)")
            }
        } else {
            noVerdict = true
            let beforeText = beforeLanguage?.description ?? ""
            let afterText = afterLanguage?.description ?? ""
            if beforeLanguage == afterLanguage {
                result.unknownLanguages.append("class \(className): language \(beforeText) in both snapshots")
            } else {
                result.unknownLanguages.append("class \(className): language \(beforeText) before, \(afterText) after")
            }
        }
        let keys = Set(before.keys).union(after.keys).sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            return lhs.name < rhs.name
        }
        for key in keys where key != languageKey {
            let beforeDetails = (before[key] ?? []).sorted()
            let afterDetails = (after[key] ?? []).sorted()
            if beforeDetails == afterDetails {
                continue
            }
            let description: String
            if beforeDetails.count == 1 && afterDetails.count == 1 {
                description = "class \(className): changed \(describe(key))\n" +
                    "      before: \(describeValue(beforeDetails[0]))\n" +
                    "      after:  \(describeValue(afterDetails[0]))"
            } else if beforeDetails.isEmpty {
                description = "class \(className): added \(describe(key)) \(joined(afterDetails, " | "))"
            } else if afterDetails.isEmpty {
                description = "class \(className): removed \(describe(key)) \(joined(beforeDetails, " | "))"
            } else {
                description = "class \(className): changed \(describe(key))\n" +
                    "      before: \(joined(beforeDetails, " | "))\n" +
                    "      after:  \(joined(afterDetails, " | "))"
            }
            let appearedOrDisappeared = (beforeDetails.isEmpty && afterDetails.count == 1) ||
                (afterDetails.isEmpty && beforeDetails.count == 1)
            if noVerdict {
                result.unclassified.append(description)
            } else if beforeDetails.isEmpty, afterDetails.count == 1,
                      key.kind == Bytes("instance-property") || key.kind == Bytes("class-property"),
                      let reason = swiftOverridePropertyReason(key: key, detail: afterDetails[0], before: before, after: after) {
                // A class already in Swift whose override of an inherited
                // getter became `override var`.
                result.classified.append(description + "\n      expected because: " + reason)
            } else if appearedOrDisappeared,
                      let allowance = allowedDifferences.first(where: { Bytes($0.kind) == key.kind && Bytes($0.name) == key.name }) {
                result.allowed.append(description + "\n      allowed because: " + allowance.reason)
            } else {
                result.differences.append(description)
            }
        }
    }

    // Recounts repeated lines with the same rules RuntimeSnapshot.swift uses
    // to write DUPLICATE lines, so a snapshot whose DUPLICATE line is missing
    // or was removed still fails: any repeated method except +load, and any
    // repeated property whose attributes differ.
    private static func undeclaredDuplicates(in parsed: ParsedClass, declared: Set<Key>) -> [(key: Key, text: String)] {
        var result = [(key: Key, text: String)]()
        for (key, details) in parsed where details.count > 1 && !declared.contains(key) {
            let flagged: Bool
            if key.kind == Bytes("class-method") {
                flagged = key.name != Bytes("+load")
            } else if key.kind == Bytes("instance-method") {
                flagged = true
            } else if key.kind == Bytes("class-property") || key.kind == Bytes("instance-property") {
                flagged = Set(details).count > 1
            } else {
                flagged = false
            }
            if flagged {
                result.append((key, "\(key.kind) \(key.name) appears \(details.count) times with no DUPLICATE line"))
            }
        }
        return result.sorted { utf8Less($0.text, $1.text) }
    }

    private static func describe(_ key: Key) -> String {
        if key.name.isEmpty {
            return key.kind.description
        }
        return "\(key.kind) \(key.name)"
    }

    // A value for a report. A line with no value is described in words that
    // contain a space, which no escaped value does, so the description cannot
    // be mistaken for a value.
    private static func describeValue(_ value: Bytes) -> String {
        return value.isEmpty ? "(no value)" : value.description
    }

    private static func joined(_ values: [Bytes], _ separator: String) -> String {
        return values.map { $0.description }.joined(separator: separator)
    }

    // Parses one snapshot. Every way in which the input is not exactly what
    // RuntimeSnapshot.swift writes is added to result.errors.
    private static func parse(_ text: String,
                              label: String,
                              result: inout RuntimeSnapshotComparisonResult) -> (header: [Bytes: Bytes], classes: [Bytes: ParsedClass], duplicates: [DuplicateRecord]) {
        let space = UInt8(ascii: " ")
        var lines = Array(text.utf8).split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        // Every line, the last included, ends with a line feed, so splitting
        // leaves an empty element at the end.
        guard lines.count > 1, let last = lines.last, last.isEmpty else {
            if text.isEmpty {
                result.errors.append("\(label): empty input, so this is not a runtime snapshot")
            } else {
                result.errors.append("\(label): the last line has no line terminator, so the snapshot is truncated")
            }
            return ([:], [:], [])
        }
        lines.removeLast()
        guard Bytes(lines[0]) == Bytes(RuntimeSnapshotFormat.headerLine) else {
            result.errors.append("\(label): the first line is not “\(RuntimeSnapshotFormat.headerLine)”, so this is not a runtime snapshot in a known format")
            return ([:], [:], [])
        }

        var header = [Bytes: Bytes]()
        var classes = [Bytes: ParsedClass]()
        var currentClassName: Bytes?
        var current = ParsedClass()
        // Keys named by the open class's DUPLICATE lines.
        var declaredDuplicates = Set<Key>()
        var duplicates = [DuplicateRecord]()

        for (index, raw) in lines.enumerated().dropFirst() {
            let lineNumber = index + 1
            let prefix = "\(label) line \(lineNumber): “\(Bytes(raw))”"
            if raw.isEmpty {
                result.errors.append("\(label) line \(lineNumber): an empty line")
                continue
            }
            if raw.first == UInt8(ascii: "#") {
                result.errors.append("\(prefix) starts with #, but only the first line of a snapshot may")
                continue
            }
            let indented = raw.starts(with: [space, space])
            let content = indented ? raw.dropFirst(2) : raw
            let fields = content.split(separator: space, omittingEmptySubsequences: false).map { Bytes($0) }
            if fields.contains(where: { $0.isEmpty }) {
                result.errors.append("\(prefix) has an empty field: fields are separated by exactly one space, and a line has no other leading or trailing space")
                continue
            }
            if let bad = fields.first(where: { !RuntimeSnapshotFormat.isCanonical($0.description) }) {
                result.errors.append("\(prefix) has the field “\(bad)”, which contains whitespace, a control or format character, or a percent sign that is not written as the snapshot writes it")
                continue
            }

            if !indented {
                if fields.count == 2 && fields[0] == Bytes("class") {
                    if let open = currentClassName {
                        result.errors.append("\(label) line \(lineNumber): class \(fields[1]) begins before class \(open) ends")
                    }
                    currentClassName = fields[1]
                    current = ParsedClass()
                    declaredDuplicates = []
                } else if fields.count == 3 && fields[0] == Bytes("end") && fields[1] == Bytes("class") {
                    guard let name = currentClassName else {
                        result.errors.append("\(prefix) does not match any open class")
                        continue
                    }
                    if name != fields[2] {
                        result.errors.append("\(prefix) does not match the open class \(name)")
                    }
                    if classes[name] != nil {
                        result.errors.append("\(label) line \(lineNumber): class \(name) appears more than once")
                    }
                    result.errors.append(contentsOf: problems(inSection: current).map { "\(label): class \(name): \($0)" })
                    classes[name] = current
                    duplicates.append(contentsOf: undeclaredDuplicates(in: current, declared: declaredDuplicates).map {
                        DuplicateRecord(className: name, key: $0.key, text: $0.text, declared: false)
                    })
                    currentClassName = nil
                    current = ParsedClass()
                    declaredDuplicates = []
                } else if RuntimeSnapshotFormat.headerKeywords.contains(fields[0].description) {
                    if currentClassName != nil || !classes.isEmpty {
                        result.errors.append("\(prefix) is a header line after the first class section")
                    } else if let problem = valueCountProblem(fields.map { $0.description }) {
                        result.errors.append("\(prefix) \(problem)")
                    } else {
                        if header[fields[0]] != nil {
                            result.errors.append("\(label) line \(lineNumber): a second \(fields[0]) line")
                        }
                        header[fields[0]] = fields.count == 2 ? fields[1] : Bytes("")
                    }
                } else if let open = currentClassName {
                    result.errors.append("\(prefix) is inside class \(open) but is not indented by two spaces")
                } else {
                    result.errors.append("\(prefix) is not a header line or the start of a class section")
                }
                continue
            }

            guard let className = currentClassName else {
                result.errors.append("\(prefix) is outside a class section")
                continue
            }
            if let problem = memberProblem(fields.map { $0.description }) {
                result.errors.append("\(prefix) \(problem)")
                continue
            }
            let kind = fields[0].description
            if kind == RuntimeSnapshotFormat.duplicateKeyword {
                duplicates.append(DuplicateRecord(className: className, key: Key(kind: fields[1], name: fields[2]),
                                                  text: Bytes(content).description, declared: true))
                declaredDuplicates.insert(Key(kind: fields[1], name: fields[2]))
                continue
            }
            if kind == RuntimeSnapshotFormat.ownershipConflictKeyword {
                result.ownershipConflicts.append("\(label): class \(className): \(Bytes(content))")
                continue
            }
            let key: Key
            let detail: Bytes
            if RuntimeSnapshotFormat.singleValueKeywords.contains(kind) {
                key = Key(kind: fields[0], name: Bytes(""))
                detail = fields.count == 2 ? fields[1] : Bytes("")
            } else {
                key = Key(kind: fields[0], name: fields[1])
                detail = Bytes(fields.dropFirst(2).map { $0.description }.joined(separator: " "))
            }
            current[key, default: []].append(detail)
        }
        for keyword in RuntimeSnapshotFormat.headerKeywords where header[Bytes(keyword)] == nil {
            result.errors.append("\(label): no \(keyword) line")
        }
        if let open = currentClassName {
            result.errors.append("\(label): class \(open) has no end line, so the snapshot is truncated")
        } else if classes.isEmpty {
            result.errors.append("\(label): the snapshot contains no classes")
        }
        return (header, classes, duplicates)
    }

    // Checks the fields of a line inside a class section against the grammar
    // of its kind, which is exactly what RuntimeSnapshot.swift writes:
    //   DUPLICATE <method or property kind> <name> count=<n of 2 or more>
    //   language <value>, superclass [<name>], image [<name>]
    //   protocol <name>
    //   ivar <name> types=[<encoding>]
    //   class-method +<selector> types=[<encoding>] [also-implemented-by=<+ or -><class>] [image=[<name>]]
    //   instance-method -<selector> types=[<encoding>] [also-implemented-by=-<class>] [image=[<name>]]
    //   class-property and instance-property: see propertyProblem
    // Returns what is wrong, or nil. Fields are already known to be nonempty
    // and canonically escaped.
    private static func memberProblem(_ fields: [String]) -> String? {
        let kind = fields[0]
        // After the kind and name, no key or flag appears twice, and no value
        // begins with =, which no name or encoding does.
        // The name is positional: the second field of a DUPLICATE line is
        // its kind and the third its name; elsewhere the second is the name.
        let positional = kind == RuntimeSnapshotFormat.duplicateKeyword || kind == RuntimeSnapshotFormat.ownershipConflictKeyword
        let keyed = positional ? fields.dropFirst(3) : fields.dropFirst(2)
        let keys = keyed.map { String($0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]) }
        if let repeated = keys.first(where: { key in keys.filter { $0 == key }.count > 1 }) {
            return "repeats the field \(repeated)"
        }
        if keyed.contains(where: { field in
            field.firstIndex(of: "=").map { field[field.index(after: $0)...].hasPrefix("=") } ?? false
        }) {
            return "has a value that begins with ="
        }
        switch kind {
        case RuntimeSnapshotFormat.duplicateKeyword:
            guard fields.count == 4 else {
                return "is a DUPLICATE line, which has exactly a kind, a name, and a count"
            }
            guard ["class-method", "instance-method", "class-property", "instance-property"].contains(fields[1]) else {
                return "names a kind of line that is never reported as a duplicate"
            }
            return isCount(fields[3]) ? nil : "has no count=<n> field with n a number of 2 or more"
        case RuntimeSnapshotFormat.ownershipConflictKeyword:
            guard fields.count == 3 else {
                return "is an OWNERSHIP-CONFLICT line, which has exactly a reason and a subject"
            }
            return RuntimeSnapshotFormat.ownershipConflictReasons.contains(fields[1]) ? nil : "gives a reason that is not one of \(RuntimeSnapshotFormat.ownershipConflictReasons.joined(separator: ", "))"
        case RuntimeSnapshotFormat.languageKeyword, RuntimeSnapshotFormat.superclassKeyword, RuntimeSnapshotFormat.imageKeyword:
            return valueCountProblem(fields)
        case RuntimeSnapshotFormat.arcFlagKeyword:
            if let problem = valueCountProblem(fields) {
                return problem
            }
            return RuntimeSnapshotFormat.arcFlags.contains(fields[1]) ? nil : "has a value that is not one of \(RuntimeSnapshotFormat.arcFlags.joined(separator: ", "))"
        case RuntimeSnapshotFormat.strongLayoutKeyword, RuntimeSnapshotFormat.weakLayoutKeyword:
            if let problem = valueCountProblem(fields) {
                return problem
            }
            return fields.count == 1 || isLayout(fields[1]) ? nil : "has a value that is not a layout: uppercase hexadecimal bytes ending in the only 00"
        case "protocol":
            return fields.count == 2 ? nil : "is a protocol line, which has only a name"
        case "ivar":
            return ivarProblem(fields)
        case "class-method", "instance-method":
            let sign = kind == "class-method" ? "+" : "-"
            guard fields.count >= 3, fields[1].hasPrefix(sign), fields[1].utf8.count > 1, fields[2].hasPrefix("types=") else {
                return "is a method line, which has \(sign)<selector> and then types=<encoding>"
            }
            var rest = fields.dropFirst(3)
            let alsoImplementedBy = "also-implemented-by="
            if let field = rest.first, field.hasPrefix(alsoImplementedBy) {
                // A sign, then a class name, which is never empty. Only a
                // class method can be also implemented by a class method.
                let value = field.dropFirst(alsoImplementedBy.count)
                let signs: [Character] = kind == "class-method" ? ["+", "-"] : ["-"]
                guard let first = value.first, signs.contains(first), value.count > 1 else {
                    return "has an also-implemented-by field that is not \(kind == "class-method" ? "+ or -" : "-") followed by a class name"
                }
                rest = rest.dropFirst()
            }
            // image= may have no value: the method is in no binary.
            if let field = rest.first, field.hasPrefix("image=") {
                rest = rest.dropFirst()
            }
            return rest.isEmpty ? nil : "has fields a method line does not have, or has them out of order: \(rest.joined(separator: " "))"
        case "class-property", "instance-property":
            return propertyProblem(fields.dropFirst(2))
        default:
            return "is not a kind of line a snapshot contains"
        }
    }

    // The fields of a property line after its kind and name, in this order:
    //   type=<T> ownership=<one of RuntimeSnapshotFormat.ownerships>
    //   atomic or nonatomic, then any of readonly, dynamic, optional in that
    //   order, then optionally getter=[<G>] and setter=[<S>], then
    //   ivar=[<V>] raw=[<attribute string>]
    // type, getter, setter, ivar, and raw may have no value, which is how the
    // writer writes an empty or absent one; that cannot be mistaken for a
    // value that is present.
    private static func propertyProblem(_ fields: ArraySlice<String>) -> String? {
        var rest = fields
        guard let type = rest.first, type.hasPrefix("type=") else {
            return "has no type= field where a property line has one"
        }
        rest = rest.dropFirst()
        guard let ownership = rest.first,
              ownership.hasPrefix("ownership="),
              RuntimeSnapshotFormat.ownerships.contains(String(ownership.dropFirst("ownership=".count))) else {
            return "has no ownership= field with one of \(RuntimeSnapshotFormat.ownerships.joined(separator: ", ")) where a property line has one"
        }
        rest = rest.dropFirst()
        guard let atomicity = rest.first, atomicity == "atomic" || atomicity == "nonatomic" else {
            return "has no atomic or nonatomic field where a property line has one"
        }
        rest = rest.dropFirst()
        for flag in ["readonly", "dynamic", "optional"] where rest.first == flag {
            rest = rest.dropFirst()
        }
        for key in ["getter", "setter"] {
            if let field = rest.first, field.hasPrefix(key + "=") {
                rest = rest.dropFirst()
            }
        }
        guard let ivar = rest.first, ivar.hasPrefix("ivar=") else {
            return "has no ivar= field where a property line has one, or has fields out of order"
        }
        rest = rest.dropFirst()
        guard let raw = rest.first, raw.hasPrefix("raw=") else {
            return "has no raw= field where a property line has one, or has fields out of order"
        }
        rest = rest.dropFirst()
        return rest.isEmpty ? nil : "has fields after raw=, which is always the last field of a property line"
    }

    // An ivar line: ivar <name> types=[<encoding>] ownership=<label>
    // layout=[<s, w and - with no trailing ->].
    private static func ivarProblem(_ fields: [String]) -> String? {
        let grammar = "is an ivar line, which has exactly a name, types=<encoding>, ownership=<label> and layout=<words>"
        guard fields.count == 5, fields[2].hasPrefix("types="), fields[3].hasPrefix("ownership="), fields[4].hasPrefix("layout=") else {
            return grammar
        }
        let label = String(fields[3].dropFirst("ownership=".count))
        guard RuntimeSnapshotFormat.ivarOwnerships.contains(label) else {
            return "has an ownership that is not one of \(RuntimeSnapshotFormat.ivarOwnerships.joined(separator: ", "))"
        }
        let words = fields[4].dropFirst("layout=".count)
        guard words.allSatisfy({ "sw-".contains($0) }), words.last != "-" else {
            return "has a layout that is not s, w and - with no trailing -"
        }
        return nil
    }

    // Whether field is a layout as the writer writes it: pairs of uppercase
    // hexadecimal digits, the last pair 00 and no other.
    private static func isLayout(_ field: String) -> Bool {
        let digits = Array(field)
        guard digits.count >= 2, digits.count % 2 == 0, digits.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            return false
        }
        let pairs = stride(from: 0, to: digits.count, by: 2).map { String(digits[$0..<($0 + 2)]) }
        return pairs.last == "00" && !pairs.dropLast().contains("00")
    }

    // What is wrong with the number of values on a line that has a keyword
    // and then at most one value, or nil. A keyword in
    // RuntimeSnapshotFormat.optionalValueKeywords may have no value; the
    // others must have one.
    private static func valueCountProblem(_ fields: [String]) -> String? {
        if fields.count > 2 {
            return "has more than one value"
        }
        if fields.count < 2 && !RuntimeSnapshotFormat.optionalValueKeywords.contains(fields[0]) {
            return "has no value, which a \(fields[0]) line always has"
        }
        return nil
    }

    // Whether field is count=<n>, n written in decimal without leading zeros
    // and at least 2.
    private static func isCount(_ field: String) -> Bool {
        let prefix = "count="
        guard field.hasPrefix(prefix) else {
            return false
        }
        let digits = field.dropFirst(prefix.count)
        guard let first = digits.first, first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits) else {
            return false
        }
        return n >= 2
    }

    // What is wrong with a class section's single-valued lines.
    private static func problems(inSection section: ParsedClass) -> [String] {
        var problems = [String]()
        for keyword in RuntimeSnapshotFormat.singleValueKeywords {
            let values = section[Key(kind: keyword, name: "")] ?? []
            if values.count != 1 {
                problems.append("\(values.count) \(keyword) lines, but a class section has exactly one")
            }
        }
        let languages = Set(RuntimeSnapshotFormat.languages.map { Bytes($0) })
        for value in section[Key(kind: RuntimeSnapshotFormat.languageKeyword, name: "")] ?? [] where !languages.contains(value) {
            problems.append("language \(value) is not one of \(RuntimeSnapshotFormat.languages.joined(separator: ", "))")
        }
        // The writer writes image= only when it differs from the class's
        // image, including image= with no value when the class's image line
        // has none.
        if let images = section[Key(kind: RuntimeSnapshotFormat.imageKeyword, name: "")], images.count == 1 {
            let classImage = Array("image=".utf8) + images[0].utf8
            let methodKinds = [Bytes("class-method"), Bytes("instance-method")]
            var offending = [String]()
            for (key, details) in section where methodKinds.contains(key.kind) {
                let matches = details.contains { detail in
                    detail.utf8.split(separator: UInt8(ascii: " ")).contains { Array($0) == classImage }
                }
                if matches {
                    offending.append("\(key.kind) \(key.name) has image= equal to the class's image, which the snapshot never writes")
                }
            }
            problems.append(contentsOf: offending.sorted(by: utf8Less))
        }
        return problems
    }
}

// MARK: - Comparing a class that moved from Objective-C to Swift

// The rule "identical in meaning" (docs/swift-migration/phase0.md section 9,
// owner queue R4): methods with their type encodings, protocols, superclass
// and the decoded property attributes must match; the systematic differences
// that the Swift compiler brings are classified, each with its reason; what
// the runtime cannot judge is listed as a check against the source; anything
// else fails. The classes of difference were found by experiment, by
// snapshotting an Objective-C class and its stage-one Swift port
// (ModernTests/RuntimeSnapshotFixtures/RuntimeSnapshotPortFixtures.*):
//
//   language objc -> swift                     the trigger for this comparison
//   ivar-arc-flag, strong- and weak-ivar-layout  classified: Swift writes no
//                                              layouts for its storage
//   ivar lines                                 every Objective-C ivar vanishes
//                                              (a check each: code that reaches
//                                              it by name breaks) and Swift's
//                                              storage appears, named after the
//                                              property without the underscore,
//                                              often with no type encoding
//                                              (classified)
//   -.cxx_destruct added or removed            classified: each compiler adds
//                                              it for its own storage
//   every initializer in the Swift class (init  a check each, kept or added:
//   family, and new-family class methods)      Swift lists -init for every
//                                              class, and stubs for inherited
//                                              designated initializers the
//                                              class does not override (such as
//                                              -initWithFrame: for an NSView
//                                              subclass); a stub traps, and the
//                                              runtime cannot tell it from a
//                                              real initializer. An added one
//                                              that overrides nothing fails
//   the class as a whole                       a check: the runtime does not
//                                              say which members are dynamic
//   +load, +initialize removed                 failure: Swift cannot implement
//                                              them; the port must move the work
//   -dealloc removed                           failure: Swift lists -dealloc only
//                                              when the class declares deinit
//   a pointer encoded ^v against a pointer to
//   an incomplete struct (^{_NSZone=}, an
//   opaque struct), or with the const
//   qualifier r on one side (CFString)         classified; any other pointee
//                                              change fails
//   any other method added, removed, or with
//   another encoding, override or image        failure
//   property attribute string (raw=) and
//   backing ivar (ivar=)                       classified: Swift orders the
//                                              codes differently and names its
//                                              storage without the underscore,
//                                              or has none for a computed
//                                              property
//   getter=/setter= present before, absent after  classified when the
//                                              method it names is still there
//                                              (Swift writes no G or S code)
//   weak -> weak-or-unowned                    a check: the runtime cannot tell
//                                              weak from unowned
//   ownership unrecorded on either side        a check
//   atomic -> nonatomic                        a check, one per property: every
//                                              Swift property is nonatomic, and
//                                              the prescribed port stores the
//                                              value in a MutableAtomicObject
//                                              whose lock the runtime cannot see
//                                              (concurrency.md section 3); a
//                                              failure when anything else about
//                                              the property fails
//   nonatomic -> atomic                        failure: a Swift property is never
//                                              atomic
//   any other property attribute change, or a
//   property added or removed                  failure, except the NSObject
//                                              protocol's properties and
//                                              @optional protocol properties,
//                                              which clang copies into the
//                                              class's list and Swift does not
//                                              (classified), and an added
//                                              readonly property whose getter
//                                              is unchanged (classified; see
//                                              swiftOverridePropertyReason)
//   protocols, superclass, image               must match; a protocol listed a
//                                              different number of times is
//                                              classified (clang lists it once
//                                              per adopting list)
//   the class's runtime name                   must match: a renamed class is a
//                                              class only in one snapshot
extension RuntimeSnapshotComparison {
    private static let nsObjectProtocolProperties = ["hash", "superclass", "description", "debugDescription"]

    private static func compareAcrossLanguages(className: Bytes,
                                               before: ParsedClass,
                                               after: ParsedClass,
                                               result: inout RuntimeSnapshotComparisonResult) {
        result.crossLanguageClasses.append(className.description)
        let prefix = "class \(className): "
        func fail(_ text: String) {
            result.differences.append(prefix + text)
        }
        func classify(_ text: String, _ reason: String) {
            result.classified.append(prefix + text + "\n      expected because: " + reason)
        }
        func check(_ text: String, _ what: String) {
            result.checks.append(prefix + text + "\n      check: " + what)
        }
        let keys = Set(before.keys).union(after.keys).sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            return lhs.name < rhs.name
        }
        check("Swift callers bypass key-value observing and swizzling for members not marked dynamic",
              "the runtime does not record which Swift members are dynamic; Swift code calls the others directly, not through objc_msgSend, so an observer added with key-value observing or a method swizzled or replaced at run time is skipped for those calls; check whether this class is observed or swizzled, and mark those members @objc dynamic (translation-rules.md section 7)")
        let afterInstanceMethods = Set(after.keys.filter { $0.kind == Bytes("instance-method") }.map { $0.name })
        let afterClassMethods = Set(after.keys.filter { $0.kind == Bytes("class-method") }.map { $0.name })
        for key in keys {
            let b = (before[key] ?? []).sorted()
            let a = (after[key] ?? []).sorted()
            if b == a {
                continue
            }
            let kind = key.kind.description
            let name = key.name.description
            let what = describe(key)
            switch kind {
            case RuntimeSnapshotFormat.languageKeyword:
                continue
            case RuntimeSnapshotFormat.arcFlagKeyword, RuntimeSnapshotFormat.strongLayoutKeyword, RuntimeSnapshotFormat.weakLayoutKeyword:
                classify("changed \(what) from \(describeValue(b.first ?? Bytes(""))) to \(describeValue(a.first ?? Bytes("")))",
                         "the ivar layouts and ARC flag describe Objective-C ivars; Swift writes no layouts for its storage, whose ownership comes from the Swift declarations")
            case "protocol":
                if !b.isEmpty && !a.isEmpty {
                    classify("protocol \(name) listed \(b.count) times before and \(a.count) after",
                             "clang lists a protocol once for each list that adopts it (the class and each category or extension)")
                } else {
                    fail("\(b.isEmpty ? "added" : "removed") protocol \(name)")
                }
            case "ivar":
                for detail in b {
                    check("Objective-C ivar \(name) (\(detail)) is gone",
                          "anything that reaches it by name breaks: class_getInstanceVariable, object_getIvar or ivar_getOffset with this name, key-value coding falling back to the ivar (accessInstanceVariablesDirectly), a xib outlet connected to the ivar, and obj->\(name) in Objective-C; Swift's storage is named differently, usually after the property without the underscore")
                }
                for detail in a {
                    classify("Swift storage \(name) (\(detail))",
                             "a Swift class lists its stored properties as ivars named after the property, often with no Objective-C type encoding; their ownership comes from the Swift declaration")
                }
            case "class-method", "instance-method":
                compareMethodAcrossLanguages(name: name, kind: kind, before: b, after: a, fail: fail, classify: classify, check: check)
            case "class-property", "instance-property":
                if b.isEmpty, a.count == 1,
                   let reason = swiftOverridePropertyReason(key: key, detail: a[0], before: before, after: after) {
                    classify("added \(what) \(a[0])", reason)
                    continue
                }
                let methods = kind == "class-property" ? afterClassMethods : afterInstanceMethods
                let sign = kind == "class-property" ? "+" : "-"
                compareProperty(name: name, kind: kind, before: b, after: a,
                                hasMethod: { methods.contains(Bytes(sign + $0)) },
                                fail: fail, classify: classify, check: check)
            default:
                // superclass, image, and any other line must match.
                if b.count == 1 && a.count == 1 {
                    fail("changed \(what)\n      before: \(describeValue(b[0]))\n      after:  \(describeValue(a[0]))")
                } else {
                    fail("changed \(what)\n      before: \(joined(b, " | "))\n      after:  \(joined(a, " | "))")
                }
            }
        }
        // Every initializer of the Swift class, kept or added: when the
        // class does not declare or inherit it, Swift's version is a stub
        // that traps, and nothing in the runtime tells a stub from a real
        // implementation.
        for key in after.keys.sorted(by: { ($0.kind, $0.name) < ($1.kind, $1.name) })
            where (key.kind == Bytes("instance-method") || key.kind == Bytes("class-method")) && isInitializer(key.name.description) {
            check("initializer \(describe(key)) is in the Swift class",
                  "it may be a stub that Swift synthesizes for an inherited designated initializer the class does not override, which traps (“Use of unimplemented initializer”) when called, so Objective-C code that calls it (for -init, also +new and [[X alloc] init]) crashes; check that the Swift class declares this initializer or inherits it (Swift inherits its superclass's designated initializers only when the class declares none of its own and every stored property has a default)")
        }
    }

    // Why a property listed on a Swift class only in the after snapshot is
    // expected, or nil when it is not. Swift can override an inherited getter
    // that the SDK imports as a property (-[NSWindow canBecomeKeyWindow])
    // only with `override var`, and then lists a property on the class that
    // the Objective-C override, a method, did not. It is expected when the
    // property is readonly with no custom setter and its getter is an
    // existing method of the class, with the same encoding before and after,
    // that returns the property's type. Whether a superclass declares the
    // property is not checked (the snapshot may not hold the superclass),
    // nor is atomicity (the SDK's declaration is atomic, Swift's is not).
    // The orchestrator's decision of 2026-11-26, after review of the
    // iTermFocusablePanel port; open to the owner.
    private static func swiftOverridePropertyReason(key: Key,
                                                    detail: Bytes,
                                                    before: ParsedClass,
                                                    after: ParsedClass) -> String? {
        let languageKey = Key(kind: RuntimeSnapshotFormat.languageKeyword, name: "")
        guard after[languageKey] == [Bytes(RuntimeSnapshotFormat.swiftLanguage)] else {
            return nil
        }
        let attributes = fields(of: detail)
        guard attributes["readonly"] != nil, attributes["setter"] == nil, let type = attributes["type"] else {
            return nil
        }
        let getter = attributes["getter"].flatMap { $0.isEmpty ? nil : $0 } ?? key.name.description
        let methodKind: String
        let sign: String
        switch key.kind.description {
        case "instance-property":
            methodKind = "instance-method"
            sign = "-"
        case "class-property":
            methodKind = "class-method"
            sign = "+"
        default:
            return nil
        }
        let methodKey = Key(kind: methodKind, name: sign + getter)
        guard let beforeMethods = before[methodKey], beforeMethods.count == 1,
              let afterMethods = after[methodKey], afterMethods.count == 1,
              let beforeTypes = fields(of: beforeMethods[0])["types"],
              let afterTypes = fields(of: afterMethods[0])["types"],
              beforeTypes == afterTypes,
              returnEncoding(afterTypes) == propertyTypeAsReturnEncoding(type) else {
            return nil
        }
        return "a readonly property listed over an existing getter (for example a Swift override var of a getter the SDK imports as a property): Swift overrides a getter that the SDK imports as a property only with `override var`, which lists a readonly property on the class; the getter \(sign)\(getter) is the same method, with the same encoding, before and after; key-value coding finds the getter by name, there is no setter for key-value observing to hook, and atomicity is not compared because nothing is synthesized (the orchestrator's decision of 2026-11-26, open to the owner)"
    }

    // The return type at the start of a method's type encoding: everything
    // before the first digit outside a struct, union, array or quoted name.
    private static func returnEncoding(_ types: String) -> String {
        var depth = 0
        var quoted = false
        var end = types.endIndex
        for index in types.indices {
            let c = types[index]
            if c == "\"" {
                quoted.toggle()
            } else if quoted {
                continue
            } else if c == "{" || c == "(" || c == "[" {
                depth += 1
            } else if c == "}" || c == ")" || c == "]" {
                depth -= 1
            } else if depth == 0 && c.isASCII && c.isNumber {
                end = index
                break
            }
        }
        return String(types[..<end])
    }

    // A property's type as a method's return would encode it: a method
    // encoding writes an object as plain @, without the class name.
    private static func propertyTypeAsReturnEncoding(_ type: String) -> String {
        return type.hasPrefix("@\"") ? "@" : type
    }

    private static func compareMethodAcrossLanguages(name: String,
                                                     kind: String,
                                                     before: [Bytes],
                                                     after: [Bytes],
                                                     fail: (String) -> Void,
                                                     classify: (String, String) -> Void,
                                                     check: (String, String) -> Void) {
        let what = "\(kind) \(name)"
        if after.isEmpty {
            switch name {
            case "-.cxx_destruct":
                classify("removed \(what)", "clang adds .cxx_destruct to destroy ARC and C++ ivars; Swift destroys its own storage")
            case "+load", "+initialize":
                fail("removed \(what): a Swift class cannot implement \(name) (Swift rejects it), so the port must do its work elsewhere, explicitly, and this difference needs the owner")
            case "-dealloc":
                fail("removed \(what): Swift lists -dealloc only for a class that declares deinit, so the port has none; this fails, rather than asking for a check, until there is a way to record that nothing -dealloc did is still needed")
            default:
                fail("removed \(what) \(joined(before, " | "))")
            }
            return
        }
        if before.isEmpty {
            switch name {
            case "-.cxx_destruct":
                classify("added \(what)", "Swift adds .cxx_destruct to destroy its stored properties")
            case _ where isInitializer(name) && after.allSatisfy({ fields(of: $0)["also-implemented-by"] != nil }):
                // An initializer that overrides a superclass's, such as the
                // -init Swift lists for every class or the -initWithFrame:
                // it lists for an NSView subclass: checked below, with every
                // initializer of the Swift class.
                break
            default:
                fail("added \(what) \(joined(after, " | ")): Swift exposes a selector the Objective-C class did not have (for example the setter of an @objc private(set) var)")
            }
            return
        }
        guard before.count == 1, after.count == 1 else {
            fail("changed \(what)\n      before: \(joined(before, " | "))\n      after:  \(joined(after, " | "))")
            return
        }
        let b = fields(of: before[0])
        let a = fields(of: after[0])
        let rest = { (f: [String: String]) in f.filter { $0.key != "types" } }
        if rest(b) == rest(a), let bt = b["types"], let at = a["types"], encodingsDifferOnlyInPointees(bt, at) {
            classify("changed \(what) types from \(bt) to \(at)",
                     "the encodings differ only where Swift writes ^v for a pointer to an incomplete struct (NSZone *, an OpaquePointer), or adds the const qualifier r (CFString); the pointers have the same size and pointee, and are passed identically")
            return
        }
        fail("changed \(what)\n      before: \(before[0])\n      after:  \(after[0])")
    }

    // The fields of a method line's details or a property line's details:
    // key=value fields by key, and bare flags with an empty value.
    private static func fields(of detail: Bytes) -> [String: String] {
        var result = [String: String]()
        for field in detail.description.split(separator: " ") {
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            result[String(parts[0])] = parts.count == 2 ? String(parts[1]) : ""
        }
        return result
    }

    private static func compareProperty(name: String,
                                        kind: String,
                                        before: [Bytes],
                                        after: [Bytes],
                                        hasMethod: (String) -> Bool,
                                        fail: (String) -> Void,
                                        classify: (String, String) -> Void,
                                        check: (String, String) -> Void) {
        let what = "\(kind) \(name)"
        if after.isEmpty {
            let attributes = fields(of: before[0])
            if kind == "instance-property" && nsObjectProtocolProperties.contains(name) && attributes["readonly"] != nil {
                classify("removed \(what)",
                         "clang copies the NSObject protocol's properties into the class's list for each protocol list derived from NSObject; Swift does not; the accessors are NSObject's and are unchanged")
            } else if attributes["optional"] != nil {
                classify("removed \(what)",
                         "an @optional property of an adopted protocol, which clang copies into the class's list and Swift does not; its accessors, if the class has any, are compared as methods")
            } else {
                fail("removed \(what) \(joined(before, " | "))")
            }
            return
        }
        if before.isEmpty {
            fail("added \(what) \(joined(after, " | "))")
            return
        }
        if Set(before) == Set(after) {
            classify("\(what) listed \(before.count) times before and \(after.count) after",
                     "clang lists a protocol's properties once for each list that adopts the protocol")
            return
        }
        guard Set(before).count == 1, Set(after).count == 1 else {
            fail("changed \(what)\n      before: \(joined(before, " | "))\n      after:  \(joined(after, " | "))")
            return
        }
        var b = fields(of: before[0])
        var a = fields(of: after[0])
        var problems = [String]()
        var expected = [String]()
        var checks = [String]()
        if b["type"] != a["type"] {
            problems.append("type \(b["type"] ?? "") became \(a["type"] ?? "")")
        }
        let bAtomic = b["atomic"] != nil
        let aAtomic = a["atomic"] != nil
        // Every Swift property is nonatomic. The port of an atomic property
        // that is relied upon stores it in a MutableAtomicObject, whose lock
        // the runtime cannot see, so the change is a check unless something
        // else about the property fails (the failure then names it too).
        var lostAtomicity: String?
        if bAtomic && !aAtomic {
            lostAtomicity = "atomic became nonatomic"
            checks.append("property \(name) was atomic: Swift properties are not; check that the port stores it in a MutableAtomicObject and reads and writes it through its value (concurrency.md section 3), or that the dossier shows it was atomic by accident")
        } else if bAtomic != aAtomic {
            problems.append("nonatomic became atomic, which a Swift property never is")
        }
        for flag in ["readonly", "dynamic", "optional"] where (b[flag] != nil) != (a[flag] != nil) {
            problems.append(b[flag] != nil ? "is no longer \(flag)" : "became \(flag)")
        }
        let bOwnership = b["ownership"] ?? ""
        let aOwnership = a["ownership"] ?? ""
        if bOwnership != aOwnership {
            if bOwnership == "weak" && aOwnership == "weak-or-unowned" {
                checks.append("weak became weak-or-unowned: the runtime cannot tell Swift's weak from unowned or unowned(unsafe); check that the Swift declaration is weak")
            } else if bOwnership == "unrecorded" || aOwnership == "unrecorded" {
                checks.append("ownership \(bOwnership) became \(aOwnership): the runtime does not record one of them; check the declarations agree")
            } else {
                problems.append("ownership \(bOwnership) became \(aOwnership)")
            }
        }
        for accessor in ["getter", "setter"] {
            let bName = b[accessor]
            let aName = a[accessor]
            if bName == aName {
                continue
            }
            if let bName, aName == nil, !bName.isEmpty, hasMethod(bName) {
                expected.append("\(accessor)=\(bName) is not written: Swift writes no G or S code for a custom accessor name, and the method \(bName) is there")
            } else {
                problems.append("\(accessor) \(bName ?? "(none)") became \(aName ?? "(none)")")
            }
        }
        if b["ivar"] != a["ivar"] {
            expected.append("backing ivar \(b["ivar"].map { $0.isEmpty ? "(none)" : $0 } ?? "(none)") became \(a["ivar"].map { $0.isEmpty ? "(none)" : $0 } ?? "(none)"): Swift names its storage without the underscore, and has none an Objective-C ivar list can name for a computed or closure-typed property")
        }
        for key in ["type", "ownership", "atomic", "nonatomic", "readonly", "dynamic", "optional", "getter", "setter", "ivar", "raw"] {
            b[key] = nil
            a[key] = nil
        }
        if b != a {
            problems.append("other fields differ")
        }
        if problems.isEmpty && before[0] != after[0] {
            if lostAtomicity != nil {
                expected.append("the attribute string differs (raw=): it gains N, for nonatomic, which is listed as a check, and Swift writes the attribute codes in another order")
            } else {
                expected.append("the attribute string differs (raw=): Swift writes the attribute codes in another order")
            }
        }
        if !problems.isEmpty {
            if let lostAtomicity {
                problems.append(lostAtomicity)
            }
            fail("changed \(what): \(problems.joined(separator: "; "))\n      before: \(before[0])\n      after:  \(after[0])")
            return
        }
        for text in checks {
            check("changed \(what)\n      before: \(before[0])\n      after:  \(after[0])", text)
        }
        if !expected.isEmpty {
            classify("changed \(what)\n      before: \(before[0])\n      after:  \(after[0])", expected.joined(separator: "; "))
        }
    }

    // Whether a selector, with its sign, is in the init family (an instance
    // method: init followed by nothing, a colon, or an uppercase letter) or
    // the new family (a class method, the same rule with new), as the
    // Objective-C method-family rule defines them.
    static func isInitializer(_ signedSelector: String) -> Bool {
        let family: String
        if signedSelector.hasPrefix("-") {
            family = "init"
        } else if signedSelector.hasPrefix("+") {
            family = "new"
        } else {
            return false
        }
        let selector = signedSelector.dropFirst()
        guard selector.hasPrefix(family) else {
            return false
        }
        guard let next = selector.dropFirst(family.count).first else {
            return true
        }
        return next == ":" || next.isUppercase
    }

    // Whether two method type encodings are the same apart from pointers that
    // pointerTypesAreEquivalent accepts, component by component (a type and
    // its frame offset).
    static func encodingsDifferOnlyInPointees(_ lhs: String, _ rhs: String) -> Bool {
        guard let l = encodingComponents(lhs), let r = encodingComponents(rhs), l.count == r.count, lhs != rhs else {
            return false
        }
        for (x, y) in zip(l, r) where x != y {
            guard x.offset == y.offset, pointerTypesAreEquivalent(x.type, y.type) else {
                return false
            }
        }
        return true
    }

    // The pointer encodings that swiftc writes differently from clang for the
    // same C type, found by compiling one method per pointer type in each
    // language: ^v for a pointer to an incomplete struct (NSZone *, which
    // Swift imports as NSZone?, and a pointer to an opaque struct, which it
    // imports as OpaquePointer), where clang writes ^{Name=}; and r^{...}
    // for a CF type such as CFString, where clang writes ^{...} (the const
    // qualifier). Pointers to scalars, objects, selectors, complete structs
    // and char * are written alike, so any other difference (a pointee of
    // another type or size, ^@ against ^v, another depth) is not accepted.
    static func pointerTypesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs {
            return true
        }
        let l = lhs.hasPrefix("r") ? String(lhs.dropFirst()) : lhs
        let r = rhs.hasPrefix("r") ? String(rhs.dropFirst()) : rhs
        if l == r {
            return l.hasPrefix("^")
        }
        guard l.hasPrefix("^"), r.hasPrefix("^") else {
            return false
        }
        let lp = String(l.dropFirst())
        let rp = String(r.dropFirst())
        if (lp == "v" && isIncompleteStruct(rp)) || (rp == "v" && isIncompleteStruct(lp)) {
            return true
        }
        return lp.hasPrefix("^") && rp.hasPrefix("^") && pointerTypesAreEquivalent(lp, rp)
    }

    // A struct encoding with no fields, {Name=}: an incomplete struct.
    private static func isIncompleteStruct(_ type: String) -> Bool {
        return type.hasPrefix("{") && type.hasSuffix("=}") && type.filter { $0 == "{" }.count == 1
    }

    // Splits a method type encoding into its types, each with its frame
    // offset (the digits after it), or returns nil for an encoding it cannot
    // read. Qualifiers (r, n, N, o, O, R, V) stay with their type.
    static func encodingComponents(_ encoding: String) -> [(type: String, offset: String)]? {
        let chars = Array(encoding)
        var i = 0
        func skipType() -> Bool {
            while i < chars.count, "rnNoORVA".contains(chars[i]) {
                i += 1
            }
            guard i < chars.count else {
                return false
            }
            let c = chars[i]
            i += 1
            switch c {
            case "^":
                return skipType()
            case "@":
                if i < chars.count, chars[i] == "?" {
                    i += 1
                } else if i < chars.count, chars[i] == "\"" {
                    guard let close = chars[(i + 1)...].firstIndex(of: "\"") else {
                        return false
                    }
                    i = close + 1
                }
                return true
            case "{", "(", "[":
                let open = c
                let close: Character = c == "{" ? "}" : (c == "(" ? ")" : "]")
                var depth = 1
                var quoted = false
                while i < chars.count, depth > 0 {
                    if quoted {
                        quoted = chars[i] != "\""
                    } else if chars[i] == "\"" {
                        quoted = true
                    } else if chars[i] == open {
                        depth += 1
                    } else if chars[i] == close {
                        depth -= 1
                    }
                    i += 1
                }
                return depth == 0
            case "b":
                while i < chars.count, chars[i].isNumber {
                    i += 1
                }
                return true
            default:
                return true
            }
        }
        var result = [(type: String, offset: String)]()
        while i < chars.count {
            let start = i
            guard skipType() else {
                return nil
            }
            let type = String(chars[start..<i])
            let offsetStart = i
            while i < chars.count, chars[i].isNumber {
                i += 1
            }
            result.append((type, String(chars[offsetStart..<i])))
        }
        return result
    }
}
