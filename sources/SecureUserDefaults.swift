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

extension String: SecureUserDefaultStringTranscodable {
    var sudString: String {
        self
    }
    init?(sudString string: String) throws {
        self = string
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
    lazy var enableSecureKeyboardEntryAutomatically = { SecureUserDefault<Bool>("EnableSecureKeyboardEntryAutomatically", defaultValue: true) }()
    lazy var enableAI = { SecureUserDefault<Bool>("EnableAI", defaultValue: false) }()
    lazy var browserBundleID = { SecureUserDefault<String>("BrowserBundleID", defaultValue: "") }()
    lazy var aiCompletionsEnabled = { SecureUserDefault<Bool>("AICompletions", defaultValue: false) }()
    private mutating func serializables() -> [any SerializableUserDefault] {
        [allowPaste,
         requireAuthToOpenPasswordmanager,
         enableSecureKeyboardEntryAutomatically,
         enableAI,
         browserBundleID,
         aiCompletionsEnabled]
    }
}

fileprivate let secureUserDefaultDidChange = NSNotification.Name("iTermSecureUserDefaultDidChange")

@objc
class iTermSecureUserDefaults: NSObject {
    static let didChange = secureUserDefaultDidChange
    @objc static let secureUserDefaultsDidChangeNotificationName = secureUserDefaultDidChange

    @objc static let instance = iTermSecureUserDefaults()
    @objc var requireAuthToOpenPasswordManager: Bool {
        get {
            return SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.value
        }
        set {
            try? SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.set(newValue)
        }
    }
    @objc var defaultValue_enableSecureKeyboardEntryAutomatically: Bool {
        return SecureUserDefaults.instance.enableSecureKeyboardEntryAutomatically.defaultValue
    }
    @objc var enableSecureKeyboardEntryAutomatically: Bool {
        get {
            return SecureUserDefaults.instance.enableSecureKeyboardEntryAutomatically.value
        }
        set {
            try? SecureUserDefaults.instance.enableSecureKeyboardEntryAutomatically.set(newValue)
        }
    }
    @objc var enableAI: Bool {
        get {
            return SecureUserDefaults.instance.enableAI.value
        }
        set {
            try? SecureUserDefaults.instance.enableAI.set(newValue)
        }
    }
    @objc var defaultValue_browserBundleID: String {
        return SecureUserDefaults.instance.browserBundleID.defaultValue
    }
    @objc var browserBundleID: String {
        get {
            return SecureUserDefaults.instance.browserBundleID.value
        }
        set {
            try? SecureUserDefaults.instance.browserBundleID.set(newValue)
        }
    }
    @objc var defaultValue_aiCompletionsEnabled: Bool {
        return SecureUserDefaults.instance.aiCompletionsEnabled.defaultValue
    }
    @objc var aiCompletionsEnabled: Bool {
        get {
            return SecureUserDefaults.instance.aiCompletionsEnabled.value
        }
        set {
            try? SecureUserDefaults.instance.aiCompletionsEnabled.set(newValue)
        }
    }
    @objc static var aiCompletionsKey: String {
        SecureUserDefaults.instance.aiCompletionsEnabled.key
    }
    @objc(resetAICompletionsEnabled) func resetAICompletionsEnabled() {
        try? SecureUserDefaults.instance.aiCompletionsEnabled.reset()
    }
}

// Save secure user defaults here if the home directory is on a network mount.
// Secure user defaults must be writable only by root and network mounts obviously can't do that.
fileprivate let FallbackFolder = "/usr/local/iTerm2-secure-settings"

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
    private var cached: T?

    enum SecureUserDefaultError: LocalizedError {
        case usrLocalIsFile
        case failedToCreateUsrLocal
        case badMagic
        case scriptError(String?)
        case directoryDoesNotExist

        var errorDescription: String? {
            switch self {
            case .usrLocalIsFile:
                "\(FallbackFolder) is a file, not a directory. Please remove it and try again."
            case .failedToCreateUsrLocal:
                "Failed to create \(FallbackFolder). Please manually create this folder."
            case .badMagic:
                "The secure user default is corrupted."
            case .scriptError(let message):
                message
            case .directoryDoesNotExist:
                "The containing directory for secure user defaults does not exist"
            }
        }
    }

    init(_ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var value: T {
        if let cached {
            return cached
        }
        if let value = try? get() {
            cached = value
            return value
        }
        cached = defaultValue
        return defaultValue
    }

    var url: URL? {
        return try? Self.path(key, create: false)
    }

    private func get() throws -> T {
        return try Self.load(key) ?? defaultValue
    }

    func set(_ newValue: T?) throws {
        cached = nil
        do {
            if let value = newValue {
                try Self.store(key, value: value)
            } else {
                try Self.delete(key)
            }
        } catch {
            iTermWarning.show(withTitle: error.localizedDescription,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: "NoSyncSecureUserDefaultsSetFailed",
                              silenceable: .kiTermWarningTypeTemporarilySilenceable,
                              heading: "Failed to Save Secure Setting",
                              window: nil)
            throw error
        }
    }

    func reset() throws {
        cached = nil
        try Self.delete(key)
    }

    private static func fallbackBaseDirectory(create: Bool) throws -> String {
        // When the user's home directory is not local, we use FallbackFolder
        let path = FallbackFolder

        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // If it already exists and is a directory, just use it.
                return path
            }
            if !create {
                throw SecureUserDefaultError.directoryDoesNotExist
            }
            // wtf, it exists but is not a directory.
            throw SecureUserDefaultError.usrLocalIsFile
        }
        if !create {
            throw SecureUserDefaultError.directoryDoesNotExist
        }
        // Create it since it does not exist.
        // Folder is owned by root without sticky bit so user can delete files without permission (that enables the delete() method).
        // If the user rewrites a file the ownership changes, which we can check for.
        // I'm not worried about TOCTOU because the threat model is concerned with accidental changes rather than an active attacker.
        let code =
        """
        do shell script "
            umask 000
            /bin/mkdir -m 777 -p \(path)
        " with prompt "iTerm2 needs to create \(path) to store secure settings because your home directory is on a network file system." with administrator privileges
        """
        let script = NSAppleScript(source: code)
        var error: NSDictionary? = nil
        script?.executeAndReturnError(&error)
        guard error == nil else {
            throw SecureUserDefaultError.failedToCreateUsrLocal
        }
        return path
    }

    private static func baseDirectory(create: Bool) throws -> String {
        guard let appSupportString = FileManager.default.applicationSupportDirectory() else {
            return try fallbackBaseDirectory(create: create)
        }
        if !FileManager.default.isWritableByRoot(path: appSupportString) {
            return try fallbackBaseDirectory(create: create)
        }
        return appSupportString
    }

    private static func path(_ key: String,
                             create: Bool) throws -> URL {
        precondition(key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil)
        let baseURL = URL(fileURLWithPath: try baseDirectory(create: create))
        return baseURL.appendingPathComponent(key).appendingPathExtension("secureSetting")
    }

    private static func magic(_ key: String, filePath: URL) -> String {
        let pathData = filePath.path.data(using: .utf8)! as NSData
        let keyData = key.data(using: .utf8)! as NSData
        let sha = keyData.it_sha256() as NSData
        return "\(pathData.it_hexEncoded()) \(sha.it_hexEncoded())"

    }

    private static func load<U: SecureUserDefaultStringTranscodable>(_ key: String) throws -> U? {
        let fileURL = try Self.path(key, create: false)
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
        return try SecureUserDefaultValue<U>(sudString: String(payload))?.value
    }

    private static func delete(_ key: String) throws {
        let filename = try path(key, create: false)
        try FileManager.default.removeItem(at: filename)

        NotificationCenter.default.post(name: secureUserDefaultDidChange, object: key)
    }

    private static func store<U: SecureUserDefaultStringTranscodable>(_ key: String, value: U) throws {
        // Write to a temp file and then move it. If the destination is a link then it's not safe
        // to write to it.
        let unsafeURL = try self.path(key, create: true)
        let path = unsafeURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\\\\\"")
        let magic = Self.magic(key, filePath: URL(fileURLWithPath: path))
        let encodedValue = SecureUserDefaultValue<U>(value: value).encodedString
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
        NotificationCenter.default.post(name: secureUserDefaultDidChange, object: key)
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
