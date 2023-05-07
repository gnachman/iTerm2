//
//  SecureUserDefaults.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/7/22.
//

import Foundation

protocol SecureUserDefaultStringTranscodable {
    var sudString: String { get }
    init?(sudString: String) throws
}

enum SecureUserDefaultValueError: Error {
    case decodingFailed
}

struct SecureUserDefaultValue<T: SecureUserDefaultStringTranscodable> {
    let value: T
    var encodedString: String {
        return (value.sudString.data(using: .utf8)! as NSData).it_hexEncoded()
    }
    init(value: T) {
        self.value = value
    }
    init?(sudString string: String) throws {
        guard let data = (string as NSString).dataFromHexValues() else {
            return nil
        }
        guard let decodedString = String(data: data, encoding: .utf8) else {
            return nil
        }
        guard let decoded = try T(sudString: decodedString) else {
            return nil
        }
        value = decoded
    }
}

extension Bool: SecureUserDefaultStringTranscodable {
    var sudString: String {
        return String(self)
    }
    init?(sudString string: String) throws {
        guard let b = Bool(string) else {
            throw SecureUserDefaultValueError.decodingFailed
        }
        self = b
    }
}

protocol SerializableUserDefault {
    var key: String { get }
    func encode(to: inout [String: String])
    func setFromSerialized(value: String)
}

struct SecureUserDefaults {
    static var instance = SecureUserDefaults()

    mutating func serializeAll() -> [String: String] {
        var result = [String: String]()
        for serializable in serializables() {
            serializable.encode(to: &result)
        }
        return result
    }

    mutating func deserializeAll(dict: [String: String]) {
        for serializable in serializables() {
            if let json = dict[serializable.key] {
                serializable.setFromSerialized(value: json)
            }
        }
    }

    lazy var allowPaste = { SecureUserDefault<Bool>("AllowPaste", defaultValue: false) }()
    lazy var requireAuthToOpenPasswordmanager = { SecureUserDefault<Bool>("RequireAuthenticationToOpenPasswordManager", defaultValue: true) }()
    private mutating func serializables() -> [any SerializableUserDefault] {
        [allowPaste, requireAuthToOpenPasswordmanager]
    }
}

@objc
class iTermSecureUserDefaults: NSObject {
    @objc static let instance = iTermSecureUserDefaults()
    @objc var requireAuthToOpenPasswordManager: Bool {
        get {
            return SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.value
        }
        set {
            try? SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.set(newValue)
        }
    }
}

// Secure user defaults are a way of saving user preferences that are hard to tamper with.
// Like UserDefaults, it is a database of key-value pairs.
// Unlike UserDefaults, the user must authenticate to set a value.
// Values can be restored to their default state without authentication, so they must fail safe.
// The implementation is to create a file owned by root that holds the setting.
// The file's contents are:
// <encoded path> <sha of key>\n<value>
// Where:
//   * <encoded path> is the path to the file as hex-encoded UTF-8.
//   * <sha of key> is the hex-encoded SHA-256 of the user defaults key. The key is the same as the filename minus directory and extension.
//   * <value> is a hex-encoded UTF8 string representation of the value (e.g., "true" or "false" for a boolean). It is hex encoded to avoid injection bugs during writing.
class SecureUserDefault<T: SecureUserDefaultStringTranscodable & Codable & Equatable> {
    let key: String
    let defaultValue: T

    enum SecureUserDefaultError: Error {
        case noAppSupportDirectory
        case badMagic
        case scriptError(String?)
    }

    init(_ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var value: T {
        if let value = try? get() {
            return value
        }
        return defaultValue
    }

    var url: URL? {
        return try? Self.path(key)
    }

    func get() throws -> T {
        return try Self.load(key) ?? defaultValue
    }

    func set(_ newValue: T?) throws {
        if let value = newValue {
            try Self.store(key, value: value)
        } else {
            try Self.delete(key)
        }
    }

    private static func path(_ key: String) throws -> URL {
        precondition(key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil)
        guard let appSupportString = FileManager.default.applicationSupportDirectory() else {
            throw SecureUserDefaultError.noAppSupportDirectory
        }
        let appSupport = URL(fileURLWithPath: appSupportString)
        return appSupport.appendingPathComponent(key).appendingPathExtension("secureSetting")
    }

    static func magic(_ key: String) throws -> String {
        let filePath = try Self.path(key)
        return magic(key, filePath: filePath)
    }

    static func magic(_ key: String, filePath: URL) -> String {
        let pathData = filePath.path.data(using: .utf8)! as NSData
        let keyData = key.data(using: .utf8)! as NSData
        let sha = keyData.it_sha256() as NSData
        return "\(pathData.it_hexEncoded()) \(sha.it_hexEncoded())"

    }

    static func load<T: SecureUserDefaultStringTranscodable>(_ key: String) throws -> T? {
        let fileURL = try Self.path(key)
        // Check if the file exists before gettings its attributes to avoid an annoying exception
        // while debugging.
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        guard let owner = attributes[.ownerAccountID] as? Int, owner == 0 else {
            // Not owned by root
            return nil
        }
        guard let content = try? String(contentsOf: fileURL) else {
            return nil
        }
        guard let newline = content.range(of: "\n") else {
            return nil
        }
        let expectedMagic = magic(key, filePath: fileURL)
        let actualMagic = content.prefix(upTo: newline.lowerBound)
        guard actualMagic == expectedMagic else {
            throw SecureUserDefaultError.badMagic
        }
        let payload = content.suffix(from: newline.upperBound)
        return try SecureUserDefaultValue<T>(sudString: String(payload))?.value
    }

    static func delete(_ key: String) throws {
        let filename = try path(key)
        try FileManager.default.removeItem(at: filename)
    }

    static func store<T: SecureUserDefaultStringTranscodable>(_ key: String, value: T) throws {
        // Write to a temp file and then move it. If the destination is a link then it's not safe
        // to write to it.
        let unsafeURL = try self.path(key)
        let path = unsafeURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\\\\\"")
        let magic = Self.magic(key, filePath: URL(fileURLWithPath: path))
        let encodedValue = SecureUserDefaultValue<T>(value: value).encodedString
        let code =
        """
        do shell script "
            umask 077
            TF=$(mktemp)
            printf '%s\\n%s' '\(magic)' '\(encodedValue)' > \\"$TF\\" && \
                chmod a+r \\"$TF\\" && \
                mv \\"$TF\\" \\"\(path)\\" || \
                rm -f \\"$TF\\"
        " with prompt "iTerm2 needs to modify a secure setting." with administrator privileges
        """
        let script = NSAppleScript(source: code)
        var error: NSDictionary? = nil
        script?.executeAndReturnError(&error)
        guard error == nil else {
            let maybeReason = error?[NSAppleScript.errorBriefMessage] as? String
            throw SecureUserDefaultError.scriptError(maybeReason)
        }
    }
}

extension SecureUserDefault: SerializableUserDefault {
    func setFromSerialized(value: String) {
        let decoder = JSONDecoder()
        guard let savedValue = try? decoder.decode(T.self, from: value.data(using: .utf8) ?? Data()) else {
            DLog("Failed to decode \(value)")
            return
        }
        if savedValue != self.value {
            try? set(savedValue)
        }
    }

    func encode(to dictionary: inout [String: String]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            DLog("Failed to encode \(value) as JSON")
            return
        }
        if let jsonString = String(data: data, encoding: .utf8) {
            dictionary[key] = jsonString
        }
    }
}
