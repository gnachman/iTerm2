//
//  RuntimeSnapshotComparison.swift
//  ModernTests
//
//  Compares two Objective-C runtime snapshots produced by RuntimeSnapshot.swift
//  (docs/swift-migration/phase0.md section 9). A port must leave the runtime
//  surface of a class unchanged, so any difference that is not on the
//  allow-list below fails the comparison, and so does any duplicate selector in
//  either snapshot (counted from the method lines themselves, not only from
//  DUPLICATE lines).
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
    static let headerLine = "# Objective-C runtime snapshot, format 2"

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
    static let singleValueKeywords = [languageKeyword, superclassKeyword, imageKeyword]

    // The keywords of header and class-section lines that are written with
    // no value when theirs is absent. The others always have one.
    static let optionalValueKeywords = [buildConfigurationKeyword, buildVariantKeyword, superclassKeyword, imageKeyword]

    // Lines of the form "<kind> <name> [<details>]", any number of each.
    static let memberKinds = ["protocol", "ivar", "class-method", "instance-method", "class-property", "instance-property"]

    // Prefix of the line that flags a selector or property appearing more than
    // once in a class's own list.
    static let duplicateKeyword = "DUPLICATE"

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
        "- whether an ivar is strong, weak, or unretained",
        "- the type of an ivar whose encoding the runtime leaves unknown or empty",
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
    // Duplicate-selector lines found in either snapshot. Any entry fails the
    // comparison.
    var duplicates: [String] = []
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

    var passed: Bool {
        return duplicates.isEmpty && differences.isEmpty && errors.isEmpty && languageChanges.isEmpty && unknownLanguages.isEmpty && invalidLanguages.isEmpty
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
        if !differences.isEmpty {
            lines.append("DIFFERENCES:")
            lines.append(contentsOf: differences.map { "  " + $0 })
        }
        if !unclassified.isEmpty {
            lines.append("UNCLASSIFIED DIFFERENCES (in classes that get no verdict):")
            lines.append(contentsOf: unclassified.map { "  " + $0 })
        }
        if !allowed.isEmpty {
            lines.append("Allowed differences:")
            lines.append(contentsOf: allowed.map { "  " + $0 })
        }
        if !noVerdict.isEmpty {
            lines.append("NO VERDICT for some classes, so the comparison does not pass.")
        }
        if !errors.isEmpty {
            lines.append("ERROR: the inputs cannot be compared.")
        } else if !duplicates.isEmpty || !differences.isEmpty {
            lines.append("FAIL: the snapshots do not match.")
        } else if passed {
            lines.append("PASS: the snapshots match.")
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
        let (beforeHeader, beforeClasses) = parse(before, label: "before", result: &result)
        let (afterHeader, afterClasses) = parse(after, label: "after", result: &result)

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
    private static func undeclaredDuplicates(in parsed: ParsedClass, declared: Set<Key>) -> [String] {
        var result = [String]()
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
                result.append("\(key.kind) \(key.name) appears \(details.count) times with no DUPLICATE line")
            }
        }
        return result.sorted(by: utf8Less)
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
                              result: inout RuntimeSnapshotComparisonResult) -> (header: [Bytes: Bytes], classes: [Bytes: ParsedClass]) {
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
            return ([:], [:])
        }
        lines.removeLast()
        guard Bytes(lines[0]) == Bytes(RuntimeSnapshotFormat.headerLine) else {
            result.errors.append("\(label): the first line is not “\(RuntimeSnapshotFormat.headerLine)”, so this is not a runtime snapshot in a known format")
            return ([:], [:])
        }

        var header = [Bytes: Bytes]()
        var classes = [Bytes: ParsedClass]()
        var currentClassName: Bytes?
        var current = ParsedClass()
        // Keys named by the open class's DUPLICATE lines.
        var declaredDuplicates = Set<Key>()

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
                    result.duplicates.append(contentsOf: undeclaredDuplicates(in: current, declared: declaredDuplicates).map {
                        "\(label): class \(name): \($0)"
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
                result.duplicates.append("\(label): class \(className): \(Bytes(content))")
                declaredDuplicates.insert(Key(kind: fields[1], name: fields[2]))
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
        return (header, classes)
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
        let keyed = kind == RuntimeSnapshotFormat.duplicateKeyword ? fields.dropFirst(3) : fields.dropFirst(2)
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
        case RuntimeSnapshotFormat.languageKeyword, RuntimeSnapshotFormat.superclassKeyword, RuntimeSnapshotFormat.imageKeyword:
            return valueCountProblem(fields)
        case "protocol":
            return fields.count == 2 ? nil : "is a protocol line, which has only a name"
        case "ivar":
            return fields.count == 3 && fields[2].hasPrefix("types=") ? nil : "is an ivar line, which has exactly a name and types=<encoding>"
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
