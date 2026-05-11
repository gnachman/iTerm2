import Foundation

/// Token for an optional path like `name?` or `user.path?` (no space before `?`).
/// The `identifier` property contains the path WITHOUT the trailing `?`.
@objc(iTermOptionalPathToken)
class OptionalPathToken: CPToken {
    @objc let identifier: String

    @objc(tokenWithIdentifier:)
    static func token(identifier: String) -> OptionalPathToken {
        return OptionalPathToken(identifier: identifier)
    }

    init(identifier: String) {
        self.identifier = identifier
        super.init()
    }

    required init?(coder: NSCoder) {
        self.identifier = coder.decodeObject(forKey: "identifier") as? String ?? ""
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(identifier, forKey: "identifier")
    }

    override var name: String! { "OptionalPath" }
}

private let keywords: Set<String> = ["true", "false", "null"]

/// Recognizes identifier paths immediately followed by `?` (no whitespace).
/// e.g., `name?`, `user.path?`, `foo.bar.baz?`
/// Does NOT match `name ?` (space before `?`) — that stays as Identifier + `?`.
@objc(iTermOptionalPathRecognizer)
class OptionalPathRecognizer: NSObject, CPTokenRecogniser {
    @objc static func recognizer() -> OptionalPathRecognizer {
        return OptionalPathRecognizer()
    }

    // CoreParse's tokenPosition is in UTF-16 code units (matches NSString length);
    // index in UTF-16 so non-BMP characters (e.g. emoji) earlier in the input
    // can't push the offset past the Unicode scalar count and trap.
    func recogniseToken(in string: String!,
                        currentTokenPosition tokenPosition: UnsafeMutablePointer<UInt>!) -> CPToken? {
        let nsString = string as NSString
        let length = nsString.length
        var pos = Int(tokenPosition.pointee)
        guard pos < length else { return nil }

        guard nsString.character(at: pos).isIdentifierStart else { return nil }

        let startPos = pos
        pos += 1
        while pos < length, nsString.character(at: pos).isIdentifierBody {
            pos += 1
        }

        guard pos < length, nsString.character(at: pos) == questionMark else { return nil }

        let path = nsString.substring(with: NSRange(location: startPos, length: pos - startPos))

        guard !keywords.contains(path) else { return nil }
        guard !path.hasSuffix(".") else { return nil }

        tokenPosition.pointee = UInt(pos + 1)
        return OptionalPathToken(identifier: path)
    }

    func encode(with coder: NSCoder) {}

    required init?(coder: NSCoder) {
        super.init()
    }

    override init() {
        super.init()
    }
}

private let questionMark = unichar(UnicodeScalar("?").value)

private extension unichar {
    private static func ascii(_ scalar: Unicode.Scalar) -> unichar { unichar(scalar.value) }

    var isIdentifierStart: Bool {
        (self >= unichar.ascii("a") && self <= unichar.ascii("z")) ||
        (self >= unichar.ascii("A") && self <= unichar.ascii("Z")) ||
        self == unichar.ascii("_")
    }

    var isIdentifierBody: Bool {
        isIdentifierStart ||
        (self >= unichar.ascii("0") && self <= unichar.ascii("9")) ||
        self == unichar.ascii(".")
    }
}
