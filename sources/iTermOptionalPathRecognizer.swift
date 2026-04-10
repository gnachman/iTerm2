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

    func recogniseToken(in string: String!,
                        currentTokenPosition tokenPosition: UnsafeMutablePointer<UInt>!) -> CPToken? {
        let scalars = string.unicodeScalars
        let start = scalars.index(scalars.startIndex, offsetBy: Int(tokenPosition.pointee))

        guard start < scalars.endIndex else { return nil }

        let first = scalars[start]
        guard first.isIdentifierStart else { return nil }

        var pos = scalars.index(after: start)
        while pos < scalars.endIndex, scalars[pos].isIdentifierBody {
            pos = scalars.index(after: pos)
        }

        guard pos < scalars.endIndex, scalars[pos] == "?" else { return nil }

        let path = String(scalars[start..<pos])

        guard !keywords.contains(path) else { return nil }
        guard !path.hasSuffix(".") else { return nil }

        let end = scalars.index(after: pos)
        tokenPosition.pointee = UInt(scalars.distance(from: scalars.startIndex, to: end))
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

private extension Unicode.Scalar {
    var isIdentifierStart: Bool {
        (self >= "a" && self <= "z") ||
        (self >= "A" && self <= "Z") ||
        self == "_"
    }

    var isIdentifierBody: Bool {
        isIdentifierStart ||
        (self >= "0" && self <= "9") ||
        self == "."
    }
}
